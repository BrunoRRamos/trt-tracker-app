import SwiftData
import SwiftUI
import TRTCore

/// Aba Histórico: registros, pulos e ajustes por protocolo (RF-AGE-07).
struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \TreatmentProtocol.createdAt, order: .reverse) private var protocols: [TreatmentProtocol]
    @State private var selectedID: UUID?
    @State private var showCreate = false

    private var selected: TreatmentProtocol? {
        if let selectedID, let match = protocols.first(where: { $0.id == selectedID }) { return match }
        let today = LocalDay(appState.now)
        return protocols.first { $0.status(today: today) == .active } ?? protocols.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selected {
                    HistoryContent(treatment: selected)
                        .id(selected.id)
                } else {
                    EmptyStateView(icon: "clock.arrow.circlepath", title: String(localized: "Sem histórico"),
                                   message: String(localized: "Os registros, pulos e ajustes aparecem aqui depois que você criar um protocolo."),
                                   actionTitle: String(localized: "Criar protocolo")) { showCreate = true }
                }
            }
            .screenBackground()
            .navigationTitle("Histórico")
            .toolbar {
                if protocols.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Protocolo", selection: Binding(get: { selected?.id }, set: { selectedID = $0 })) {
                                ForEach(protocols) { treatment in
                                    Text(treatment.name).tag(Optional(treatment.id))
                                }
                            }
                        } label: {
                            Label("Protocolo", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                ProtocolFormView(mode: .create)
            }
        }
    }
}

/// Histórico de um protocolo aberto a partir do detalhe.
struct HistoryListScreen: View {
    let treatment: TreatmentProtocol

    var body: some View {
        HistoryContent(treatment: treatment)
            .screenBackground()
            .navigationTitle("Histórico")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Item do histórico: registro/pulo ou ajuste de vial.
enum HistoryEntry: Identifiable {
    case event(DoseEvent)
    case adjustment(VialAdjustment)

    var id: PersistentIdentifier {
        switch self {
        case .event(let e): e.persistentModelID
        case .adjustment(let a): a.persistentModelID
        }
    }

    var date: Date {
        switch self {
        case .event(let e): e.performedAt
        case .adjustment(let a): a.date
        }
    }
}

struct HistoryContent: View {
    let treatment: TreatmentProtocol

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var compoundFilter: UUID?
    @State private var editing: DoseEvent?
    @State private var toDelete: DoseEvent?
    @State private var applyTarget: ApplyTarget?

    private var compounds: [Compound] { treatment.orderedCompounds }

    /// Do mais recente ao mais antigo, com filtro por composto.
    private var entries: [HistoryEntry] {
        let filtered = compounds.filter { compoundFilter == nil || $0.id == compoundFilter }
        var result: [HistoryEntry] = []
        for compound in filtered {
            result += compound.events.map(HistoryEntry.event)
            for vial in compound.vials {
                result += vial.adjustments.map(HistoryEntry.adjustment)
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    var body: some View {
        let items = entries
        List {
            if compounds.count > 1 {
                Section {
                    Picker("Composto", selection: $compoundFilter) {
                        Text("Todos os compostos").tag(UUID?.none)
                        ForEach(compounds) { compound in
                            Text(compound.name).tag(Optional(compound.id))
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }

            Section(treatment.name) {
                if items.isEmpty {
                    EmptyStateView(icon: "clock.arrow.circlepath", title: String(localized: "Nenhum registro"),
                                   message: String(localized: "As aplicações registradas, puladas e os ajustes de vial aparecem aqui."),
                                   actionTitle: treatment.status(today: LocalDay(appState.now)) == .ended ? nil : String(localized: "Registrar aplicação")) {
                        applyTarget = ApplyTarget(compound: compounds.first { $0.id == compoundFilter } ?? compounds.first, dayKey: nil)
                    }
                }
                ForEach(items) { entry in
                    row(entry)
                }
            }
            .listRowBackground(Theme.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .sheet(item: $editing) { event in
            EditEventView(event: event)
        }
        .sheet(item: $applyTarget) { target in
            ApplyView(compound: target.compound, dayKey: target.dayKey)
        }
        .alert("Excluir registro?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), presenting: toDelete) { event in
            Button("Excluir", role: .destructive) { delete(event) }
            Button("Cancelar", role: .cancel) {}
        } message: { event in
            Text(event.kind == .applied
                 ? String(localized: "O volume descontado volta para o vial e as projeções são recalculadas.")
                 : String(localized: "A aplicação volta a ficar pendente."))
        }
    }

    @ViewBuilder
    private func row(_ entry: HistoryEntry) -> some View {
        switch entry {
        case .event(let event):
            EventRow(event: event)
                .swipeActions(edge: .trailing) {
                    Button("Excluir", systemImage: "trash", role: .destructive) { toDelete = event }
                    Button("Editar", systemImage: "pencil") { editing = event }
                        .tint(Theme.accent)
                }
                .contextMenu {
                    Button("Editar", systemImage: "pencil") { editing = event }
                    Button("Excluir", systemImage: "trash", role: .destructive) { toDelete = event }
                }
        case .adjustment(let adjustment):
            AdjustmentRow(adjustment: adjustment)
        }
    }

    private func delete(_ event: DoseEvent) {
        DoseService.delete(event: event, in: context)
        Haptics.warning()
        appState.tick()
        Task { await NotificationScheduler.shared.reschedule() }
    }
}

/// Data, hora, composto, dose, vial e situação.
struct EventRow: View {
    let event: DoseEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AdaptiveStack {
                Text(event.compound?.name ?? "")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                badge
            }
            Text("\(Formatting.numericDate(event.performedAt)) · \(Formatting.time(event.performedAt))")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
            if event.kind == .applied {
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let day = event.scheduledDay, event.kind == .applied, day != LocalDay(event.performedAt) {
                Text("Prevista para \(Formatting.weekdayDayMonth(day))")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !event.note.isEmpty {
                Text(event.note)
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts = [Formatting.milligrams(event.doseMicrograms)]
        if let compound = event.compound {
            let vials = event.orderedUsages.compactMap { usage -> String? in
                guard let vial = usage.vial else { return nil }
                return "\(compound.displayName(of: vial)) (\(Formatting.milliliters(usage.microliters)))"
            }
            parts.append(vials.isEmpty ? String(localized: "sem desconto de estoque") : vials.joined(separator: " + "))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var badge: some View {
        switch event.kind {
        case .applied:
            if event.isExtra {
                StatusBadge(title: String(localized: "Extra"), icon: "plus.circle.fill", color: Theme.success)
            } else {
                StatusBadge(OccurrenceStatus.applied)
            }
        case .skipped:
            StatusBadge(OccurrenceStatus.skipped)
        }
    }
}

struct AdjustmentRow: View {
    let adjustment: VialAdjustment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AdaptiveStack {
                Text(adjustment.vial?.compound?.name ?? "")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                StatusBadge(title: String(localized: "Ajuste"), icon: "slider.horizontal.3", color: Theme.warning)
            }
            Text("\(Formatting.numericDate(adjustment.date)) · \(Formatting.time(adjustment.date))")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
            if let vial = adjustment.vial, let compound = vial.compound {
                Text("\(compound.displayName(of: vial)): \(Formatting.milliliters(adjustment.beforeMicroliters)) → \(Formatting.milliliters(adjustment.afterMicroliters))")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !adjustment.note.isEmpty {
                Text(adjustment.note)
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
