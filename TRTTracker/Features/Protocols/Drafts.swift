import Foundation
import TRTCore

/// Agenda editável (frequência, dias e recontagem do "dia sim, dia não").
struct ScheduleDraft: Equatable {
    var frequency: Frequency = .twoTimesWeek
    var weekdays: Set<Weekday> = Frequency.twoTimesWeek.defaultWeekdays
    var restartsCount = false
    var anchorDate = Date()

    init() {}

    init(_ schedule: Schedule) {
        frequency = schedule.frequency
        weekdays = schedule.frequency.usesWeekdays ? schedule.weekdays : schedule.frequency.defaultWeekdays
        if let anchor = schedule.alternateAnchor {
            restartsCount = true
            anchorDate = anchor.date()
        }
    }

    var schedule: Schedule {
        let anchor = frequency == .everyOtherDay && restartsCount ? LocalDay(anchorDate) : nil
        return Schedule(frequency: frequency, weekdays: frequency.usesWeekdays ? weekdays : frequency.defaultWeekdays,
                        alternateAnchor: anchor)
    }

    var error: String? {
        guard let required = frequency.requiredWeekdayCount, weekdays.count != required else { return nil }
        return String(localized: "Selecione exatamente \(required) dias.")
    }
}

/// Rascunho de composto editado no formulário do protocolo (RF-VIA-01).
struct CompoundDraft: Identifiable, Equatable {
    var id = UUID()
    /// Composto existente (edição).
    var existingID: UUID?
    /// Variante escolhida no catálogo de compostos.
    var catalogKey: String?
    /// "Outro": composto fora da lista, com nome livre.
    var isCustom = false
    var name = ""
    /// % ativo de um composto fora da lista.
    var customActivePercentText = "100"
    var doseText = ""
    var notes = ""
    var usesProtocolSchedule = true
    var schedule = ScheduleDraft()
    var reminderEnabled = true
    var usesCustomTime = false
    var hour = 9
    var minute = 0
    /// Vial atual do composto existente, usado como referência no cálculo de vials (RF-VIA-09).
    var currentReference: VialReference?
    /// Vial de referência informado na tela quando não há vial cadastrado.
    var referenceVolumeText = ""
    var referenceConcentrationText = ""

    init() {}

    init(_ compound: Compound) {
        existingID = compound.id
        catalogKey = compound.catalogEntry?.key
        isCustom = catalogKey == nil
        name = compound.name
        if catalogKey == nil {
            customActivePercentText = Formatting.decimal(Decimal(compound.activeDosePercent), maxFractionDigits: 1)
        }
        doseText = DecimalInput.text(fromScaled: compound.doseMicrograms)
        notes = compound.notes
        usesProtocolSchedule = compound.usesProtocolSchedule
        if !compound.usesProtocolSchedule {
            schedule = ScheduleDraft(Schedule(frequency: compound.ownFrequency, weekdays: compound.ownWeekdays,
                                              alternateAnchor: compound.ownAlternateAnchor))
        }
        reminderEnabled = compound.reminderEnabled
        usesCustomTime = compound.usesCustomReminderTime
        hour = compound.reminderHour
        minute = compound.reminderMinute
        currentReference = compound.currentVial?.reference
    }

    var catalogEntry: CatalogEntry? { CompoundCatalog.shared.entry(forKey: catalogKey) }

    /// Nome gravado no composto: o do catálogo ou o digitado.
    var displayName: String { catalogEntry?.displayName ?? Validation.trimmed(name) }

    var nameError: String? {
        if catalogEntry != nil { return nil }
        if !isCustom { return String(localized: "Escolha uma substância da lista.") }
        return Validation.compoundName(name)?.message
    }

    mutating func select(_ entry: CatalogEntry?) {
        catalogKey = entry?.key
        isCustom = entry == nil
        if let entry { name = entry.displayName }
    }

    /// Meia-vida tabelada do catálogo; compostos fora da lista não têm.
    var halfLifeHours: Double? { catalogEntry?.variant.halfLifeHours }

    var activeDosePercent: Double {
        if let entry = catalogEntry { return entry.variant.activeDosePercent }
        return DecimalInput.parse(customActivePercentText).map { NSDecimalNumber(decimal: $0).doubleValue } ?? 100
    }

    var activePercentError: String? {
        guard catalogEntry == nil else { return nil }
        guard let value = DecimalInput.parse(customActivePercentText) else { return String(localized: "Digite um número válido.") }
        let percent = NSDecimalNumber(decimal: value).doubleValue
        return percent >= 1 && percent <= 100 ? nil : String(localized: "Use de 1% a 100%.")
    }

    var doseResult: Result<Int, NumberInputError> { Validation.dose(doseText) }

    var doseMicrograms: Int? {
        if case .success(let value) = doseResult { return value }
        return nil
    }

    var doseError: String? {
        guard case .failure(let error) = doseResult else { return nil }
        switch error {
        case .empty: return String(localized: "Informe a dose por aplicação.")
        case .belowMinimum: return String(localized: "A dose deve ser maior que 0.")
        default: return error.message(min: "0", max: "100.000 mg")
        }
    }

    var scheduleError: String? { usesProtocolSchedule ? nil : schedule.error }

    var isValid: Bool {
        nameError == nil && doseError == nil && scheduleError == nil && activePercentError == nil
    }

    func effectiveSchedule(protocolSchedule: Schedule) -> Schedule {
        usesProtocolSchedule ? protocolSchedule : schedule.schedule
    }

    var reference: VialReference? {
        if let currentReference { return currentReference }
        guard case .success(let volume) = Validation.vialVolume(referenceVolumeText),
              case .success(let concentration) = Validation.concentration(referenceConcentrationText) else { return nil }
        return VialReference(volumeMicroliters: volume, concentrationMicrogramsPerMl: concentration)
    }

    /// Vials mínimos em tempo real para as datas e a agenda atuais do formulário.
    func requirement(start: LocalDay, end: LocalDay, protocolSchedule: Schedule) -> VialRequirement? {
        guard let dose = doseMicrograms, let reference, end >= start else { return nil }
        let count = effectiveSchedule(protocolSchedule: protocolSchedule).applicationCount(start: start, end: end)
        return VialRequirement.compute(doseMicrograms: dose, applicationCount: count, reference: reference)
    }
}

/// Rascunho do protocolo (RF-PRO-01 e 05).
struct ProtocolDraft: Equatable {
    var name = ""
    var start = Calendar.current.startOfDay(for: Date())
    var end = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    var schedule = ScheduleDraft()
    var hour = 9
    var minute = 0
    var compounds: [CompoundDraft] = []

    init() {}

    init(_ treatment: TreatmentProtocol) {
        name = treatment.name
        start = treatment.startDay.date()
        end = treatment.endDay.date()
        schedule = ScheduleDraft(treatment.schedule)
        hour = treatment.reminderHour
        minute = treatment.reminderMinute
        compounds = treatment.orderedCompounds.map(CompoundDraft.init)
    }

    var startDay: LocalDay { LocalDay(start) }
    var endDay: LocalDay { LocalDay(end) }

    var nameError: String? { Validation.protocolName(name)?.message }

    var periodError: String? {
        Validation.isValidPeriod(start: startDay, end: endDay) ? nil : String(localized: "A data de fim deve ser igual ou posterior à de início.")
    }

    var compoundsError: String? {
        compounds.isEmpty ? String(localized: "Adicione pelo menos um composto.") : nil
    }

    var isValid: Bool {
        nameError == nil && periodError == nil && schedule.error == nil && compoundsError == nil && compounds.allSatisfy(\.isValid)
    }
}
