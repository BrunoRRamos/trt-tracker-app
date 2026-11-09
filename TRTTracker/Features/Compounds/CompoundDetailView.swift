import SwiftData
import SwiftUI
import TRTCore

/// Composto: vial atual, fila de estoque reordenável, esgotados/arquivados e projeções (RF-VIA-03 a 09).
struct CompoundDetailView: View {
    let compound: Compound

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var showAddVial = false
    @State private var applyTarget: ApplyTarget?
    @State private var vialToDelete: Vial?
    @State private var confirmDeleteCompound = false
    @State private var showCannotDelete = false
    @State private var isDeleting = false

    private var now: Date { appState.now }

    var body: some View {
        Group {
            if isDeleting || compound.isDeleted {
                Color.clear
            } else {
                content
            }
        }
        .screenBackground()
        .navigationTitle(isDeleting ? "" : compound.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Excluir composto?", isPresented: $confirmDeleteCompound) {
            Button("Excluir", role: .destructive, action: deleteCompound)
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta ação é irreversível: o composto, seus vials e todo o histórico de aplicações dele serão apagados.")
        }
        .alert("Não é possível excluir", isPresented: $showCannotDelete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Este é o único composto do protocolo, e o protocolo precisa de pelo menos um. Adicione outro composto ou exclua o protocolo.")
        }
    }

    private var content: some View {
        let insights = CompoundInsights(compound: compound, now: now)
        return List {
            summarySection
            currentSection(insights)
            stockSection(insights)
            Section("Estoque e protocolo") {
                StockInsightsView(compound: compound, insights: insights)
                    .padding(.vertical, 4)
            }
            .listRowBackground(Theme.surface)
            inactiveSection(insights)
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Vial.self) { VialDetailView(vial: $0) }
        .vialDeletionDialog(vial: $vialToDelete)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Cadastrar vial", systemImage: "plus") { showAddVial = true }
                    if compound.lastRegisteredVial != nil {
                        Button("Adicionar mais um igual", systemImage: "plus.square.on.square") { duplicateLast() }
                    }
                    Button("Registrar aplicação", systemImage: "syringe") {
                        applyTarget = ApplyTarget(compound: compound, dayKey: nil)
                    }
                    Divider()
                    Button("Excluir composto", systemImage: "trash", role: .destructive) {
                        if CompoundService.canDelete(compound) { confirmDeleteCompound = true } else { showCannotDelete = true }
                    }
                } label: {
                    Label("Ações", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddVial) {
            VialFormView(mode: .create(compound))
        }
        .sheet(item: $applyTarget) { target in
            ApplyView(compound: target.compound, dayKey: target.dayKey)
        }
    }

