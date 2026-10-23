import SwiftData
import SwiftUI
import TRTCore

/// Lista agrupada em Ativos, Agendados e Encerrados (RF-PRO-03).
struct ProtocolsListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \TreatmentProtocol.createdAt, order: .reverse) private var protocols: [TreatmentProtocol]
    @State private var showCreate = false

    private var today: LocalDay { LocalDay(appState.now) }

    var body: some View {
        NavigationStack {
            Group {
                if protocols.isEmpty {
                    EmptyStateView(icon: "list.bullet.rectangle", title: String(localized: "Nenhum protocolo"),
                                   message: String(localized: "Um protocolo reúne seus compostos, a agenda e os vials. Comece criando o primeiro."),
                                   actionTitle: String(localized: "Criar protocolo")) { showCreate = true }
                } else {
                    list
                }
            }
            .screenBackground()
            .navigationTitle("Protocolos")
            .navigationDestination(for: TreatmentProtocol.self) { ProtocolDetailView(treatment: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreate = true
                    } label: {
                        Label("Criar protocolo", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                ProtocolFormView(mode: .create)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(ProtocolStatus.allCases, id: \.self) { status in
                let group = protocols.filter { $0.status(today: today) == status }
                if !group.isEmpty {
                    Section(status.sectionTitle) {
                        ForEach(group) { treatment in
                            NavigationLink(value: treatment) {
                                ProtocolRow(treatment: treatment, now: appState.now)
                            }
                            .listRowBackground(Theme.surface)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// Nome, período, situação, nº de compostos e próxima aplicação prevista.
struct ProtocolRow: View {
    let treatment: TreatmentProtocol
    let now: Date

    var body: some View {
        let today = LocalDay(now)
        let status = treatment.status(today: today)
        VStack(alignment: .leading, spacing: Theme.spacing(1)) {
            AdaptiveStack {
                Text(treatment.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                StatusBadge(status)
            }
            Text(Formatting.period(start: treatment.startDay, end: treatment.endDay))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
            Text(Plural.compounds(treatment.compounds.count))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            if let next = OccurrenceEngine.next(in: treatment, now: now) {
                Label {
                    Text("Próxima: \(next.compound.name) · \(Formatting.weekdayDayMonth(next.scheduledAt)) às \(Formatting.time(next.scheduledAt))")
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.footnote)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
