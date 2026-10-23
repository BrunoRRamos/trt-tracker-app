import Foundation
import TRTCore

/// Aplicação prevista, derivada da agenda (RF-AGE-02). Não é persistida.
struct Occurrence: Identifiable {
    let compound: Compound
    let day: LocalDay
    let scheduledAt: Date
    /// Registro ou pulo vinculado, se houver.
    let event: DoseEvent?

    var id: String { "\(compound.id.uuidString)|\(day.key)" }

    func status(now: Date) -> OccurrenceStatus {
        let resolution: OccurrenceResolution? = event.map { $0.kind == .applied ? .applied : .skipped }
        return .resolve(scheduledAt: scheduledAt, resolution: resolution, now: now)
    }
}

enum OccurrenceEngine {
    /// Aplicações previstas do composto no intervalo, limitadas ao período do protocolo,
    /// no horário do lembrete do composto e no calendário/fuso local.
    /// Protocolos encerrados não geram aplicações previstas (RF-PRO-02).
    static func occurrences(for compound: Compound, from: LocalDay? = nil, through: LocalDay? = nil, today: LocalDay) -> [Occurrence] {
        guard let p = compound.treatmentProtocol, p.status(today: today) != .ended else { return [] }
        let lower = max(from ?? p.startDay, p.startDay)
        let upper = min(through ?? p.endDay, p.endDay)
        guard lower <= upper else { return [] }
        let time = compound.reminderTime
        let events = compound.eventsByDayKey
        return compound.schedule.days(from: lower, through: upper, protocolStart: p.startDay).map { day in
            Occurrence(compound: compound, day: day,
                       scheduledAt: day.date(hour: time.hour, minute: time.minute),
                       event: events[day.key])
        }
    }

    /// Previstas a partir de agora até o fim do protocolo, sem registradas, puladas ou atrasadas (seção 8, passo 1).
    static func upcoming(for compound: Compound, now: Date) -> [Occurrence] {
        let today = LocalDay(now)
        return occurrences(for: compound, from: today, today: today)
            .filter { $0.event == nil && $0.scheduledAt > now }
    }

    static func occurrence(for compound: Compound, dayKey: String, now: Date) -> Occurrence? {
        guard let day = LocalDay(key: dayKey) else { return nil }
        return occurrences(for: compound, from: day, through: day, today: LocalDay(now)).first
    }

    /// Próxima aplicação prevista do protocolo.
    static func next(in treatment: TreatmentProtocol, now: Date) -> Occurrence? {
        treatment.compounds
            .compactMap { upcoming(for: $0, now: now).first }
            .min { $0.scheduledAt < $1.scheduledAt }
    }
}