    private var summarySection: some View {
        Section {
            if let entry = compound.catalogEntry {
                InfoRow(label: String(localized: "Substância"), value: "\(entry.chemicalName) · \(entry.variant.route.title)")
            }
            InfoRow(label: String(localized: "Dose"), value: Formatting.milligrams(compound.doseMicrograms))
            InfoRow(label: String(localized: "Agenda"), value: compound.schedule.summary)
            InfoRow(label: String(localized: "Lembrete"), value: reminderText)
            if !compound.notes.isEmpty {
                Text(compound.notes)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var reminderText: String {
        guard compound.reminderEnabled else { return String(localized: "Desligado") }
        let time = compound.reminderTime
        return Formatting.time(hour: time.hour, minute: time.minute)
    }

    @ViewBuilder
    private func currentSection(_ insights: CompoundInsights) -> some View {
        Section("Vial atual") {
            if let vial = insights.currentVial {
                NavigationLink(value: vial) {
                    CurrentVialSummary(compound: compound, insights: insights)
                        .padding(.vertical, 4)
                }
                .vialSwipeActions(vial, onDelete: { vialToDelete = vial }, onArchive: { archive(vial) })
            } else {
                EmptyStateView(icon: "testtube.2", title: String(localized: "Sem vial cadastrado"),
                               message: String(localized: "Cadastre um vial para acompanhar o nível, a duração e o estoque."),
                               actionTitle: String(localized: "Cadastrar vial")) { showAddVial = true }
            }
        }
        .listRowBackground(Theme.surface)
    }

    @ViewBuilder
    private func stockSection(_ insights: CompoundInsights) -> some View {
        let stock = compound.stockVials
        Section {
            if stock.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacing(1)) {
                    Text("Nenhum vial em estoque.")
                        .foregroundStyle(Theme.textSecondary)
                    if compound.lastRegisteredVial != nil {
                        Button("Adicionar mais um igual", action: duplicateLast)
                            .buttonStyle(SecondaryButtonStyle(tint: Theme.accent))
                    } else {
                        Button("Cadastrar vial") { showAddVial = true }
                            .buttonStyle(SecondaryButtonStyle(tint: Theme.accent))
                    }
                }
                .padding(.vertical, 4)
            } else {
                ForEach(stock) { vial in
                    NavigationLink(value: vial) {
                        VialRow(compound: compound, vial: vial, insights: insights)
                    }
                    .vialSwipeActions(vial, onDelete: { vialToDelete = vial }, onArchive: { archive(vial) })
                }
                .onMove { source, destination in
                    var reordered = stock
                    reordered.move(fromOffsets: source, toOffset: destination)
                    VialService.reorderStock(of: compound, newOrder: reordered, in: context)
                    appState.tick()
                    Task { await NotificationScheduler.shared.reschedule() }
                }
            }
        } header: {
            HStack {
                Text("Estoque (fila)")
                Spacer()
                if stock.count > 1 {
                    EditButton()
                        .font(.footnote.weight(.semibold))
                        .textCase(nil)
                }
            }
        } footer: {
            Text("Quando o vial atual esvazia, o próximo da fila vira o atual. Toque e segure ou use Editar para reordenar; deslize para excluir ou arquivar.")
        }
        .listRowBackground(Theme.surface)
    }

    @ViewBuilder
    private func inactiveSection(_ insights: CompoundInsights) -> some View {
        let inactive = compound.inactiveVials
        if !inactive.isEmpty {
            Section("Esgotados e arquivados") {
                ForEach(inactive) { vial in
                    NavigationLink(value: vial) {
                        VialRow(compound: compound, vial: vial, insights: insights)
                    }
                    .vialSwipeActions(vial, onDelete: { vialToDelete = vial }, onArchive: { archive(vial) })
                }
            }
            .listRowBackground(Theme.surface)
        }
    }

    private func archive(_ vial: Vial) {
        VialService.archive(vial, in: context)
        appState.tick()
        appState.showToast(String(localized: "Vial arquivado"))
        Task { await NotificationScheduler.shared.reschedule() }
    }

    /// Volta para a tela anterior antes de excluir, para nenhuma tela exibir o composto apagado.
    private func deleteCompound() {
        Haptics.warning()
        isDeleting = true
        dismiss()
        let modelContext = context
        let state = appState
        let name = compound.name
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            CompoundService.delete(compound, in: modelContext)
            state.tick()
            state.showToast(String(localized: "\(name) excluído"))
        }
    }

    private func duplicateLast() {
        guard let vial = VialService.duplicateLast(of: compound, in: context) else { return }
        appState.tick()
        Task { await NotificationScheduler.shared.reschedule() }
        appState.showToast(String(localized: "\(compound.displayName(of: vial)) adicionado ao estoque"))
    }
}

/// Linha de vial com barra de nível, %, ml, mg e aplicações restantes (RF-VIA-04).
struct VialRow: View {
    let compound: Compound
    let vial: Vial
    let insights: CompoundInsights

    var body: some View {
        let remainingApps = insights.applicationsRemaining(in: vial)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(compound.displayName(of: vial))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if vial.isArchived {
                    StatusBadge(title: String(localized: "Arquivado"), icon: "archivebox", color: Theme.textSecondary)
                } else if vial.isDepleted {
                    StatusBadge(title: String(localized: "Esgotado"), icon: "drop", color: Theme.critical)
                }
            }
            LevelBar(fraction: vial.fractionRemaining, tint: vial.levelTint(applicationsRemaining: remainingApps))
            Text([
                Formatting.percent(vial.percentRemaining),
                Formatting.milliliters(vial.remainingMicroliters),
                Formatting.milligrams(vial.remainingMicrograms),
                Plural.applications(remainingApps)
            ].joined(separator: " · "))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(InsightText.vialAccessibility(compound: compound, vial: vial, insights: insights)
                            + ", " + Plural.applications(remainingApps) + String(localized: " restantes"))
    }
}
