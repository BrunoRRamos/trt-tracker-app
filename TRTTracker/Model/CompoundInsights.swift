import Foundation
import TRTCore

/// Projeções e cálculos de estoque de um composto num instante (RF-VIA-06, 07 e 09).
struct CompoundInsights {
    let compound: Compound
    let now: Date
    let status: ProtocolStatus
    let currentVial: Vial?
    /// ml por aplicação no vial atual.
    let perApplicationMicroliters: Int?
    let upcoming: [Occurrence]
    let currentProjection: CurrentVialProjection?
    let stock: StockProjection
    /// Nº de aplicações previstas entre o início e o fim do protocolo.
    let protocolApplicationCount: Int
    let endDay: LocalDay

    init(compound: Compound, now: Date) {
        self.compound = compound
        self.now = now
        let today = LocalDay(now)
        let p = compound.treatmentProtocol
        status = p?.status(today: today) ?? .ended
        endDay = p?.endDay ?? today
        upcoming = OccurrenceEngine.upcoming(for: compound, now: now)
        let dates = upcoming.map(\.scheduledAt)

        currentVial = compound.currentVial
        if let vial = currentVial {
            let per = compound.perApplicationMicroliters(for: vial)
            perApplicationMicroliters = per
            currentProjection = Projection.currentVial(remainingMicroliters: vial.remainingMicroliters,
                                                       perApplicationMicroliters: per, upcoming: dates)
        } else {
            perApplicationMicroliters = nil
            currentProjection = nil
        }
        stock = Projection.stock(vials: compound.activeVials.map(\.supply),
                                 doseMicrograms: compound.doseMicrograms, upcoming: dates)
        if let p {
            protocolApplicationCount = compound.schedule.applicationCount(start: p.startDay, end: p.endDay)
        } else {
            protocolApplicationCount = 0
        }
    }

    /// Vial de referência = vial atual (RF-VIA-09).
    var currentReference: VialReference? { currentVial?.reference }

    func requirement(reference: VialReference?) -> VialRequirement? {
        guard let reference else { return nil }
        return VialRequirement.compute(doseMicrograms: compound.doseMicrograms,
                                       applicationCount: protocolApplicationCount, reference: reference)
    }

    var stockMicrograms: Int { compound.activeVials.reduce(0) { $0 + $1.remainingMicrograms } }

    var neededMicrogramsUntilEnd: Int { compound.doseMicrograms * upcoming.count }

    /// Vials que ainda faltam comprar de hoje até o fim (RF-VIA-09).
    func vialsToBuy(reference: VialReference?) -> Int? {
        guard let reference, reference.capacityMicrograms > 0 else { return nil }
        return VialRequirement.vialsToBuy(neededMicrograms: neededMicrogramsUntilEnd,
                                          stockMicrograms: stockMicrograms,
                                          perVialMicrograms: reference.capacityMicrograms)
    }

    /// Volume que falta, na concentração de referência (RF-VIA-07).
    func shortageMicroliters(reference: VialReference?) -> Int? {
        guard let reference, reference.concentrationMicrogramsPerMl > 0 else { return nil }
        return VolumeMath.microliters(micrograms: stock.shortageMicrograms,
                                      concentrationMicrogramsPerMl: reference.concentrationMicrogramsPerMl)
    }

    /// Dias entre a data de falta e o fim do protocolo.
    var shortageDaysBeforeEnd: Int? {
        guard let shortage = stock.firstShortage else { return nil }
        return LocalDay(shortage).days(to: endDay)
    }

    /// Aplicações restantes de um vial (parte inteira de ml restantes ÷ ml por aplicação).
    func applicationsRemaining(in vial: Vial) -> Int {
        VolumeMath.applicationsRemaining(remainingMicroliters: vial.remainingMicroliters,
                                         perApplicationMicroliters: compound.perApplicationMicroliters(for: vial))
    }
}
