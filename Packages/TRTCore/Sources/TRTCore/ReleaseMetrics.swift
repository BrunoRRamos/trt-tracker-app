import Foundation

/// Métricas derivadas de um éster, comparáveis entre ésteres.
public struct ReleaseMetrics: Identifiable, Sendable {
    public struct TMax: Sendable, Equatable {
        /// Meia-vida de eliminação assumida; t_max sempre é exibido com ela.
        public let eliminationHalfLifeHours: Double
        public let hours: Double
    }

    public let entry: CatalogEntry
    public let halfLifeHours: Double
    public let origin: HalfLifeOrigin?
    /// k_a [h⁻¹]
    public let ka: Double
    /// 90% e 99% da dose liberados [h]; dependem só de k_a.
    public let t90: Double
    public let t99: Double
    /// C_max relativo ao éster de referência (propionato = 1): k_a / k_a,ref, para dose molar igual do esteroide-pai.
    public let cmaxRelative: Double
    public let tMax: [TMax]
    public let uncertainty: CmaxUncertainty?

    public var id: String { entry.key }
}

/// Propagação de incerteza do C_max absoluto (seção 7): intervalo percentil 5–95 e a razão P95/P5.
public struct CmaxUncertainty: Sendable, Equatable {
    public let p5: Double
    public let p95: Double
    /// k_e assumido no cenário de maior razão.
    public let eliminationHalfLifeHours: Double
    public var ratio: Double { p5 > 0 ? p95 / p5 : .infinity }
}

/// Parâmetros da simulação de Monte Carlo do C_max absoluto.
public struct UncertaintyParameters: Sendable {
    /// V_d em L/kg, log-uniforme.
    public var volumeOfDistribution: ClosedRange<Double> = 0.5...2.0
    /// Biodisponibilidade do depósito, uniforme.
    public var bioavailability: ClosedRange<Double> = 0.5...1.0
    /// Fator multiplicativo (log-uniforme, ×/÷) da incerteza do t½: estreito para medido, amplo para extrapolado.
    public var measuredHalfLifeFactor: Double = 1.2
    public var unverifiedHalfLifeFactor: Double = 2.0
    public var samples = 10_000

    public init() {}

    public func halfLifeFactor(_ origin: HalfLifeOrigin?) -> Double {
        origin == .measured ? measuredHalfLifeFactor : unverifiedHalfLifeFactor
    }
}

public enum ReleaseMetricsBuilder {
    public static func metrics(for entries: [CatalogEntry], reference: CatalogEntry?,
                               uncertainty parameters: UncertaintyParameters? = UncertaintyParameters()) -> [ReleaseMetrics] {
        let referenceKa = reference.map { ReleaseKinetics.absorptionRate(halfLifeHours: $0.variant.halfLifeHours) }
        return entries.filter(\.isDepotModelEligible).map { entry in
            let halfLife = entry.variant.halfLifeHours
            let ka = ReleaseKinetics.absorptionRate(halfLifeHours: halfLife)
            let tMax = ReleaseKinetics.eliminationHalfLivesHours.map {
                ReleaseMetrics.TMax(eliminationHalfLifeHours: $0, hours: ReleaseKinetics.tMax(ka: ka, ke: ReleaseKinetics.rate(halfLifeHours: $0)))
            }
            return ReleaseMetrics(
                entry: entry, halfLifeHours: halfLife, origin: entry.variant.halfLifeOrigin, ka: ka,
                t90: ReleaseKinetics.timeToFraction(ka: ka, fraction: 0.9),
                t99: ReleaseKinetics.timeToFraction(ka: ka, fraction: 0.99),
                cmaxRelative: referenceKa.map { ka / $0 } ?? .nan,
                tMax: tMax,
                uncertainty: parameters.map { cmaxUncertainty(halfLifeHours: halfLife, origin: entry.variant.halfLifeOrigin, key: entry.key, parameters: $0) })
        }
        .sorted { $0.halfLifeHours < $1.halfLifeHours }
    }

    /// Monte Carlo sobre a Bateman completa: C_max ∝ (F/V_d) · max(C_bruto(k_a, k_e)), com V_d, F e t½ amostrados.
    /// A dose e o peso corporal são fixos e se cancelam na razão P95/P5. Repete para cada k_e da varredura
    /// e reporta o cenário de maior razão. Semente derivada da chave: resultado reprodutível.
    public static func cmaxUncertainty(halfLifeHours: Double, origin: HalfLifeOrigin?, key: String,
                                       parameters: UncertaintyParameters) -> CmaxUncertainty {
        let factor = log(parameters.halfLifeFactor(origin))
        let vd = parameters.volumeOfDistribution
        let f = parameters.bioavailability
        var worst: CmaxUncertainty?
        for eliminationHalfLife in ReleaseKinetics.eliminationHalfLivesHours {
            var rng = SplitMix64(seed: stableHash(key) ^ UInt64(eliminationHalfLife * 1000))
            let ke = ReleaseKinetics.rate(halfLifeHours: eliminationHalfLife)
            var values: [Double] = []
            values.reserveCapacity(parameters.samples)
            for _ in 0..<parameters.samples {
                let volume = exp(rng.uniform(in: log(vd.lowerBound)...log(vd.upperBound)))
                let bioavailability = rng.uniform(in: f)
                let halfLife = halfLifeHours * exp(rng.uniform(in: -factor...factor))
                let ka = ReleaseKinetics.absorptionRate(halfLifeHours: halfLife)
                values.append(bioavailability / volume * ReleaseKinetics.batemanPeak(ka: ka, ke: ke))
            }
            values.sort()
            let result = CmaxUncertainty(p5: values[Int(Double(values.count) * 0.05)],
                                         p95: values[Int(Double(values.count) * 0.95) - 1],
                                         eliminationHalfLifeHours: eliminationHalfLife)
            if worst == nil || result.ratio > worst!.ratio { worst = result }
        }
        return worst!
    }

    /// metricas.csv — separador vírgula e ponto decimal, para leitura por ferramentas de análise.
    public static func csv(_ metrics: [ReleaseMetrics]) -> String {
        let keHeaders = ReleaseKinetics.eliminationHalfLivesHours.map { "t_max_h_ke_meia_vida_\(number($0))h" }
        var rows = [(["composto", "ester", "veiculo", "t_meia_h", "origem_t_meia", "k_a_por_h", "t_90_h", "t_99_h",
                      "cmax_relativo_propionato"] + keHeaders + ["cmax_p95_sobre_p5", "cmax_incerteza_ke_meia_vida_h"])
            .joined(separator: ",")]
        for m in metrics {
            var fields = [m.entry.compoundName, m.entry.variant.ester ?? "", m.entry.variant.vehicle ?? "",
                          number(m.halfLifeHours), m.origin?.rawValue ?? "nao_informado",
                          number(m.ka, digits: 6), number(m.t90), number(m.t99), number(m.cmaxRelative, digits: 4)]
            fields += m.tMax.map { number($0.hours) }
            fields += [m.uncertainty.map { number($0.ratio) } ?? "", m.uncertainty.map { number($0.eliminationHalfLifeHours) } ?? ""]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double, digits: Int = 2) -> String {
        guard value.isFinite else { return "" }
        let s = String(format: "%.\(digits)f", value)
        return s.contains(".") ? s.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) : s
    }

    private static func escape(_ field: String) -> String {
        field.contains(",") || field.contains("\"") ? "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\"" : field
    }

    /// FNV-1a: hash estável entre execuções (o `hashValue` do Swift é aleatorizado).
    static func stableHash(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// Gerador pseudoaleatório determinístico.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func uniform(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
