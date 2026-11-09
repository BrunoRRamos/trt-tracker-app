import Foundation

// Carregador: leitura e validação do catálogo de compostos (`compound-catalog.json`, chaves em pt-BR).

/// Via de administração de uma variante do catálogo.
public enum AdministrationRoute: String, Codable, Sendable {
    case oral
    case intramuscular
}

/// Origem da meia-vida tabelada, conforme o levantamento de fontes.
public enum HalfLifeOrigin: String, Codable, Sendable {
    case measured = "medido"
    case extrapolated = "extrapolado"
}

/// Variante de um composto: éster, forma ou veículo, com meia-vida e fração ativa.
public struct CatalogVariant: Codable, Hashable, Sendable {
    public let ester: String?
    public let route: AdministrationRoute
    public let form: String?
    public let vehicle: String?
    public let halfLifeDays: Double
    /// Meia-vida tabelada, em horas.
    public let halfLifeHours: Double
    /// Fração de peso do esteroide-pai sobre o peso molecular do éster (%).
    public let activeDosePercent: Double
    public let note: String?
    /// Nil quando a fonte não informa se o valor foi medido ou extrapolado.
    public let halfLifeOrigin: HalfLifeOrigin?

    enum CodingKeys: String, CodingKey {
        case ester
        case route = "via"
        case form = "forma"
        case vehicle = "veiculo"
        case halfLifeDays = "meiaVidaDias"
        case halfLifeHours = "meiaVidaHoras"
        case activeDosePercent = "doseAtivaPercentual"
        case note = "observacao"
        case halfLifeOrigin = "origemMeiaVida"
    }
}

public struct CatalogCompound: Codable, Sendable, Identifiable {
    public let name: String
    public let chemicalName: String
    public let compoundClass: String?
    public let esters: [CatalogVariant]

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name = "nome"
        case chemicalName = "nomeQuimico"
        case compoundClass = "classe"
        case esters = "esteres"
    }
}

/// Uma opção selecionável no cadastro: composto + variante.
public struct CatalogEntry: Identifiable, Hashable, Sendable {
    public let compoundName: String
    public let chemicalName: String
    public let compoundClass: String?
    public let variant: CatalogVariant

    /// Chave estável persistida no composto.
    public var key: String {
        [compoundName, variant.ester ?? "", variant.route.rawValue, variant.form ?? "", variant.vehicle ?? ""]
            .joined(separator: "|")
    }

    public var id: String { key }

    private var qualifier: String? { [variant.form, variant.vehicle].compactMap { $0 }.first }

    /// Detalhe da variante: "Cipionato", "Undecanoato (Óleo de rícino)", "Suspensão aquosa".
    public var variantLabel: String? {
        switch (variant.ester, qualifier) {
        case let (ester?, qualifier?): return "\(ester) (\(qualifier))"
        case let (ester?, nil): return ester
        case let (nil, qualifier?): return qualifier
        case (nil, nil): return nil
        }
    }

    /// Nome do composto no protocolo: "Testosterona Cipionato", "Winstrol (Suspensão aquosa)".
    public var displayName: String {
        var name = compoundName
        if let ester = variant.ester { name += " \(ester)" }
        if let qualifier { name += " (\(qualifier))" }
        return name
    }

    public var activeFraction: Double { variant.activeDosePercent / 100 }
}

/// Problema encontrado na validação do catálogo.
public struct CatalogIssue: Equatable, Sendable, CustomStringConvertible {
    public enum Severity: Sendable { case error, warning }

    public let severity: Severity
    public let entryKey: String
    public let message: String

    public var description: String { "\(severity == .error ? "erro" : "aviso"): \(entryKey): \(message)" }
}

/// Catálogo de compostos carregado do JSON embutido no pacote.
public struct CompoundCatalog: Sendable {
    public let compounds: [CatalogCompound]
    public let entries: [CatalogEntry]
    public let issues: [CatalogIssue]

    private struct File: Decodable {
        let compounds: [CatalogCompound]
        enum CodingKeys: String, CodingKey { case compounds = "compostos" }
    }

    /// Monta o catálogo descartando variantes com erro de validação (avisos são mantidos).
    public init(compounds: [CatalogCompound]) {
        var issues: [CatalogIssue] = []
        var seen = Set<String>()
        var entries: [CatalogEntry] = []
        for compound in compounds {
            for variant in compound.esters {
                let entry = CatalogEntry(compoundName: compound.name, chemicalName: compound.chemicalName,
                                         compoundClass: compound.compoundClass, variant: variant)
                let found = Self.validate(entry, seen: seen)
                issues += found
                if found.contains(where: { $0.severity == .error }) { continue }
                seen.insert(entry.key)
                entries.append(entry)
            }
        }
        self.compounds = compounds
        self.entries = entries
        self.issues = issues
    }

    static func validate(_ entry: CatalogEntry, seen: Set<String>) -> [CatalogIssue] {
        var issues: [CatalogIssue] = []
        func add(_ severity: CatalogIssue.Severity, _ message: String) {
            issues.append(CatalogIssue(severity: severity, entryKey: entry.key, message: message))
        }
        let v = entry.variant
        if !(v.halfLifeHours > 0) { add(.error, "meiaVidaHoras deve ser maior que 0") }
        if !(v.activeDosePercent > 0 && v.activeDosePercent <= 100) { add(.error, "doseAtivaPercentual deve estar em (0, 100]") }
        if seen.contains(entry.key) { add(.error, "variante duplicada") }
        if v.halfLifeHours > 0, abs(v.halfLifeDays * 24 - v.halfLifeHours) > max(0.5, 0.05 * v.halfLifeHours) {
            add(.warning, "meiaVidaDias × 24 diverge de meiaVidaHoras")
        }
        return issues
    }

    public static func decode(_ data: Data) throws -> CompoundCatalog {
        CompoundCatalog(compounds: try JSONDecoder().decode(File.self, from: data).compounds)
    }

    public static let shared: CompoundCatalog = {
        guard let url = Bundle.module.url(forResource: "compound-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? decode(data) else {
            return CompoundCatalog(compounds: [])
        }
        return catalog
    }()

    public func entry(forKey key: String?) -> CatalogEntry? {
        guard let key else { return nil }
        return entries.first { $0.key == key }
    }

    public func entries(of compound: CatalogCompound) -> [CatalogEntry] {
        entries.filter { $0.compoundName == compound.name }
    }
}
