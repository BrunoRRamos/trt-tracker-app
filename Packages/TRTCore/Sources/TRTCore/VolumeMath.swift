import Foundation

/// Unidades internas, todas inteiras para evitar erro de ponto flutuante (seção 8):
/// - volume em microlitros (µl, 0,001 ml);
/// - massa em microgramas (µg, 0,001 mg);
/// - concentração em µg/ml (mg/ml × 1000).
public enum VolumeMath {
    /// Divisão inteira arredondada (meio para cima), para valores não negativos.
    static func divideRounded(_ numerator: Int, _ denominator: Int) -> Int {
        guard denominator > 0 else { return 0 }
        return (numerator + denominator / 2) / denominator
    }

    static func divideRoundedUp(_ numerator: Int, _ denominator: Int) -> Int {
        guard denominator > 0, numerator > 0 else { return 0 }
        return (numerator + denominator - 1) / denominator
    }

    /// ml por aplicação = dose (mg) ÷ concentração (mg/ml).
    public static func microlitersPerApplication(doseMicrograms: Int, concentrationMicrogramsPerMl: Int) -> Int {
        guard doseMicrograms > 0, concentrationMicrogramsPerMl > 0 else { return 0 }
        return divideRounded(doseMicrograms * 1000, concentrationMicrogramsPerMl)
    }

    /// Massa contida num volume (arredondada para baixo).
    public static func micrograms(microliters: Int, concentrationMicrogramsPerMl: Int) -> Int {
        guard microliters > 0, concentrationMicrogramsPerMl > 0 else { return 0 }
        return microliters * concentrationMicrogramsPerMl / 1000
    }

    /// Volume que contém uma massa (arredondado).
    public static func microliters(micrograms: Int, concentrationMicrogramsPerMl: Int) -> Int {
        guard micrograms > 0, concentrationMicrogramsPerMl > 0 else { return 0 }
        return divideRounded(micrograms * 1000, concentrationMicrogramsPerMl)
    }

    /// UI de seringa U-100: 1 ml = 100 UI, ou seja, 1 UI = 10 µl.
    public static func insulinUnits(microliters: Int) -> Decimal {
        Decimal(microliters) / 10
    }

    /// Aplicações restantes = parte inteira de ml restantes ÷ ml por aplicação.
    public static func applicationsRemaining(remainingMicroliters: Int, perApplicationMicroliters: Int) -> Int {
        guard perApplicationMicroliters > 0, remainingMicroliters > 0 else { return 0 }
        return remainingMicroliters / perApplicationMicroliters
    }

    public static func percentRemaining(remainingMicroliters: Int, totalMicroliters: Int) -> PercentRemaining {
        guard totalMicroliters > 0, remainingMicroliters > 0 else { return .whole(0) }
        let value = min(remainingMicroliters, totalMicroliters) * 100 / totalMicroliters
        return value == 0 ? .lessThanOne : .whole(value)
    }

    /// Fração de 0 a 1 para o anel do vial.
    public static func fractionRemaining(remainingMicroliters: Int, totalMicroliters: Int) -> Double {
        guard totalMicroliters > 0 else { return 0 }
        return min(1, max(0, Double(remainingMicroliters) / Double(totalMicroliters)))
    }
}

/// Porcentagem restante exibida como inteiro arredondado para baixo, ou "<1%" (RF-VIA-04).
public enum PercentRemaining: Equatable, Sendable {
    case whole(Int)
    case lessThanOne
}
