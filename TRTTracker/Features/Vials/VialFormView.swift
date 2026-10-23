import SwiftData
import SwiftUI
import TRTCore

/// Cadastro e edição de vial (RF-VIA-02 e 08).
struct VialFormView: View {
    enum Mode {
        case create(Compound)
        case edit(Vial)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var volumeText = ""
    @State private var concentrationText = ""
    @State private var remainingText = ""
    @State private var remainingEdited = false
    @State private var nickname = ""
    @State private var hasOpenedAt = false
    @State private var openedAt = Date()
    @State private var lot = ""
    @State private var hasExpiry = false
    @State private var expiresAt = Date()
    @State private var didLoad = false

    private var compound: Compound? {
        switch mode {
        case .create(let compound): compound
        case .edit(let vial): vial.compound
        }
    }

    private var isNew: Bool {
        if case .create = mode { return true }
        return false
    }

    private var volume: Result<Int, NumberInputError> { Validation.vialVolume(volumeText) }
    private var concentration: Result<Int, NumberInputError> { Validation.concentration(concentrationText) }

    private var volumeMicroliters: Int? { try? volume.get() }
    private var concentrationValue: Int? { try? concentration.get() }

    private var remaining: Result<Int, NumberInputError>? {
        guard let total = volumeMicroliters else { return nil }
        return Validation.remainingVolume(remainingText, totalMicroliters: total)
    }

    private var remainingMicroliters: Int? { try? remaining?.get() }

    private var isValid: Bool {
        volumeMicroliters != nil && concentrationValue != nil && remainingMicroliters != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                mainSection
                remainingSection
                volumePerApplicationSection
                optionalSection
            }
            .sheetBackground()
            .navigationTitle(isNew ? String(localized: "Novo vial") : String(localized: "Editar vial"))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var mainSection: some View {
        Section {
            DecimalField(title: String(localized: "Volume total"), text: $volumeText, unit: "ml", prompt: "10",
                         error: volumeText.isEmpty ? nil : volume.errorMessage(min: "0,1 ml", max: "100 ml"))
                .onChange(of: volumeText) { _, newValue in
                    if !remainingEdited { remainingText = newValue }
                }
            DecimalField(title: String(localized: "Concentração"), text: $concentrationText, unit: "mg/ml", prompt: "200",
                         error: concentrationText.isEmpty ? nil : concentration.errorMessage(min: "1 mg/ml", max: "1.000 mg/ml"))
        } header: {
            Text("Vial")
        } footer: {
            Text("Volume de 0,1 a 100 ml (passo de 0,1) e concentração de 1 a 1.000 mg/ml.")
        }
        .listRowBackground(Theme.surface)
    }

    private var remainingSection: some View {
        Section {
            DecimalField(title: String(localized: "Volume restante"), text: Binding(
                get: { remainingText },
                set: { remainingText = $0; remainingEdited = true }
            ), unit: "ml", error: remainingError)
            if let total = volumeMicroliters, let value = remainingMicroliters {
                InfoRow(label: String(localized: "Porcentagem"),
                        value: Formatting.percent(VolumeMath.percentRemaining(remainingMicroliters: value, totalMicroliters: total)))
            }
        } footer: {
            Text(isNew
                 ? String(localized: "Igual ao volume total por padrão. Altere para cadastrar um vial que já foi aberto.")
                 : String(localized: "Se o vial já tiver aplicações, a correção fica registrada como ajuste no histórico."))
        }
        .listRowBackground(Theme.surface)
    }

    private var remainingError: String? {
        guard let remaining, !remainingText.isEmpty || volumeMicroliters != nil else { return nil }
        if case .failure(let error) = remaining {
            return error == .aboveMaximum
                ? String(localized: "O volume restante não pode ser maior que o volume total.")
                : error.message(min: "0 ml", max: Formatting.milliliters(volumeMicroliters ?? 0))
        }
        return nil
    }

