import Foundation

/// Vial usado como referência nos cálculos de quantidade (volume × concentração).
public struct VialReference: Equatable, Sendable {
    public let volumeMicroliters: Int
    public let concentrationMicrogramsPerMl: Int

    public init(volumeMicroliters: Int, concentrationMicrogramsPerMl: Int) {
        self.volumeMicroliters = volumeMicroliters
        self.concentrationMicrogramsPerMl = concentrationMicrogramsPerMl
    }

    public var capacityMicrograms: Int {
        VolumeMath.micrograms(microliters: volumeMicroliters, concentrationMicrogramsPerMl: concentrationMicrogramsPerMl)
    }

    public var isValid: Bool { volumeMicroliters > 0 && concentrationMicrogramsPerMl > 0 }
}

/// Quantidade mínima de vials para o protocolo inteiro (RF-VIA-09).
public struct VialRequirement: Equatable, Sendable {
    public let applicationCount: Int
    public let totalMicrograms: Int
    public let totalMicroliters: Int
    public let vialsNeeded: Int
    public let leftoverMicroliters: Int
    public let reference: VialReference

    /// vials mínimos = ⌈dose × nº de aplicações ÷ (volume × concentração)⌉
    public static func compute(doseMicrograms: Int, applicationCount: Int, reference: VialReference) -> VialRequirement? {
        guard doseMicrograms > 0, reference.isValid, reference.capacityMicrograms > 0 else { return nil }
        let total = doseMicrograms * max(0, applicationCount)
        let capacity = reference.capacityMicrograms
        let vials = VolumeMath.divideRoundedUp(total, capacity)
        let leftoverMicrograms = vials * capacity - total
        return VialRequirement(
            applicationCount: applicationCount,
            totalMicrograms: total,
            totalMicroliters: VolumeMath.microliters(micrograms: total, concentrationMicrogramsPerMl: reference.concentrationMicrogramsPerMl),
            vialsNeeded: vials,
            leftoverMicroliters: VolumeMath.microliters(micrograms: leftoverMicrograms, concentrationMicrogramsPerMl: reference.concentrationMicrogramsPerMl),
            reference: reference
        )
    }

    /// vials a comprar = max(0, ⌈(mg necessários até o fim − mg em estoque) ÷ mg por vial⌉)
    public static func vialsToBuy(neededMicrograms: Int, stockMicrograms: Int, perVialMicrograms: Int) -> Int {
        guard perVialMicrograms > 0 else { return 0 }
        return max(0, VolumeMath.divideRoundedUp(neededMicrograms - stockMicrograms, perVialMicrograms))
    }
}
