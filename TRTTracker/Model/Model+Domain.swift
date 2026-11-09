import Foundation
import SwiftData
import TRTCore

extension TreatmentProtocol {
    var startDay: LocalDay {
        get { LocalDay(key: startDayKey) ?? .today() }
        set { startDayKey = newValue.key }
    }

    var endDay: LocalDay {
        get { LocalDay(key: endDayKey) ?? .today() }
        set { endDayKey = newValue.key }
    }

    var frequency: Frequency {
        get { Frequency(rawValue: frequencyRaw) ?? .twoTimesWeek }
        set { frequencyRaw = newValue.rawValue }
    }

    var weekdays: Set<Weekday> {
        get { Weekday.set(fromMask: weekdayMask) }
        set { weekdayMask = Weekday.mask(newValue) }
    }

    var alternateAnchor: LocalDay? {
        get { alternateAnchorKey.flatMap(LocalDay.init(key:)) }
        set { alternateAnchorKey = newValue?.key }
    }

    var schedule: Schedule {
        Schedule(frequency: frequency, weekdays: weekdays, alternateAnchor: alternateAnchor)
    }

    func status(today: LocalDay) -> ProtocolStatus {
        .resolve(start: startDay, end: endDay, endedManually: endedManually, today: today)
    }

    var orderedCompounds: [Compound] {
        compounds.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    /// Total de dias do protocolo, inclusive.
    var totalDays: Int { max(1, startDay.days(to: endDay) + 1) }

    /// Dias decorridos até hoje (inclusive), limitado ao total.
    func elapsedDays(today: LocalDay) -> Int {
        min(totalDays, max(0, startDay.days(to: today) + 1))
    }

    var hasAnyReminderEnabled: Bool {
        compounds.contains { $0.reminderEnabled }
    }
}

extension Compound {
    var ownFrequency: Frequency {
        get { Frequency(rawValue: frequencyRaw) ?? .twoTimesWeek }
        set { frequencyRaw = newValue.rawValue }
    }

    var ownWeekdays: Set<Weekday> {
        get { Weekday.set(fromMask: weekdayMask) }
        set { weekdayMask = Weekday.mask(newValue) }
    }

    var ownAlternateAnchor: LocalDay? {
        get { alternateAnchorKey.flatMap(LocalDay.init(key:)) }
        set { alternateAnchorKey = newValue?.key }
    }

    /// Agenda efetiva: a do protocolo por padrão, ou a própria (RF-AGE-01).
    var schedule: Schedule {
        if usesProtocolSchedule, let p = treatmentProtocol { return p.schedule }
        return Schedule(frequency: ownFrequency, weekdays: ownWeekdays, alternateAnchor: ownAlternateAnchor)
    }

    /// Horário das aplicações previstas e do lembrete (RF-NOT-01).
    var reminderTime: (hour: Int, minute: Int) {
        if usesCustomReminderTime || treatmentProtocol == nil { return (reminderHour, reminderMinute) }
        return (treatmentProtocol!.reminderHour, treatmentProtocol!.reminderMinute)
    }

    /// Vials disponíveis (não arquivados e com líquido), na ordem da fila. O primeiro é o vial atual.
    var activeVials: [Vial] {
        vials.filter { !$0.isArchived && $0.remainingMicroliters > 0 }.sorted(by: Vial.queueOrder)
    }

    var currentVial: Vial? { activeVials.first }

    var stockVials: [Vial] { Array(activeVials.dropFirst()) }

