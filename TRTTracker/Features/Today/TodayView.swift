import SwiftData
import SwiftUI
import TRTCore

/// Destino da folha de registro.
struct ApplyTarget: Identifiable {
    let id = UUID()
    let compound: Compound?
    let dayKey: String?
}

/// Tela inicial: aplicações do dia de todos os protocolos ativos (RF-AGE-04, RF-PRO-08).
struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \TreatmentProtocol.createdAt) private var protocols: [TreatmentProtocol]

    @State private var applyTarget: ApplyTarget?
    @State private var skipTarget: Occurrence?
    @State private var showCreateProtocol = false

    private var now: Date { appState.now }
    private var today: LocalDay { LocalDay(now) }

    private var activeProtocols: [TreatmentProtocol] {
        protocols.filter { $0.status(today: today) == .active }
    }

    /// Atrasadas de dias anteriores (até virarem "Não registrada") e as aplicações de hoje.
    private var items: (overdue: [Occurrence], today: [Occurrence]) {
        var overdue: [Occurrence] = []
        var todays: [Occurrence] = []
        for treatment in activeProtocols {
            for compound in treatment.orderedCompounds {
                for occurrence in OccurrenceEngine.occurrences(for: compound, from: today.adding(days: -7), through: today, today: today) {
                    if occurrence.day < today {
                        if occurrence.status(now: now) == .overdue { overdue.append(occurrence) }
                    } else {
                        todays.append(occurrence)
                    }
                }
            }
        }
        return (overdue.sorted { $0.scheduledAt < $1.scheduledAt }, todays.sorted { $0.scheduledAt < $1.scheduledAt })
    }

    private var nextOccurrence: Occurrence? {
        protocols.filter { $0.status(today: today) != .ended }
            .compactMap { OccurrenceEngine.next(in: $0, now: now) }
            .min { $0.scheduledAt < $1.scheduledAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if protocols.isEmpty {
                    EmptyStateView(icon: "syringe", title: String(localized: "Nenhum protocolo"),
                                   message: String(localized: "Crie um protocolo com seus compostos para ver aqui as aplicações do dia."),
                                   actionTitle: String(localized: "Criar protocolo")) { showCreateProtocol = true }
                } else {
                    list
                }
            }
            .screenBackground()
            .navigationTitle("Hoje")
            .toolbar {
                if !activeProtocols.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            applyTarget = ApplyTarget(compound: nil, dayKey: nil)
                        } label: {
                            Label("Registrar aplicação extra", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(item: $applyTarget) { target in
                ApplyView(compound: target.compound, dayKey: target.dayKey)
            }
            .sheet(item: $skipTarget) { occurrence in
                SkipView(occurrence: occurrence)
            }
            .sheet(isPresented: $showCreateProtocol) {
                ProtocolFormView(mode: .create)
            }
        }
    }

    private var list: some View {
        let content = items
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.spacing(2)) {
                Text(Formatting.weekdayDayMonth(now).capitalizedFirst)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)

                if !content.overdue.isEmpty {
                    sectionHeader(String(localized: "Atrasadas"), icon: "exclamationmark.triangle.fill", color: Theme.warning)
                    ForEach(content.overdue) { occurrence in
                        card(occurrence, highlight: true)
                    }
                }

                if !content.today.isEmpty {
                    if !content.overdue.isEmpty {
                        sectionHeader(String(localized: "Hoje"), icon: "sun.max", color: Theme.accent)
                    }
                    ForEach(content.today) { occurrence in
                        card(occurrence, highlight: false)
                    }
                } else {
                    noApplicationsToday
                }
            }
            .padding(Theme.spacing(2))
        }
    }

    private func card(_ occurrence: Occurrence, highlight: Bool) -> some View {
        OccurrenceCard(occurrence: occurrence, now: now, highlightOverdue: highlight, showDate: highlight,
                       onApply: { applyTarget = ApplyTarget(compound: occurrence.compound, dayKey: occurrence.day.key) },
                       onSkip: { skipTarget = occurrence })
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }

    /// Sem aplicações hoje: mostra a próxima prevista e em quantos dias (RF-AGE-04).
    @ViewBuilder
    private var noApplicationsToday: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1)) {
            Label("Nenhuma aplicação hoje", systemImage: "checkmark.circle")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if let next = nextOccurrence {
                Text("Próxima aplicação \(relativeDays(from: today, to: next.day))")
                    .font(.rounded(.title2, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("\(next.compound.name) · \(Formatting.weekdayDayMonth(next.scheduledAt)) às \(Formatting.time(next.scheduledAt))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text(next.compound.treatmentProtocol?.name ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Não há aplicações previstas nos protocolos ativos ou agendados.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button("Criar protocolo") { showCreateProtocol = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .fixedSize()
                    .padding(.top, Theme.spacing(1))
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
