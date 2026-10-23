import Foundation

/// Leitura de números digitados, aceitando vírgula ou ponto como separador decimal (RF-UI-04).
public enum DecimalInput {
    private static let posix = Locale(identifier: "en_US_POSIX")

    public static func parse(_ text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty,
              normalized.range(of: #"^(\d+(\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil
        else { return nil }
        return Decimal(string: normalized, locale: posix)
    }

    /// Converte para inteiro escalado (ex.: ml → µl com `factor` 1000), arredondando.
    public static func scaled(_ value: Decimal, by factor: Int) -> Int {
        var input = value * Decimal(factor)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// Texto inicial de um campo a partir do valor escalado: 500 µl → "0,5".
    public static func text(fromScaled value: Int, factor: Int = 1000, maxFractionDigits: Int = 3) -> String {
        Formatting.decimal(Decimal(value) / Decimal(factor), minFractionDigits: 0, maxFractionDigits: maxFractionDigits)
            .replacingOccurrences(of: ".", with: "")
    }
}

public enum NumberInputError: Error, Equatable, Sendable {
    case empty
    case invalid
    case belowMinimum
    case aboveMaximum
    case step
}

public enum NameInputError: Error, Equatable, Sendable {
    case empty
    case tooLong(max: Int)
}

/// Regras de validação dos formulários.
public enum Validation {
    public static let protocolNameMax = 50
    public static let compoundNameMax = 40

    public static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// RF-PRO-01: 1 a 50 caracteres, sem espaços nas pontas.
    public static func protocolName(_ s: String) -> NameInputError? {
        name(s, max: protocolNameMax)
    }

    /// RF-VIA-01: obrigatório, até 40 caracteres.
    public static func compoundName(_ s: String) -> NameInputError? {
        name(s, max: compoundNameMax)
    }

    private static func name(_ s: String, max: Int) -> NameInputError? {
        let t = trimmed(s)
        if t.isEmpty { return .empty }
        if t.count > max { return .tooLong(max: max) }
        return nil
    }

    /// RF-PRO-01: fim igual ou posterior ao início.
    public static func isValidPeriod(start: LocalDay, end: LocalDay) -> Bool {
        end >= start
    }

    private static func scaledNumber(_ text: String, factor: Int, min: Int, max: Int?, step: Int?) -> Result<Int, NumberInputError> {
        let t = trimmed(text)
        if t.isEmpty { return .failure(.empty) }
        guard let value = DecimalInput.parse(t) else { return .failure(.invalid) }
        let scaled = DecimalInput.scaled(value, by: factor)
        if scaled < min { return .failure(.belowMinimum) }
        if let max, scaled > max { return .failure(.aboveMaximum) }
        if let step, scaled % step != 0 { return .failure(.step) }
        return .success(scaled)
    }

    /// Dose em mg, maior que 0 → µg.
    public static func dose(_ text: String) -> Result<Int, NumberInputError> {
        scaledNumber(text, factor: 1000, min: 1, max: 100_000_000, step: nil)
    }

    /// Volume total do vial: 0,1 a 100 ml, passo de 0,1 → µl.
    public static func vialVolume(_ text: String) -> Result<Int, NumberInputError> {
        scaledNumber(text, factor: 1000, min: 100, max: 100_000, step: 100)
    }

    /// Concentração: 1 a 1.000 mg/ml → µg/ml.
    public static func concentration(_ text: String) -> Result<Int, NumberInputError> {
        scaledNumber(text, factor: 1000, min: 1000, max: 1_000_000, step: nil)
    }

    /// Volume restante: de 0 até o volume total → µl.
    public static func remainingVolume(_ text: String, totalMicroliters: Int) -> Result<Int, NumberInputError> {
        scaledNumber(text, factor: 1000, min: 0, max: totalMicroliters, step: nil)
    }
}
