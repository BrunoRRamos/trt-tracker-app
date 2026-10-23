import SwiftData
import SwiftUI
import TRTCore

/// Ajuste manual do nível em ml (passo 0,1) ou em % (passo 1), registrado como "Ajuste" (RF-VIA-05).
struct AdjustVialView: View {
    let vial: Vial

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    private enum Unit: Hashable { case milliliters, percent }

    @State private var unit: Unit = .milliliters
    @State private var microliters = 0
    @State private var percent = 0
    @State private var note = ""
    @State private var didLoad = false

    private var target: Int {
        switch unit {
        case .milliliters: min(max(0, microliters), vial.totalMicroliters)
        case .percent: vial.totalMicroliters * min(100, max(0, percent)) / 100
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Ajustar por", selection: $unit) {
                        Text("ml").tag(Unit.milliliters)
                        Text("%").tag(Unit.percent)
                    }
                    .pickerStyle(.segmented)

                    switch unit {
                    case .milliliters:
                        Stepper(value: $microliters, in: 0...vial.totalMicroliters, step: 100) {
                            valueLabel(Formatting.milliliters(microliters))
                        }
                        .accessibilityValue(Text(Formatting.milliliters(microliters)))
                    case .percent:
                        Stepper(value: $percent, in: 0...100, step: 1) {
                            valueLabel("\(percent)%")
                        }
                        .accessibilityValue(Text("\(percent)%"))
                    }
                } footer: {
                    Text("Use para refletir perdas, como líquido descartado ou volume morto da seringa.")
                }
                .listRowBackground(Theme.surface)

                Section("Resultado") {
                    InfoRow(label: String(localized: "Antes"), value: "\(Formatting.milliliters(vial.remainingMicroliters)) · \(Formatting.percent(vial.percentRemaining))")
                    InfoRow(label: String(localized: "Depois"),
                            value: "\(Formatting.milliliters(target)) · \(Formatting.percent(VolumeMath.percentRemaining(remainingMicroliters: target, totalMicroliters: vial.totalMicroliters)))")
                }
                .listRowBackground(Theme.surface)

                Section("Motivo") {
                    TextField("Opcional", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
                .listRowBackground(Theme.surface)
            }
            .sheetBackground()
            .navigationTitle("Ajustar nível")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .disabled(target == vial.remainingMicroliters)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                microliters = vial.remainingMicroliters
                if case .whole(let value) = vial.percentRemaining { percent = value }
            }
            .onChange(of: unit) { _, newValue in
                if newValue == .percent {
                    percent = vial.totalMicroliters > 0 ? microliters * 100 / vial.totalMicroliters : 0
                } else {
                    microliters = target
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func valueLabel(_ text: String) -> some View {
        Text(text)
            .font(.rounded(.title2, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .contentTransition(.numericText())
    }

    private func save() {
        VialService.adjust(vial, to: target, note: note.trimmingCharacters(in: .whitespacesAndNewlines), in: context)
        appState.tick()
        appState.showToast(String(localized: "Ajuste registrado"))
        Task { await NotificationScheduler.shared.reschedule() }
        dismiss()
    }
}
