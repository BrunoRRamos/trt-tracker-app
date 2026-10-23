import SwiftData
import SwiftUI
import TRTCore

/// Folha de confirmação de aplicação (RF-AGE-05), já preenchida com a dose padrão, data e hora atuais e o vial atual.
struct ApplyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(sort: \TreatmentProtocol.createdAt) private var protocols: [TreatmentProtocol]

    private let fixedCompound: Compound?
    private let requestedDayKey: String?

    @State private var compoundID: UUID?
    @State private var doseText = ""
    @State private var date = Date()
    @State private var vialID: UUID?
    @State private var linkKey = ApplyView.extraKey
    @State private var note = ""
    @State private var didLoad = false

    static let extraKey = "__extra__"

    init(compound: Compound?, dayKey: String?) {
        fixedCompound = compound
        requestedDayKey = dayKey
    }

    private var today: LocalDay { LocalDay(Date()) }

    private var selectableCompounds: [Compound] {
        protocols.filter { $0.status(today: today) != .ended }.flatMap(\.orderedCompounds)
    }

    private var compound: Compound? {
        fixedCompound ?? selectableCompounds.first { $0.id == compoundID }
    }

    private var doseResult: Result<Int, NumberInputError> { Validation.dose(doseText) }

    private var doseMicrograms: Int? {
        if case .success(let value) = doseResult { return value }
        return nil
    }

    private var selectedVial: Vial? {
        compound?.activeVials.first { $0.id == vialID }
    }

    /// Data e hora não podem estar no futuro.
    private var isFuture: Bool { date > Date().addingTimeInterval(60) }

    private var canConfirm: Bool { compound != nil && doseMicrograms != nil && !isFuture }

    /// Previstas que podem ser vinculadas, incluindo a pedida (por exemplo, pela notificação ou pelo calendário).
    private var linkOptions: [Occurrence] {
        guard let compound else { return [] }
        let now = Date()
        var options = DoseService.linkableOccurrences(for: compound, now: now)
        if let key = requestedDayKey, !options.contains(where: { $0.day.key == key }),
           let requested = OccurrenceEngine.occurrence(for: compound, dayKey: key, now: now), requested.event == nil {
            options.append(requested)
        }
        return options.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var body: some View {
        NavigationStack {
            Form {
                compoundSection
                if let compound {
                    linkSection(compound)
                    doseSection(compound)
                    dateSection
                    vialSection(compound)
                    Section("Observação") {
                        TextField("Opcional", text: $note, axis: .vertical)
                            .lineLimit(1...4)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .sheetBackground()
            .navigationTitle("Registrar aplicação")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirmar") { confirm() }
                        .disabled(!canConfirm)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private var compoundSection: some View {
        if fixedCompound == nil {
            Section("Composto") {
                if selectableCompounds.isEmpty {
                    Text("Nenhum protocolo ativo ou agendado.")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Picker("Composto", selection: $compoundID) {
                        ForEach(selectableCompounds) { compound in
                            Text("\(compound.name) · \(compound.treatmentProtocol?.name ?? "")").tag(Optional(compound.id))
                        }
                    }
                    .onChange(of: compoundID) { _, _ in applyDefaults() }
                }
            }
            .listRowBackground(Theme.surface)
        } else if let compound {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(compound.name).font(.headline)
                    Text(compound.treatmentProtocol?.name ?? "")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Theme.surface)
        }
    }

    private func linkSection(_ compound: Compound) -> some View {
        Section {
            Picker("Aplicação prevista", selection: $linkKey) {
                ForEach(linkOptions) { occurrence in
                    Text("\(Formatting.weekdayDayMonth(occurrence.scheduledAt)) · \(Formatting.time(occurrence.scheduledAt)) · \(occurrence.status(now: Date()).title)")
                        .tag(occurrence.day.key)
                }
                Text("Aplicação extra (fora da agenda)").tag(Self.extraKey)
            }
        } footer: {
            Text("O registro fica vinculado à aplicação prevista escolhida. Aplicações extras também descontam volume.")
        }
        .listRowBackground(Theme.surface)
    }

    private func doseSection(_ compound: Compound) -> some View {
        Section {
            DecimalField(title: String(localized: "Dose"), text: $doseText, unit: "mg",
                         error: doseError)
            if let dose = doseMicrograms, let vial = selectedVial {
                let ml = VolumeMath.microlitersPerApplication(doseMicrograms: dose, concentrationMicrogramsPerMl: vial.concentrationMicrogramsPerMl)
                InfoRow(label: String(localized: "Volume"), value: InsightText.volume(ml))
            }
        } footer: {
            if let dose = doseMicrograms, dose != compound.doseMicrograms {
                Text("Dose diferente da padrão (\(Formatting.milligrams(compound.doseMicrograms))). Vale só para este registro.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var doseError: String? {
        guard !doseText.isEmpty || didLoad else { return nil }
        if case .failure(let error) = doseResult {
            return error == .belowMinimum ? String(localized: "A dose deve ser maior que 0.") : error.message(min: "0", max: "100.000 mg")
        }
        return nil
    }

    private var dateSection: some View {
        Section {
            BRDateField(title: String(localized: "Data"), date: $date, partialUpTo: Date())
            DatePicker("Hora", selection: $date, displayedComponents: .hourAndMinute)
                .environment(\.locale, Theme.locale)
            FieldError(message: isFuture ? String(localized: "A data e a hora não podem estar no futuro.") : nil)
        }
        .listRowBackground(Theme.surface)
    }

    @ViewBuilder
    private func vialSection(_ compound: Compound) -> some View {
        Section {
            if compound.activeVials.isEmpty {
                NoticeView(tone: .warning, title: String(localized: "Sem vial cadastrado"),
                           message: String(localized: "A aplicação será registrada sem descontar estoque."))
            } else {
                Picker("Vial", selection: $vialID) {
                    ForEach(compound.activeVials) { vial in
                        Text("\(compound.displayName(of: vial)) · \(InsightText.level(vial))").tag(Optional(vial.id))
                    }
                }
                if let summary = splitSummary(compound) {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("Vial")
        }
        .listRowBackground(Theme.surface)
    }

    /// Mostra quando a dose vai consumir o restante e completar com o próximo vial (RF-VIA-03).
    private func splitSummary(_ compound: Compound) -> String? {
        guard let vial = selectedVial, let dose = doseMicrograms else { return nil }
        let chain = [vial] + compound.activeVials.filter { $0.id != vial.id }
        var supplies = chain.map(\.supply)
        let result = Consumption.consume(doseMicrograms: dose, from: &supplies)
        var lines: [String] = []
        if result.portions.count > 1 {
            let parts = result.portions.compactMap { portion -> String? in
                guard let v = chain.first(where: { $0.id == portion.vialID }) else { return nil }
                return String(localized: "\(Formatting.milliliters(portion.microliters)) do \(compound.displayName(of: v))")
            }
            lines.append(String(localized: "O vial não tem a dose inteira: serão descontados \(parts.joined(separator: " + ")).") )
        }
        if result.uncoveredMicrograms > 0 {
            lines.append(String(localized: "Faltam \(Formatting.milligrams(result.uncoveredMicrograms)) no estoque; essa parte não será descontada."))
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    private func load() {
        guard !didLoad else { return }
        compoundID = fixedCompound?.id ?? selectableCompounds.first?.id
        applyDefaults()
        if let key = requestedDayKey, linkOptions.contains(where: { $0.day.key == key }) {
            linkKey = key
        }
        didLoad = true
    }

    private func applyDefaults() {
        guard let compound else { return }
        doseText = DecimalInput.text(fromScaled: compound.doseMicrograms)
        vialID = compound.currentVial?.id
        linkKey = DoseService.defaultOccurrence(for: compound, now: Date())?.day.key ?? Self.extraKey
    }

    private func confirm() {
        guard let compound, let dose = doseMicrograms, !isFuture else { return }
        let dayKey = linkKey == Self.extraKey ? nil : linkKey
        let event = DoseService.register(compound: compound, doseMicrograms: dose, performedAt: date,
                                         vial: selectedVial, dayKey: dayKey, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                         in: context)
        Haptics.success()
        appState.tick()
        Task { await NotificationScheduler.shared.reschedule() }
        let modelContext = context
        let state = appState
        let message = event.totalMicroliters > 0
            ? String(localized: "Aplicação registrada · \(Formatting.milliliters(event.totalMicroliters)) descontados")
            : String(localized: "Aplicação registrada")
        appState.showToast(message) {
            DoseService.delete(event: event, in: modelContext)
            state.tick()
            Task { await NotificationScheduler.shared.reschedule() }
        }
        dismiss()
    }
}
