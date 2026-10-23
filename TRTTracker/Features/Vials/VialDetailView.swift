import SwiftData
import SwiftUI
import TRTCore

/// Detalhe do vial: anel de nível, dados, ações (editar, ajustar, arquivar/excluir) e histórico do vial.
struct VialDetailView: View {
    let vial: Vial

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var showEdit = false
    @State private var showAdjust = false
    @State private var confirmArchive = false
    @State private var vialToDelete: Vial?
    @State private var isDeleting = false

    var body: some View {
        Group {
            if isDeleting || vial.isDeleted || vial.compound == nil {
                Color.clear
            } else {
                content(vial.compound!)
            }
        }
        .screenBackground()
        .navigationTitle(isDeleting ? "" : (vial.compound.map { $0.displayName(of: vial) } ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) { VialFormView(mode: .edit(vial)) }
        .sheet(isPresented: $showAdjust) { AdjustVialView(vial: vial) }
        .confirmationDialog("Arquivar vial?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Arquivar") {
                VialService.archive(vial, in: context)
                appState.tick()
                Task { await NotificationScheduler.shared.reschedule() }
            }
        } message: {
            Text("O vial sai da fila de estoque, mas o histórico de aplicações é preservado.")
        }
        .vialDeletionDialog(vial: $vialToDelete) { _ in deleteVial() }
    }

    private func content(_ compound: Compound) -> some View {
        let insights = CompoundInsights(compound: compound, now: appState.now)
        let remainingApps = insights.applicationsRemaining(in: vial)
        return List {
            Section {
                VStack(spacing: Theme.spacing(1)) {
                    VialRing(fraction: vial.fractionRemaining,
                             percentText: Formatting.percent(vial.percentRemaining),
                             millilitersText: String(localized: "\(Formatting.milliliters(vial.remainingMicroliters)) restantes"),
                             tint: vial.levelTint(applicationsRemaining: remainingApps),
                             size: 150,
                             accessibilityText: InsightText.vialAccessibility(compound: compound, vial: vial, insights: insights))
                    statusBadge(compound)
                    if insights.currentVial?.id == vial.id, let duration = InsightText.duration(insights) {
                        Text(duration)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.spacing(1))
            }
            .listRowBackground(Theme.surface)

            Section("Nível") {
                InfoRow(label: String(localized: "Restante"), value: "\(Formatting.milliliters(vial.remainingMicroliters)) · \(Formatting.percent(vial.percentRemaining))")
                InfoRow(label: String(localized: "Massa restante"), value: Formatting.milligrams(vial.remainingMicrograms))
                InfoRow(label: String(localized: "Aplicações restantes"), value: "\(remainingApps)")
                InfoRow(label: String(localized: "Por aplicação"), value: InsightText.volume(compound.perApplicationMicroliters(for: vial)))
            }
            .listRowBackground(Theme.surface)

            Section("Dados do vial") {
                InfoRow(label: String(localized: "Volume total"), value: Formatting.milliliters(vial.totalMicroliters))
                InfoRow(label: String(localized: "Concentração"), value: "\(Formatting.milligramsValue(vial.concentrationMicrogramsPerMl)) mg/ml")
                if !vial.nickname.isEmpty { InfoRow(label: String(localized: "Apelido"), value: vial.nickname) }
                if let opened = vial.openedAt { InfoRow(label: String(localized: "Aberto em"), value: Formatting.numericDate(opened)) }
                if !vial.lot.isEmpty { InfoRow(label: String(localized: "Lote"), value: vial.lot) }
                if let expiry = vial.expiresAt { InfoRow(label: String(localized: "Validade"), value: Formatting.numericDate(expiry)) }
            }
            .listRowBackground(Theme.surface)

            Section {
                Button("Editar vial", systemImage: "pencil") { showEdit = true }
                Button("Ajustar nível", systemImage: "slider.horizontal.3") { showAdjust = true }
                if vial.hasApplications && !vial.isArchived {
                    Button("Arquivar vial", systemImage: "archivebox") { confirmArchive = true }
                }
                Button("Excluir vial", systemImage: "trash", role: .destructive) { vialToDelete = vial }
            } footer: {
                if vial.hasApplications {
                    Text("Este vial tem aplicações registradas. Arquivar tira o vial da fila e mantém o vínculo com o histórico; excluir mantém os registros, mas sem o vial.")
                }
            }
            .listRowBackground(Theme.surface)

            historySection(compound)
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func statusBadge(_ compound: Compound) -> some View {
        if vial.isArchived {
            StatusBadge(title: String(localized: "Arquivado"), icon: "archivebox", color: Theme.textSecondary)
        } else if vial.isDepleted {
            StatusBadge(title: String(localized: "Esgotado"), icon: "drop", color: Theme.critical)
        } else if compound.currentVial?.id == vial.id {
            StatusBadge(title: String(localized: "Vial atual"), icon: "drop.fill", color: Theme.accent)
        } else {
            StatusBadge(title: String(localized: "Em estoque"), icon: "shippingbox", color: Theme.textSecondary)
        }
    }

    private enum VialHistoryItem: Identifiable {
        case usage(VialUsage)
        case adjustment(VialAdjustment)

        var id: PersistentIdentifier {
            switch self {
            case .usage(let u): u.persistentModelID
            case .adjustment(let a): a.persistentModelID
            }
        }

        var date: Date {
            switch self {
            case .usage(let u): u.event?.performedAt ?? .distantPast
            case .adjustment(let a): a.date
            }
        }
    }

    @ViewBuilder
    private func historySection(_ compound: Compound) -> some View {
        let items = (vial.usages.map(VialHistoryItem.usage) + vial.adjustments.map(VialHistoryItem.adjustment))
            .sorted { $0.date > $1.date }
        Section("Histórico do vial") {
            if items.isEmpty {
                Text("Nenhuma aplicação ou ajuste neste vial.")
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(items) { item in
                switch item {
                case .usage(let usage):
                    HistoryLine(icon: "syringe", tint: Theme.success,
                                title: String(localized: "Aplicação · −\(Formatting.milliliters(usage.microliters))"),
                                subtitle: "\(Formatting.numericDate(item.date)) \(Formatting.time(item.date))"
                                    + (usage.event.map { " · " + Formatting.milligrams($0.doseMicrograms) } ?? ""))
                case .adjustment(let adjustment):
                    HistoryLine(icon: "slider.horizontal.3", tint: Theme.warning,
                                title: String(localized: "Ajuste · \(Formatting.milliliters(adjustment.beforeMicroliters)) → \(Formatting.milliliters(adjustment.afterMicroliters))"),
                                subtitle: "\(Formatting.numericDate(adjustment.date)) \(Formatting.time(adjustment.date))"
                                    + (adjustment.note.isEmpty ? "" : " · \(adjustment.note)"))
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private func deleteVial() {
        isDeleting = true
        dismiss()
        let modelContext = context
        let state = appState
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            VialService.delete(vial, in: modelContext)
            state.tick()
            state.showToast(String(localized: "Vial excluído"))
        }
    }
}

struct HistoryLine: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(1.5)) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
