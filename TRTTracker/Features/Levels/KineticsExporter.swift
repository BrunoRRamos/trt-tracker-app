import SwiftUI
import TRTCore

/// Saídas da análise (seção 6 da spec): fig_liberacao.{png,pdf}, fig_sensibilidade.{png,pdf} e metricas.csv.
/// Gera os arquivos numa pasta temporária, só no aparelho, para o usuário compartilhar se quiser.
@MainActor
enum KineticsExporter {
    static let figureWidth: CGFloat = 720

    static func export(compoundName: String, metrics: [ReleaseMetrics], highlightKey: String?,
                       sensitivityMetric: ReleaseMetrics) -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "cinetica-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return []
        }
        var urls: [URL] = []

        let csv = folder.appending(path: "metricas.csv")
        if (try? ReleaseMetricsBuilder.csv(metrics).write(to: csv, atomically: true, encoding: .utf8)) != nil {
            urls.append(csv)
        }

        let release = figure(title: String(localized: "Liberação cumulativa — \(compoundName)")) {
            ReleaseChartView(metrics: metrics, highlightKey: highlightKey)
            Text("Tempo para liberar 90% da dose (t_90)").font(.headline).foregroundStyle(Theme.textPrimary)
            T90BarsView(metrics: metrics, highlightKey: highlightKey)
        }
        urls += render(release, name: "fig_liberacao", in: folder)

        let sensitivity = figure(title: String(localized: "Sensibilidade a k_e — \(sensitivityMetric.entry.displayName)")) {
            SensitivityChartView(metric: sensitivityMetric, color: EsterColorScale(metrics).color(sensitivityMetric.halfLifeHours))
            OriginBadge(origin: sensitivityMetric.origin)
        }
        urls += render(sensitivity, name: "fig_sensibilidade", in: folder)
        return urls
    }

    private static func figure<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
            content()
            KineticsFootnote()
            Text("TRT-Tracker · \(Formatting.numericDate(Date()))").font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(24)
        .frame(width: figureWidth)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Theme.locale)
        .environment(\.dynamicTypeSize, .large)
        .environment(AppState.shared)
    }

    private static func render<Content: View>(_ view: Content, name: String, in folder: URL) -> [URL] {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: figureWidth, height: nil)
        var urls: [URL] = []

        renderer.scale = 3
        let png = folder.appending(path: "\(name).png")
        if let data = renderer.uiImage?.pngData(), (try? data.write(to: png)) != nil {
            urls.append(png)
        }

        let pdf = folder.appending(path: "\(name).pdf")
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(pdf as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        if FileManager.default.fileExists(atPath: pdf.path) { urls.append(pdf) }
        return urls
    }
}
