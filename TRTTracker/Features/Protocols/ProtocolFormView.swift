import SwiftData
import SwiftUI
import TRTCore

/// Criação e edição de protocolo (RF-PRO-01 e 05).
struct ProtocolFormView: View {
    enum Mode {
        case create
        case edit(TreatmentProtocol)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var draft: ProtocolDraft
    @State private var editingCompound: CompoundDraft?
    @State private var creatingCompound: CompoundDraft?
    @State private var compoundToRemove: CompoundDraft?
    @State private var nameTouched = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create: _draft = State(initialValue: ProtocolDraft())
        case .edit(let treatment): _draft = State(initialValue: ProtocolDraft(treatment))
        }
    }

    private var isNew: Bool {
        if case .create = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                periodSection
                scheduleSection
                reminderSection
                compoundsSection
            }
            .sheetBackground()
            .navigationTitle(isNew ? String(localized: "Novo protocolo") : String(localized: "Editar protocolo"))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Salvar fica desabilitado enquanto houver erro (RF-PRO-01).
                    Button("Salvar", action: save)
                        .disabled(!draft.isValid)
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: $creatingCompound) { compound in
                compoundForm(compound, isNew: true)
            }
            .sheet(item: $editingCompound) { compound in
                compoundForm(compound, isNew: false)
            }
            .alert("Remover composto?", isPresented: removeBinding, presenting: compoundToRemove) { compound in
                Button("Remover", role: .destructive) {
                    draft.compounds.removeAll { $0.id == compound.id }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { compound in
                if compound.existingID != nil {
                    Text("Ao salvar, os vials e o histórico deste composto também serão apagados.")
                } else {
                    Text("O composto será removido do protocolo.")
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var removeBinding: Binding<Bool> {
        Binding(get: { compoundToRemove != nil }, set: { if !$0 { compoundToRemove = nil } })
    }

    private var nameSection: some View {
        Section("Nome") {
            TextField("Ex.: TRT", text: $draft.name)
                .textInputAutocapitalization(.sentences)
                .onChange(of: draft.name) { _, _ in nameTouched = true }
            FieldError(message: nameTouched || !isNew ? draft.nameError : nil)
        }
        .listRowBackground(Theme.surface)
    }

    private var periodSection: some View {
        Section {
            BRDateField(title: String(localized: "Início"), date: $draft.start)
            BRDateField(title: String(localized: "Fim"), date: $draft.end)
            FieldError(message: draft.periodError)
        } header: {
            Text("Período")
        } footer: {
            Text("A data de início pode estar no passado, para um protocolo já em andamento.")
        }
        .listRowBackground(Theme.surface)
    }

    private var scheduleSection: some View {
        Section {
            ScheduleEditor(draft: $draft.schedule, protocolStart: draft.start)
        } header: {
            Text("Agenda padrão")
        } footer: {
            Text("Vale para todos os compostos, que podem ter a sua própria agenda.")
        }
        .listRowBackground(Theme.surface)
    }

    private var reminderSection: some View {
        Section {
            ReminderTimeRow(title: String(localized: "Horário padrão"), hour: $draft.hour, minute: $draft.minute)
        } header: {
            Text("Lembrete")
        } footer: {
            Text("Cada composto pode ter o seu horário ou desligar o lembrete.")
        }
        .listRowBackground(Theme.surface)
    }

    private var compoundsSection: some View {
        Section {
            ForEach(draft.compounds) { compound in
                Button {
                    editingCompound = compound
                } label: {
                    compoundRow(compound)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Remover", role: .destructive) { compoundToRemove = compound }
                }
                .contextMenu {
                    Button("Remover", systemImage: "trash", role: .destructive) { compoundToRemove = compound }
                }
            }
            Button {
                creatingCompound = CompoundDraft()
            } label: {
                Label("Adicionar composto", systemImage: "plus.circle.fill")
            }
            FieldError(message: draft.compoundsError)
        } header: {
            Text("Compostos")
        } footer: {
            Text("O protocolo precisa de pelo menos um composto. Os vials são cadastrados no detalhe de cada composto; a curva de nível estimado fica em Níveis estimados.")
        }
        .listRowBackground(Theme.surface)
    }

    private func compoundRow(_ compound: CompoundDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(compound.displayName.isEmpty ? String(localized: "Sem nome") : compound.displayName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !compound.isValid {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.critical)
                        .accessibilityLabel(Text("Com erro"))
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            let schedule = compound.effectiveSchedule(protocolSchedule: draft.schedule.schedule)
            Text("\(compound.doseMicrograms.map(Formatting.milligrams) ?? "—") · \(schedule.summary)")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            // Vials mínimos em tempo real ao mudar datas, dose, frequência ou dias (RF-VIA-09).
            if let requirement = compound.requirement(start: draft.startDay, end: draft.endDay, protocolSchedule: draft.schedule.schedule) {
                Text(InsightText.requirement(requirement))
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
                    .motion(requirement)
            } else {
                Text("Informe um vial de referência para calcular os vials mínimos.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func compoundForm(_ compound: CompoundDraft, isNew: Bool) -> some View {
        CompoundFormView(draft: compound, protocolStart: draft.start, protocolEnd: draft.end,
                         protocolSchedule: draft.schedule.schedule, protocolHour: draft.hour,
                         protocolMinute: draft.minute, isNew: isNew,
                         colorIndex: draft.compounds.firstIndex { $0.id == compound.id } ?? draft.compounds.count) { saved in
            if let index = draft.compounds.firstIndex(where: { $0.id == saved.id }) {
                draft.compounds[index] = saved
            } else {
                draft.compounds.append(saved)
            }
        }
    }

    // MARK: Salvar

    private func save() {
        guard draft.isValid else { return }
        let treatment: TreatmentProtocol
        switch mode {
        case .create:
            treatment = TreatmentProtocol(name: "", startDayKey: draft.startDay.key, endDayKey: draft.endDay.key)
            context.insert(treatment)
        case .edit(let existing):
            treatment = existing
            if existing.endDayKey != draft.endDay.key {
                // Uma nova data de fim reabre um protocolo encerrado manualmente.
                existing.endedManually = false
            }
        }
        treatment.name = Validation.trimmed(draft.name)
        treatment.startDay = draft.startDay
        treatment.endDay = draft.endDay
        treatment.frequency = draft.schedule.frequency
        treatment.weekdays = draft.schedule.schedule.weekdays
        treatment.alternateAnchor = draft.schedule.schedule.alternateAnchor
        treatment.reminderHour = draft.hour
        treatment.reminderMinute = draft.minute

        let keptIDs = Set(draft.compounds.compactMap(\.existingID))
        var removedIDs: [UUID] = []
        for compound in treatment.compounds where !keptIDs.contains(compound.id) {
            removedIDs += [compound.id] + compound.vials.map(\.id)
            compound.treatmentProtocol = nil
            context.delete(compound)
        }
        if !removedIDs.isEmpty {
            Task { await NotificationScheduler.shared.removeNotifications(mentioning: removedIDs) }
        }

        for (index, item) in draft.compounds.enumerated() {
            let compound: Compound
            if let id = item.existingID, let existing = treatment.compounds.first(where: { $0.id == id }) {
                compound = existing
            } else {
                compound = Compound(name: item.name, doseMicrograms: item.doseMicrograms ?? 0)
                context.insert(compound)
                compound.treatmentProtocol = treatment
            }
            apply(item, to: compound, index: index)
        }

        try? context.save()
        appState.tick()
        Task { await NotificationScheduler.shared.reschedule() }
        appState.requestNotificationPrimerIfNeeded(remindersEnabled: draft.compounds.contains { $0.reminderEnabled })
        dismiss()
    }

    private func apply(_ item: CompoundDraft, to compound: Compound, index: Int) {
        compound.name = item.displayName
        compound.catalogKey = item.catalogEntry?.key
        compound.halfLifeHours = item.halfLifeHours
        compound.activeDosePercent = item.activeDosePercent
        compound.doseMicrograms = item.doseMicrograms ?? compound.doseMicrograms
        compound.notes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        compound.sortIndex = index
        compound.usesProtocolSchedule = item.usesProtocolSchedule
        let own = item.schedule.schedule
        compound.ownFrequency = own.frequency
        compound.ownWeekdays = own.weekdays
        compound.ownAlternateAnchor = own.alternateAnchor
        compound.reminderEnabled = item.reminderEnabled
        compound.usesCustomReminderTime = item.usesCustomTime
        compound.reminderHour = item.hour
        compound.reminderMinute = item.minute
        compound.lowStockAlertSent = false
    }
}