    /// Esgotados e arquivados.
    var inactiveVials: [Vial] {
        vials.filter { $0.isArchived || $0.remainingMicroliters == 0 }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Número do vial na ordem de cadastro ("Vial 1", "Vial 2"…).
    func number(of vial: Vial) -> Int {
        let ordered = vials.sorted { $0.createdAt < $1.createdAt }
        return (ordered.firstIndex { $0.id == vial.id } ?? 0) + 1
    }

    func displayName(of vial: Vial) -> String {
        let base = String(localized: "Vial \(number(of: vial))")
        return vial.nickname.isEmpty ? base : "\(base) · \(vial.nickname)"
    }

    /// Registro ou pulo vinculado a cada dia previsto; o registro de aplicação tem prioridade.
    var eventsByDayKey: [String: DoseEvent] {
        var map: [String: DoseEvent] = [:]
        for event in events {
            guard let key = event.scheduledDayKey else { continue }
            if let existing = map[key], existing.kind == .applied { continue }
            map[key] = event
        }
        return map
    }

    func perApplicationMicroliters(for vial: Vial) -> Int {
        VolumeMath.microlitersPerApplication(doseMicrograms: doseMicrograms, concentrationMicrogramsPerMl: vial.concentrationMicrogramsPerMl)
    }

    var lastRegisteredVial: Vial? {
        vials.max { $0.createdAt < $1.createdAt }
    }

    /// Variante do catálogo de compostos; nil para compostos fora da lista.
    var catalogEntry: CatalogEntry? { CompoundCatalog.shared.entry(forKey: catalogKey) }

    /// Fração de composto ativo sobre o peso do éster.
    var activeFraction: Double { min(1, max(0, activeDosePercent / 100)) }

    /// Nome do composto ativo ("Testosterone"), para as frases de dose ativa.
    var activeSubstanceName: String { catalogEntry?.compoundName ?? name }

    /// Dose ativa por aplicação, em mg.
    var activeDoseMilligrams: Double { Double(doseMicrograms) / 1000 * activeFraction }
}

extension Vial {
    static func queueOrder(_ a: Vial, _ b: Vial) -> Bool {
        if a.queueIndex != b.queueIndex { return a.queueIndex < b.queueIndex }
        return a.createdAt < b.createdAt
    }

    var usedMicroliters: Int { usages.reduce(0) { $0 + $1.microliters } }

    var adjustedMicroliters: Int { adjustments.reduce(0) { $0 + $1.afterMicroliters - $1.beforeMicroliters } }

    /// ml restantes = ml no cadastro − Σ ml aplicados ± Σ ajustes; nunca negativo (RF-VIA-04).
    var remainingMicroliters: Int {
        min(totalMicroliters, max(0, initialMicroliters - usedMicroliters + adjustedMicroliters))
    }

    var remainingMicrograms: Int {
        VolumeMath.micrograms(microliters: remainingMicroliters, concentrationMicrogramsPerMl: concentrationMicrogramsPerMl)
    }

    var percentRemaining: PercentRemaining {
        VolumeMath.percentRemaining(remainingMicroliters: remainingMicroliters, totalMicroliters: totalMicroliters)
    }

    var fractionRemaining: Double {
        VolumeMath.fractionRemaining(remainingMicroliters: remainingMicroliters, totalMicroliters: totalMicroliters)
    }

    var isDepleted: Bool { remainingMicroliters == 0 }

    var hasApplications: Bool { !usages.isEmpty }

    var supply: VialSupply {
        VialSupply(id: id, remainingMicroliters: remainingMicroliters, concentrationMicrogramsPerMl: concentrationMicrogramsPerMl)
    }

    var reference: VialReference {
        VialReference(volumeMicroliters: totalMicroliters, concentrationMicrogramsPerMl: concentrationMicrogramsPerMl)
    }
}

extension DoseEvent {
    enum Kind: String {
        case applied
        case skipped
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .applied }
        set { kindRaw = newValue.rawValue }
    }

    var scheduledDay: LocalDay? { scheduledDayKey.flatMap(LocalDay.init(key:)) }

    var isExtra: Bool { kind == .applied && scheduledDayKey == nil }

    var orderedUsages: [VialUsage] { usages.sorted { $0.order < $1.order } }

    var totalMicroliters: Int { usages.reduce(0) { $0 + $1.microliters } }

    /// Vial escolhido no registro (primeira parte).
    var primaryVial: Vial? { orderedUsages.first?.vial }
}

extension AppPreferences {
    /// Registro único de preferências, criado na primeira leitura.
    @MainActor
    static func current(in context: ModelContext) -> AppPreferences {
        if let existing = try? context.fetch(FetchDescriptor<AppPreferences>()).first {
            return existing
        }
        let prefs = AppPreferences()
        context.insert(prefs)
        try? context.save()
        return prefs
    }
}
