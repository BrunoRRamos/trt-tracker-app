import SwiftData
import SwiftUI
import TRTCore

/// Edição de registro ou pulo, com recálculo do nível do vial e das projeções (RF-AGE-07).
struct EditEventView: View {
    let event: DoseEvent

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var doseText = ""
    @State private var date = Date()
    @State private var vialID: UUID?
    @State private var note = ""
    @State private var confirmDelete = false
    @State private var didLoad = false

    private var compound: Compound? { event.compound }

    /// Vials que podem receber o desconto: os ativos e o já usado por este registro.
    private var vialOptions: [Vial] {
        guard let compound else { return [] }
        var options = compound.activeVials
        if let used = event.primaryVial, !options.contains(where: { $0.id == used.id }) {
            options.insert(used, at: 0)
        }
        return options
    }

    private var doseMicrograms: Int? { try? Validation.dose(doseText).get() }
    private var isFuture: Bool { date > Date().addingTimeInterval(60) }
    private var canSave: Bool { event.kind == .skipped || (doseMicrograms != nil && !isFuture) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(compound?.name ?? "").font(.headline)
                }
                .listRowBackground(Theme.surface)

                if event.kind == .applied {
                    Section {
                        DecimalField(title: String(localized: "Dose"), text: $doseText, unit: "mg",
                                     error: doseMicrograms == nil ? String(localized: "A dose deve ser maior que 0.") : nil)
                        BRDateField(title: String(localized: "Data"), date: $date, partialUpTo: Date())
                        DatePicker("Hora", selection: $date, displayedComponents: .hourAndMinute)
                            .environment(\.locale, Theme.locale)
                        FieldError(message: isFuture ? String(localized: "A data e a hora não podem estar no futuro.") : nil)
                    }
                    .listRowBackground(Theme.surface)

                    Section("Vial") {
                        if vialOptions.isEmpty {
                            Text("Sem vial disponível: o registro não desconta estoque.")
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            Picker("Vial", selection: $vialID) {
                                Text("Não descontar estoque").tag(UUID?.none)
                                ForEach(vialOptions) { vial in
                                    Text(compound.map { $0.displayName(of: vial) } ?? "").tag(Optional(vial.id))
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }

                Section(event.kind == .applied ? String(localized: "Observação") : String(localized: "Motivo")) {
                    TextField("Opcional", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button("Excluir registro", role: .destructive) { confirmDelete = true }
                }
                .listRowBackground(Theme.surface)
            }
            .sheetBackground()
            .navigationTitle(event.kind == .applied ? String(localized: "Editar aplicação") : String(localized: "Editar pulo"))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .alert("Excluir registro?", isPresented: $confirmDelete) {
                Button("Excluir", role: .destructive, action: delete)
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("O volume descontado volta para o vial e as projeções são recalculadas.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        doseText = DecimalInput.text(fromScaled: event.doseMicrograms)
        date = event.performedAt
        vialID = event.primaryVial?.id
        note = event.note
    }

    private func save() {
        let vial = vialOptions.first { $0.id == vialID }
        DoseService.update(event: event, doseMicrograms: doseMicrograms ?? event.doseMicrograms, performedAt: date,
                           vial: vial, note: note.trimmingCharacters(in: .whitespacesAndNewlines), in: context)
        appState.tick()
        Task { await NotificationScheduler.shared.reschedule() }
        dismiss()
    }

    private func delete() {
        Haptics.warning()
        dismiss()
        let modelContext = context
        let state = appState
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            DoseService.delete(event: event, in: modelContext)
            state.tick()
            await NotificationScheduler.shared.reschedule()
        }
    }
}
