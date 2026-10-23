import SwiftUI
import TRTCore

/// Perfil plasmático normalizado dos compostos do protocolo, pela agenda e pela meia-vida de absorção de cada éster.
struct PlasmaLevelsView: View {
    let treatment: TreatmentProtocol

    @Environment(AppState.self) private var appState
    @State private var showEdit = false

    var body: some View {
        let compounds = treatment.orderedCompounds
        let modeled = compounds.filter { $0.depotEntry != nil }
        let range = ProfileSeriesBuilder.range(for: treatment, compounds: modeled)
        let series = modeled.compactMap { ProfileSeriesBuilder.series(for: $0, now: appState.now, range: range) }
        let unmodeled = compounds.filter { $0.depotEntry == nil }

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing(2)) {
                if series.isEmpty {
                    EmptyStateView(icon: "chart.xyaxis.line", title: String(localized: "Nenhum éster intramuscular"),
                                   message: String(localized: "O perfil normalizado usa o modelo de depósito oleoso: escolha no catálogo um éster intramuscular para cada composto."),
                                   actionTitle: String(localized: "Editar protocolo")) { showEdit = true }
                } else {
                    ProfileChartView(series: series, now: appState.now,
                                     protocolEnd: treatment.endDay.date(hour: 23, minute: 59))
                        .card()
                    if series.count > 1 {
                        Text("Cada faixa é normalizada pelo pico de uma dose do próprio composto: compare formas, não alturas, e não some compostos diferentes.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(series) { item in
                        statsCard(item, compound: modeled.first { $0.id == item.id })
                    }
                    KineticsFootnote()
                }
                ForEach(unmodeled) { compound in
                    NoticeView(tone: .warning, title: String(localized: "\(compound.name): sem perfil"),
                               message: unmodeledReason(compound))
                }
            }
            .padding(Theme.spacing(2))
        }
        .screenBackground()
        .navigationTitle("Perfil normalizado")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            ProtocolFormView(mode: .edit(treatment))
        }
    }

    private func unmodeledReason(_ compound: Compound) -> String {
        guard let entry = compound.catalogEntry else {
            return String(localized: "Composto fora do catálogo.")
        }
        return entry.variant.route == .oral
            ? String(localized: "Composto oral: não segue cinética de depósito oleoso.")
            : String(localized: "Suspensão aquosa: não segue cinética de depósito oleoso.")
    }

    private func statsCard(_ item: ProfileSeries, compound: Compound?) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1)) {
            HStack(spacing: Theme.spacing(1)) {
                StrokeSample(color: Theme.chart(item.colorIndex), measured: item.origin.isMeasured)
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            if let compound {
                Text("\(Formatting.milligrams(compound.doseMicrograms)) · \(compound.schedule.summary)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            ProfileStatsView(series: item)
            NavigationLink {
                EsterKineticsView(compoundName: item.entry.compoundName, highlightKey: item.entry.key)
            } label: {
                Label("Cinética de liberação do éster", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.top, 4)
        }
        .card()
    }
}
