import Foundation
import SwiftData
import TRTCore

/// Registro, pulo, edição e exclusão de aplicações (RF-AGE-05 a 07).
/// Só aplicações registradas descontam volume; o nível do vial é derivado das partes descontadas.
@MainActor
enum DoseService {
    /// Previstas que um registro pode vincular: atrasadas (até virarem "Não registrada") e as de hoje, da mais antiga à mais nova.
    static func linkableOccurrences(for compound: Compound, now: Date) -> [Occurrence] {
        let today = LocalDay(now)
        return OccurrenceEngine.occurrences(for: compound, from: today.adding(days: -7), through: today, today: today)
            .filter { $0.event == nil && $0.status(now: now) != .missed }
    }

    /// Vínculo padrão: a atrasada mais antiga ou a de hoje.
    static func defaultOccurrence(for compound: Compound, now: Date) -> Occurrence? {
        linkableOccurrences(for: compound, now: now).first
    }

    @discardableResult
    static func register(compound: Compound, doseMicrograms: Int, performedAt: Date, vial: Vial?,
                         dayKey: String?, note: String, in context: ModelContext) -> DoseEvent {
        let event = DoseEvent(kindRaw: DoseEvent.Kind.applied.rawValue, scheduledDayKey: dayKey,
                              performedAt: performedAt, doseMicrograms: doseMicrograms, note: note)
        context.insert(event)
        event.compound = compound
        consume(event: event, startingAt: vial, compound: compound, in: context)
        clearSnoozes(of: compound, dayKey: dayKey, in: context)
        try? context.save()
        NotificationScheduler.shared.removeDelivered(compound: compound, dayKey: dayKey)
        return event
    }

    @discardableResult
    static func skip(compound: Compound, dayKey: String, reason: String, in context: ModelContext) -> DoseEvent {
        let event = DoseEvent(kindRaw: DoseEvent.Kind.skipped.rawValue, scheduledDayKey: dayKey,
                              performedAt: Date(), doseMicrograms: 0, note: reason)
        context.insert(event)
        event.compound = compound
        clearSnoozes(of: compound, dayKey: dayKey, in: context)
        try? context.save()
        NotificationScheduler.shared.removeDelivered(compound: compound, dayKey: dayKey)
        return event
    }

    /// Edita um registro: devolve o volume descontado e desconta de novo com os valores novos (RF-VIA-04).
    static func update(event: DoseEvent, doseMicrograms: Int, performedAt: Date, vial: Vial?,
                       note: String, in context: ModelContext) {
        event.note = note
        guard event.kind == .applied, let compound = event.compound else {
            try? context.save()
            return
        }
        releaseUsages(of: event, in: context)
        event.doseMicrograms = doseMicrograms
        event.performedAt = performedAt
        consume(event: event, startingAt: vial, compound: compound, in: context)
        try? context.save()
    }

    /// Exclui um registro ou pulo, devolvendo o volume ao vial.
    static func delete(event: DoseEvent, in context: ModelContext) {
        releaseUsages(of: event, in: context)
        event.compound = nil
        context.delete(event)
        try? context.save()
    }

    /// Desconta a dose a partir do vial escolhido e, se faltar, completa com os próximos da fila (RF-VIA-03).
    /// Sem vial, a aplicação é registrada sem descontar estoque.
    private static func consume(event: DoseEvent, startingAt vial: Vial?, compound: Compound, in context: ModelContext) {
        guard let vial, vial.remainingMicroliters > 0 else { return }
        let chain = [vial] + compound.activeVials.filter { $0.id != vial.id }
        var supplies = chain.map(\.supply)
        let result = Consumption.consume(doseMicrograms: event.doseMicrograms, from: &supplies)
        for (index, portion) in result.portions.enumerated() {
            guard let target = chain.first(where: { $0.id == portion.vialID }) else { continue }
            let usage = VialUsage(microliters: portion.microliters, order: index)
            context.insert(usage)
            usage.vial = target
            usage.event = event
        }
    }

    private static func releaseUsages(of event: DoseEvent, in context: ModelContext) {
        for usage in event.usages {
            usage.vial = nil
            usage.event = nil
            context.delete(usage)
        }
        event.usages = []
    }

    private static func clearSnoozes(of compound: Compound, dayKey: String?, in context: ModelContext) {
        guard let dayKey else { return }
        for snooze in compound.snoozes where snooze.scheduledDayKey == dayKey {
            snooze.compound = nil
            context.delete(snooze)
        }
    }
}
