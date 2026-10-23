import SwiftUI
import TRTCore
import UIKit

/// Cinética de liberação dos ésteres de um esteroide-pai: liberação cumulativa + t_90, sensibilidade a k_e,
/// métricas e exportação (fig_liberacao, fig_sensibilidade, metricas.csv).
struct EsterKineticsView: View {
    let compoundName: String
    var highlightKey: String?

    @State private var metrics: [ReleaseMetrics]?
    @State private var sensitivityKey: String?
    @State private var shareItems: ShareItems?
    @State private var isExporting = false

    private let catalog = CompoundCatalog.shared

    private var compound: CatalogCompound? { catalog.compounds.first { $0.name == compoundName } }

    private var sensitivityMetric: ReleaseMetrics? {
        guard let metrics else { return nil }
        return metrics.first { $0.id == sensitivityKey } ?? metrics.first { $0.id == highlightKey } ?? metrics.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing(2)) {
                if let metrics {
                    content(metrics)
                } else {
                    ProgressView("Calculando métricas…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing(4))
                }
            }
            .padding(Theme.spacing(2))
        }
        .screenBackground()
        .navigationTitle(compoundName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    export()
                } label: {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
                .disabled(metrics == nil || isExporting)
            }
        }
        .sheet(item: $shareItems) { items in
            ShareSheet(items: items.urls)
        }
        .task {
            guard metrics == nil else { return }
            let entries = catalog.depotEntries.filter { $0.compoundName == compoundName }
            let reference = catalog.referenceEntry
            // A propagação de incerteza (Monte Carlo, 10⁴ amostras por k_e) roda fora da thread principal.
            metrics = await Task.detached(priority: .userInitiated) {
                ReleaseMetricsBuilder.metrics(for: entries, reference: reference)
            }.value
        }
    }

    @ViewBuilder
    private func content(_ metrics: [ReleaseMetrics]) -> some View {
        if let compound {
            Text("\(compound.chemicalName) · \(Plural.esters(metrics.count)) intramusculares em veículo oleoso")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }

        section(String(localized: "Liberação cumulativa"),
                subtitle: String(localized: "Fração da dose que já saiu do depósito. Depende só de k_a: a saída mais confiável do modelo.")) {
            ReleaseChartView(metrics: metrics, highlightKey: highlightKey)
        }

        section(String(localized: "Tempo para liberar 90% da dose (t_90)"), subtitle: nil) {
            T90BarsView(metrics: metrics, highlightKey: highlightKey)
        }

        if let metric = sensitivityMetric {
            section(String(localized: "Sensibilidade a k_e"),
                    subtitle: String(localized: "Perfil plasmático normalizado (Bateman) de uma dose. k_e não é publicado: a faixa mostra o efeito de assumir valores diferentes.")) {
                if metrics.count > 1 {
                    Picker("Éster", selection: Binding(get: { metric.id }, set: { sensitivityKey = $0 })) {
                        ForEach(metrics) { Text($0.label).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                }
                SensitivityChartView(metric: metric, color: EsterColorScale(metrics).color(metric.halfLifeHours))
            }
        }

        NoticeView(tone: .info, title: String(localized: "O éster não altera a exposição total"),
                   message: String(localized: "Para o mesmo esteroide-pai e a mesma dose molar, a área sob a curva (AUC) é igual para qualquer éster: ele muda só a distribuição no tempo — pico alto e curto ou pico baixo e longo, com a mesma área."))

        section(String(localized: "Métricas"), subtitle: nil) {
            MetricsTableView(metrics: metrics, highlightKey: highlightKey)
        }

        if let uncertainty = metrics.compactMap(\.uncertainty).first {
            NoticeView(tone: .warning, title: String(localized: "Por que não há valor absoluto"),
                       message: String(localized: "Simulando V_d de 0,5 a 2 L/kg, F de 0,5 a 1 e a incerteza do t½ (×/÷1,2 se medido, ×/÷2 se extrapolado ou sem origem), o C_max absoluto varia \(Formatting.decimal(Decimal(uncertainty.ratio), minFractionDigits: 1, maxFractionDigits: 1))× ou mais entre os percentis 5 e 95 (10⁴ amostras). Um valor pontual em ng/dL não se sustenta."))
        }

        KineticsFootnote()
    }

    private func section<Content: View>(_ title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .card()
    }

    private func export() {
        guard let metrics, let metric = sensitivityMetric else { return }
        isExporting = true
        let urls = KineticsExporter.export(compoundName: compoundName, metrics: metrics, highlightKey: highlightKey,
                                           sensitivityMetric: metric)
        isExporting = false
        if !urls.isEmpty { shareItems = ShareItems(urls: urls) }
    }
}

/// Lista de esteroides-pai com ésteres no modelo de depósito.
struct KineticsCatalogView: View {
    private let catalog = CompoundCatalog.shared

    var body: some View {
        List {
            Section {
                ForEach(catalog.depotCompounds) { compound in
                    NavigationLink {
                        EsterKineticsView(compoundName: compound.name)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(compound.name).foregroundStyle(Theme.textPrimary)
                            Text("\(compound.chemicalName) · \(Plural.esters(catalog.depotEntries.filter { $0.compoundName == compound.name }.count))")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            } footer: {
                Text("Só ésteres intramusculares em veículo oleoso. Orais e suspensões aquosas não seguem cinética de depósito e ficam fora do modelo.")
            }
            .listRowBackground(Theme.surface)
        }
        .listStyle(.insetGrouped)
        .screenBackground()
        .navigationTitle("Cinética dos ésteres")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension Plural {
    static func esters(_ n: Int) -> String {
        n == 1 ? String(localized: "1 éster") : String(localized: "\(n) ésteres")
    }
}
