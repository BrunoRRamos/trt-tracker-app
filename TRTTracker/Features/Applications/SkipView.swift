import SwiftData
import SwiftUI
import TRTCore

/// Marca uma aplicação prevista ou atrasada como "Pulada", com motivo opcional (RF-AGE-06).
struct SkipView: View {
    let occurrence: Occurrence

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(occurrence.compound.name).font(.headline)
                        Text("\(Formatting.weekdayDayMonth(occurrence.scheduledAt)) · \(Formatting.time(occurrence.scheduledAt))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                } footer: {
                    Text("Pular não desconta volume do vial e remove o lembrete desta aplicação.")
                }
                .listRowBackground(Theme.surface)

                Section("Motivo") {
                    TextField("Opcional", text: $reason, axis: .vertical)
                        .lineLimit(1...4)
                }
                .listRowBackground(Theme.surface)
            }
            .sheetBackground()
            .navigationTitle("Pular aplicação")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pular") { skip() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func skip() {
        let event = DoseService.skip(compound: occurrence.compound, dayKey: occurrence.day.key,
                                     reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), in: context)
        Haptics.warning()
        appState.tick()
        Task { await NotificationScheduler.shared.reschedule() }
        let modelContext = context
        let state = appState
        appState.showToast(String(localized: "Aplicação pulada")) {
            DoseService.delete(event: event, in: modelContext)
            state.tick()
            Task { await NotificationScheduler.shared.reschedule() }
        }
        dismiss()
    }
}
