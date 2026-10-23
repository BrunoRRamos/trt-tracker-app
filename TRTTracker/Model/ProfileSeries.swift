import Foundation
import TRTCore

/// Perfil plasmático normalizado de um composto no protocolo (C / pico de uma dose única),
/// como envelope sobre a varredura de k_e.
struct ProfileSeries: Identifiable {
    let id: UUID
    let name: String
    let colorIndex: Int
    let entry: CatalogEntry
    let doses: [RelativeDose]
    let envelope: [EnvelopePoint]
    let steadyState: SteadyStateEnvelope?

    var origin: HalfLifeOrigin? { entry.variant.halfLifeOrigin }
    var absorptionHalfLifeHours: Double { entry.variant.halfLifeHours }

    /// Faixa do perfil num instante (mínimo e máximo sobre os valores de k_e).
    func band(at date: Date) -> ClosedRange<Double> {
        let ka = ReleaseKinetics.absorptionRate(halfLifeHours: absorptionHalfLifeHours)
        let values = ReleaseKinetics.eliminationHalfLivesHours.map {
            RegimenProfile.level(at: date, doses: doses, ka: ka, ke: ReleaseKinetics.rate(halfLifeHours: $0))
        }
        return (values.min() ?? 0)...(values.max() ?? 0)
    }
}

enum ProfileSeriesBuilder {
    /// Cauda após o fim do protocolo: até t_99 do éster, entre 1 e 60 dias.
    static func tail(absorptionHalfLifeHours: Double) -> TimeInterval {
        let ka = ReleaseKinetics.absorptionRate(halfLifeHours: absorptionHalfLifeHours)
        return min(60 * 86400, max(86400, ReleaseKinetics.timeToFraction(ka: ka, fraction: 0.99) * 3600))
    }

    /// Período do gráfico: do início (ou do primeiro registro) ao fim mais a cauda de liberação.
    static func range(for treatment: TreatmentProtocol, compounds: [Compound]) -> ClosedRange<Date> {
        let firstEvent = compounds.flatMap(\.events).filter { $0.kind == .applied }.map(\.performedAt).min()
        let start = min(treatment.startDay.date(), firstEvent ?? .distantFuture)
        let longest = compounds.compactMap { $0.depotEntry?.variant.halfLifeHours }.max() ?? 24
        let end = treatment.endDay.date(hour: 23, minute: 59).addingTimeInterval(tail(absorptionHalfLifeHours: longest))
        return start...max(end, start.addingTimeInterval(86400))
    }

    /// Doses relativas à dose padrão do composto: registradas até agora e previstas daí em diante.
    static func doses(for compound: Compound, now: Date) -> [RelativeDose] {
        let reference = Double(max(1, compound.doseMicrograms))
        let past = compound.events
            .filter { $0.kind == .applied && $0.performedAt <= now }
            .map { RelativeDose(date: $0.performedAt, amount: Double($0.doseMicrograms) / reference) }
        let future = OccurrenceEngine.upcoming(for: compound, now: now).map { RelativeDose(date: $0.scheduledAt, amount: 1) }
        return (past + future).sorted { $0.date < $1.date }
    }

    static func series(for compound: Compound, now: Date, range: ClosedRange<Date>) -> ProfileSeries? {
        guard let entry = compound.depotEntry else { return nil }
        let doses = doses(for: compound, now: now)
        let end = compound.treatmentProtocol?.endDay.date(hour: 23, minute: 59) ?? range.upperBound
        return make(id: compound.id, name: compound.name, colorIndex: compound.sortIndex, entry: entry,
                    doses: doses, range: range, steadyStateEnd: end)
    }

    /// Prévia no formulário: aplicações previstas pela agenda do rascunho, do início ao fim, na dose padrão.
    static func preview(name: String, colorIndex: Int, entry: CatalogEntry, schedule: Schedule,
                        start: LocalDay, end: LocalDay, hour: Int, minute: Int) -> ProfileSeries? {
        guard entry.isDepotModelEligible, end >= start else { return nil }
        let doses = schedule.days(from: start, through: end, protocolStart: start)
            .map { RelativeDose(date: $0.date(hour: hour, minute: minute), amount: 1) }
        let endDate = end.date(hour: 23, minute: 59)
        let range = start.date()...endDate.addingTimeInterval(tail(absorptionHalfLifeHours: entry.variant.halfLifeHours))
        return make(id: UUID(), name: name, colorIndex: colorIndex, entry: entry, doses: doses, range: range, steadyStateEnd: endDate)
    }

    private static func make(id: UUID, name: String, colorIndex: Int, entry: CatalogEntry, doses: [RelativeDose],
                             range: ClosedRange<Date>, steadyStateEnd: Date) -> ProfileSeries {
        let halfLife = entry.variant.halfLifeHours
        return ProfileSeries(
            id: id, name: name, colorIndex: colorIndex, entry: entry, doses: doses,
            envelope: RegimenProfile.envelope(doses: doses, absorptionHalfLifeHours: halfLife,
                                              from: range.lowerBound, to: range.upperBound),
            steadyState: RegimenProfile.steadyState(doses: doses, absorptionHalfLifeHours: halfLife, to: steadyStateEnd))
    }
}
