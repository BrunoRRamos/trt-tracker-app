import SwiftUI
import TRTCore

/// Cadastro de composto no protocolo (RF-VIA-01), com agenda e lembrete próprios opcionais
/// e o cálculo de vials mínimos em tempo real (RF-VIA-09).
struct CompoundFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CompoundDraft
    @State private var showErrors = false
    let protocolStart: Date
    let protocolEnd: Date
    let protocolSchedule: Schedule
    let protocolHour: Int
    let protocolMinute: Int
    let isNew: Bool
    /// Cor da série: a posição do composto no protocolo.
    let colorIndex: Int
    let onSave: (CompoundDraft) -> Void

    init(draft: CompoundDraft, protocolStart: Date, protocolEnd: Date, protocolSchedule: Schedule,
         protocolHour: Int, protocolMinute: Int, isNew: Bool, colorIndex: Int, onSave: @escaping (CompoundDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.protocolStart = protocolStart
        self.protocolEnd = protocolEnd
        self.protocolSchedule = protocolSchedule
        self.protocolHour = protocolHour
        self.protocolMinute = protocolMinute
        self.isNew = isNew
        self.colorIndex = colorIndex
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                doseSection
                scheduleSection
                reminderSection
                levelPreviewSection
                requirementSection
                Section("Observações") {
                    TextField("Opcional", text: $draft.notes, axis: .vertical)
                        .lineLimit(1...5)
                }
                .listRowBackground(Theme.surface)
            }
            .sheetBackground()
            .navigationTitle(isNew ? String(localized: "Novo composto") : String(localized: "Editar composto"))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? String(localized: "Adicionar") : String(localized: "Salvar")) {
                        draft.name = draft.displayName
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var nameSection: some View {
        Section {
            NavigationLink {
                CatalogPickerView(selectedKey: draft.catalogKey, isCustom: draft.isCustom) { entry in
                    draft.select(entry)
                }
            } label: {
                substanceLabel
            }
            if let entry = draft.catalogEntry {
                InfoRow(label: String(localized: "Nome químico"), value: entry.chemicalName)
                InfoRow(label: String(localized: "Via"), value: entry.variant.route.title)
                InfoRow(label: String(localized: "Meia-vida"), value: Formatting.halfLife(hours: entry.variant.halfLifeHours))
                OriginBadge(origin: entry.variant.halfLifeOrigin)
                InfoRow(label: String(localized: "Composto ativo"), value: Formatting.percentValue(entry.variant.activeDosePercent))
                if !entry.isDepotModelEligible {
                    Text("Fora do modelo de depósito oleoso (oral ou suspensão aquosa): sem perfil de liberação.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let note = entry.variant.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if draft.isCustom {
                TextField("Nome do composto", text: $draft.name)
                    .textInputAutocapitalization(.sentences)
                    .onChange(of: draft.name) { _, _ in showErrors = true }
                FieldError(message: showErrors || !isNew ? draft.nameError : nil)
                DecimalField(title: String(localized: "Composto ativo"), text: $draft.customActivePercentText,
                             unit: "%", prompt: "100", error: draft.activePercentError)
            }
        } header: {
            Text("Substância")
        } footer: {
            Text(draft.isCustom
                 ? String(localized: "Até 40 caracteres. Compostos fora da lista não têm perfil de liberação.")
                 : String(localized: "Escolha a substância e o éster na lista. A meia-vida, a origem dela e o % de composto ativo vêm do catálogo."))
        }
        .listRowBackground(Theme.surface)
    }

    @ViewBuilder
    private var substanceLabel: some View {
        if let entry = draft.catalogEntry {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                if let compoundClass = entry.compoundClass {
                    Text(compoundClass)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } else if draft.isCustom {
            Text("Outro (fora da lista)")
                .foregroundStyle(Theme.textPrimary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Escolher da lista")
                    .foregroundStyle(Theme.accent)
                if showErrors, let error = draft.nameError {
                    Text(error).font(.footnote).foregroundStyle(Theme.critical)
                }
            }
        }
    }

    /// Prévia do perfil normalizado com a agenda e as datas atuais do formulário.
    @ViewBuilder
    private var levelPreviewSection: some View {
        let schedule = draft.effectiveSchedule(protocolSchedule: protocolSchedule)
        let hour = draft.usesCustomTime ? draft.hour : protocolHour
        let minute = draft.usesCustomTime ? draft.minute : protocolMinute
        Section {
            if let entry = draft.catalogEntry, entry.isDepotModelEligible, schedule.isValid,
               let series = ProfileSeriesBuilder.preview(name: draft.displayName, colorIndex: colorIndex, entry: entry,
                                                         schedule: schedule, start: LocalDay(protocolStart), end: LocalDay(protocolEnd),
                                                         hour: hour, minute: minute) {
                ProfileChartView(series: [series], now: Date(), protocolEnd: LocalDay(protocolEnd).date(hour: 23, minute: 59))
                    .padding(.vertical, 4)
                ProfileStatsView(series: series)
            } else {
                Text(draft.catalogEntry == nil
                     ? String(localized: "Escolha na lista um éster intramuscular para ver o perfil.")
                     : String(localized: "Disponível só para ésteres intramusculares em veículo oleoso."))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Perfil normalizado com esta agenda")
        } footer: {
            Text("Em múltiplos do pico de uma dose única: a forma muda com a frequência e os dias, não com a dose. V_d e F se cancelam na normalização; nenhuma concentração absoluta é inferível.")
        }
        .listRowBackground(Theme.surface)
    }

    private var doseSection: some View {
        Section {
            DecimalField(title: String(localized: "Dose por aplicação"), text: $draft.doseText, unit: "mg", prompt: "100",
                         error: draft.doseText.isEmpty && isNew ? nil : draft.doseError)
        } footer: {
            if !isNew {
                Text("A alteração da dose vale apenas para aplicações futuras.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var scheduleSection: some View {
        Section("Agenda") {
            Toggle("Seguir a agenda do protocolo", isOn: $draft.usesProtocolSchedule)
                .onChange(of: draft.usesProtocolSchedule) { _, followsProtocol in
                    // A agenda própria começa igual à do protocolo.
                    if !followsProtocol { draft.schedule = ScheduleDraft(protocolSchedule) }
                }
            if draft.usesProtocolSchedule {
                Text(protocolSchedule.summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ScheduleEditor(draft: $draft.schedule, protocolStart: protocolStart)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var reminderSection: some View {
        Section {
            Toggle("Lembrete", isOn: $draft.reminderEnabled)
            Toggle("Horário próprio", isOn: $draft.usesCustomTime)
            if draft.usesCustomTime {
                ReminderTimeRow(title: String(localized: "Horário"), hour: $draft.hour, minute: $draft.minute)
            } else {
                Text("Horário do protocolo: \(Formatting.time(hour: protocolHour, minute: protocolMinute))")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Horário e lembrete")
        } footer: {
            Text("O horário define quando cada aplicação está prevista, mesmo com o lembrete desligado.")
        }
        .listRowBackground(Theme.surface)
    }

    private var requirementSection: some View {
        Section {
            if draft.currentReference == nil {
                DecimalField(title: String(localized: "Volume do vial"), text: $draft.referenceVolumeText, unit: "ml", prompt: "10")
                DecimalField(title: String(localized: "Concentração"), text: $draft.referenceConcentrationText, unit: "mg/ml", prompt: "200")
            }
            if let requirement = draft.requirement(start: LocalDay(protocolStart), end: LocalDay(protocolEnd), protocolSchedule: protocolSchedule) {
                Text(InsightText.requirement(requirement))
                    .font(.rounded(.body, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .motion(requirement)
            }
        } header: {
            Text("Vials mínimos para o protocolo")
        } footer: {
            Text(draft.currentReference == nil
                 ? String(localized: "Sem vial cadastrado: informe volume e concentração de referência. Não considera perdas.")
                 : String(localized: "Calculado com o vial atual do composto. Não considera perdas."))
        }
        .listRowBackground(Theme.surface)
    }
}