    /// Volume por aplicação: ml = dose ÷ concentração, também em UI de seringa U-100 (RF-VIA-02).
    @ViewBuilder
    private var volumePerApplicationSection: some View {
        if let compound, let concentrationValue {
            let ml = VolumeMath.microlitersPerApplication(doseMicrograms: compound.doseMicrograms, concentrationMicrogramsPerMl: concentrationValue)
            Section {
                if let entry = compound.catalogEntry {
                    InfoRow(label: String(localized: "Substância"), value: entry.displayName)
                }
                InfoRow(label: String(localized: "Por aplicação de \(Formatting.milligrams(compound.doseMicrograms))"),
                        value: InsightText.volume(ml))
                if compound.activeFraction < 1 {
                    // Rótulo do vial em mg de éster; a fração ativa do catálogo dá o equivalente do composto ativo.
                    let activeConcentration = Double(concentrationValue) / 1000 * compound.activeFraction
                    InfoRow(label: String(localized: "\(compound.activeSubstanceName) ativa"),
                            value: "≈ \(Formatting.milligrams(estimate: activeConcentration))/ml")
                    InfoRow(label: String(localized: "Dose ativa por aplicação"),
                            value: "≈ \(Formatting.milligrams(estimate: compound.activeDoseMilligrams))")
                }
            } footer: {
                Text(compound.activeFraction < 1
                     ? String(localized: "Seringa U-100: 1 ml = 100 UI. A concentração do rótulo é do éster; \(Formatting.percentValue(compound.activeDosePercent)) dela é composto ativo.")
                     : String(localized: "Seringa U-100: 1 ml = 100 UI."))
            }
            .listRowBackground(Theme.surface)
        }
    }

    private var optionalSection: some View {
        Section("Opcional") {
            TextField("Apelido (marca, farmácia…)", text: $nickname)
            Toggle("Data de abertura", isOn: $hasOpenedAt)
            if hasOpenedAt {
                BRDateField(title: String(localized: "Aberto em"), date: $openedAt)
            }
            TextField("Lote", text: $lot)
            Toggle("Validade", isOn: $hasExpiry)
            if hasExpiry {
                BRDateField(title: String(localized: "Válido até"), date: $expiresAt)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        switch mode {
        case .create(let compound):
            // Pré-preenche com o último vial cadastrado do composto, se houver.
            if let last = compound.lastRegisteredVial {
                volumeText = DecimalInput.text(fromScaled: last.totalMicroliters)
                concentrationText = DecimalInput.text(fromScaled: last.concentrationMicrogramsPerMl)
                remainingText = volumeText
            }
        case .edit(let vial):
            volumeText = DecimalInput.text(fromScaled: vial.totalMicroliters)
            concentrationText = DecimalInput.text(fromScaled: vial.concentrationMicrogramsPerMl)
            remainingText = DecimalInput.text(fromScaled: vial.remainingMicroliters)
            remainingEdited = true
            nickname = vial.nickname
            hasOpenedAt = vial.openedAt != nil
            openedAt = vial.openedAt ?? Date()
            lot = vial.lot
            hasExpiry = vial.expiresAt != nil
            expiresAt = vial.expiresAt ?? Date()
        }
    }

    private func save() {
        guard let total = volumeMicroliters, let concentration = concentrationValue, let remaining = remainingMicroliters else { return }
        let input = VialService.VialInput(totalMicroliters: total, concentrationMicrogramsPerMl: concentration,
                                          remainingMicroliters: remaining, nickname: nickname,
                                          openedAt: hasOpenedAt ? openedAt : nil, lot: lot,
                                          expiresAt: hasExpiry ? expiresAt : nil)
        var message: String
        switch mode {
        case .create(let compound):
            let vial = VialService.add(input, to: compound, in: context)
            message = String(localized: "\(compound.displayName(of: vial)) salvo")
        case .edit(let vial):
            VialService.update(vial, with: input, in: context)
            message = String(localized: "Vial atualizado")
        }
        if let compound {
            let ml = VolumeMath.microlitersPerApplication(doseMicrograms: compound.doseMicrograms, concentrationMicrogramsPerMl: concentration)
            message += " · " + String(localized: "\(InsightText.volume(ml)) por aplicação")
        }
        appState.tick()
        appState.showToast(message)
        Task { await NotificationScheduler.shared.reschedule() }
        dismiss()
    }
}

extension Result where Failure == NumberInputError {
    func errorMessage(min: String, max: String) -> String? {
        if case .failure(let error) = self { return error.message(min: min, max: max) }
        return nil
    }
}
