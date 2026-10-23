import Charts
import SwiftUI
import TRTCore

/// Cor de um éster pela posição do seu t½ (escala log) entre os ésteres comparados: claro = curto, escuro = longo.
struct EsterColorScale {
    let minHalfLife: Double
    let maxHalfLife: Double

    init(_ metrics: [ReleaseMetrics]) {
        minHalfLife = metrics.map(\.halfLifeHours).min() ?? 1
        maxHalfLife = metrics.map(\.halfLifeHours).max() ?? 1
    }

    func color(_ halfLife: Double) -> Color {
        guard maxHalfLife > minHalfLife else { return Theme.ramp(0.6) }
        return Theme.ramp((log(halfLife) - log(minHalfLife)) / (log(maxHalfLife) - log(minHalfLife)))
    }
}

/// Rótulo curto do éster: "Cipionato", "Undecanoato (Óleo de rícino)".
extension ReleaseMetrics {
    var label: String { entry.variantLabel ?? entry.displayName }
}

private func hourTicks(upTo maximum: Double, from minimum: Double = 0) -> [Double] {
    [1, 6, 24, 72, 168, 336, 720, 1440, 2160, 4320, 8760].filter { $0 >= minimum && $0 <= maximum }
}

private func tickLabel(_ hours: Double) -> String {
    hours < 48 ? "\(Formatting.decimal(Decimal(hours), maxFractionDigits: 0)) h"
               : "\(Formatting.decimal(Decimal(hours / 24), maxFractionDigits: 0)) d"
}

/// Liberação cumulativa F_lib(t) = 1 − exp(−k_a·t): saída primária, depende só de k_a.
/// Eixo do tempo logarítmico, para comparar ésteres de horas a meses.
struct ReleaseChartView: View {
    let metrics: [ReleaseMetrics]
    var highlightKey: String?

    @State private var selectedHour: Double?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 240

    private var scale: EsterColorScale { EsterColorScale(metrics) }
    private var maxHour: Double { min(8760, max(48, metrics.map(\.t99).max() ?? 48)) }

    private func samples(_ metric: ReleaseMetrics) -> [(hours: Double, fraction: Double)] {
        let steps = 160
        return (0...steps).map { i in
            let hours = exp(log(1) + (log(maxHour) - log(1)) * Double(i) / Double(steps))
            return (hours, ReleaseKinetics.cumulativeRelease(hours, ka: metric.ka))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            readout
            Chart {
                ForEach(metrics) { metric in
                    let isHighlighted = metric.id == highlightKey
                    ForEach(samples(metric), id: \.hours) { point in
                        LineMark(x: .value("Tempo (h)", point.hours), y: .value("Fração da dose", point.fraction),
                                 series: .value("Éster", metric.id))
                            .foregroundStyle(scale.color(metric.halfLifeHours))
                            .lineStyle(metric.origin.stroke(width: isHighlighted ? 3.5 : 2))
                    }
                }
                RuleMark(y: .value("90%", 0.9))
                    .foregroundStyle(Theme.border)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("0,9").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                if let selectedHour {
                    RuleMark(x: .value("Seleção", selectedHour))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXSelection(value: $selectedHour)
            .chartXScale(domain: 1...maxHour, type: .log)
            .chartYScale(domain: 0...1)
            .chartXAxis {
                AxisMarks(values: hourTicks(upTo: maxHour, from: 1)) { value in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel {
                        if let h = value.as(Double.self) { Text(tickLabel(h)).foregroundStyle(Theme.textSecondary) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 0.25, 0.5, 0.75, 1]) { value in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(Formatting.decimal(Decimal(v), maxFractionDigits: 2)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .chartYAxisLabel(position: .leading) {
                Text("Fração da dose liberada (adimensional)").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .chartXAxisLabel(position: .bottom) {
                Text("Tempo após a aplicação (escala log)").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .frame(height: chartHeight)
            .accessibilityLabel(Text("Liberação cumulativa por éster"))
            .accessibilityValue(Text(metrics.map { "\($0.label): 90% em \(Formatting.duration(hours: $0.t90))" }.joined(separator: ". ")))

            legend
        }
    }

    @ViewBuilder
    private var readout: some View {
        if let selectedHour {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Formatting.duration(hours: selectedHour)) após a aplicação")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(metrics) { metric in
                    HStack(spacing: Theme.spacing(1)) {
                        StrokeSample(color: scale.color(metric.halfLifeHours), measured: metric.origin.isMeasured)
                        Text(metric.label).foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: Theme.spacing(1))
                        Text(Formatting.percentValue(ReleaseKinetics.cumulativeRelease(selectedHour, ka: metric.ka) * 100))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .font(.footnote)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Toque e arraste para ler a fração liberada de cada éster.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(metrics) { metric in
                HStack(spacing: Theme.spacing(1)) {
                    StrokeSample(color: scale.color(metric.halfLifeHours), measured: metric.origin.isMeasured,
                                 width: metric.id == highlightKey ? 3.5 : 2)
                    Text(metric.label)
                        .font(.footnote.weight(metric.id == highlightKey ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: Theme.spacing(1))
                    Text("t½ \(Formatting.halfLife(hours: metric.halfLifeHours))")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            OriginLineKey()
            Text("Cor ordenada por t½: mais clara = liberação mais rápida.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Barras de t_90 (90% da dose liberada) por éster, com rótulo direto.
struct T90BarsView: View {
    let metrics: [ReleaseMetrics]
    var highlightKey: String?

    private var scale: EsterColorScale { EsterColorScale(metrics) }

    var body: some View {
        Chart(metrics) { metric in
            BarMark(x: .value("t_90 (dias)", metric.t90 / 24), y: .value("Éster", metric.label), height: .ratio(0.6))
                .foregroundStyle(scale.color(metric.halfLifeHours))
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text(Formatting.duration(hours: metric.t90) + (metric.origin.isMeasured ? "" : " · extrap."))
                        .font(.caption2.weight(metric.id == highlightKey ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text("\(Formatting.decimal(Decimal(d), maxFractionDigits: 0)) d").foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) { Text(label).foregroundStyle(Theme.textPrimary) }
                }
            }
        }
        .chartXScale(range: .plotDimension(endPadding: 72))
        .frame(height: CGFloat(max(1, metrics.count)) * 34 + 24)
        .accessibilityLabel(Text("Tempo para liberar 90% da dose"))
        .accessibilityValue(Text(metrics.map { "\($0.label): \(Formatting.duration(hours: $0.t90))" }.joined(separator: ". ")))
    }
}

/// Envelope de C_norm de uma dose única sob variação de k_e (saída secundária, depende de k_e).
struct SensitivityChartView: View {
    let metric: ReleaseMetrics
    var color: Color = Theme.accent

    @State private var selectedHour: Double?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 220

    private var maxHour: Double { min(8760, max(24, metric.t99)) }

    private struct Point { let hours: Double; let low: Double; let high: Double }

    private var points: [Point] {
        let kes = ReleaseKinetics.eliminationHalfLivesHours.map { ReleaseKinetics.rate(halfLifeHours: $0) }
        let grid = (0...200).map { maxHour * Double($0) / 200 } + kes.map { ReleaseKinetics.tMax(ka: metric.ka, ke: $0) }
        return Set(grid).sorted().map { t in
            let values = kes.map { ReleaseKinetics.batemanNormalized(t, ka: metric.ka, ke: $0) }
            return Point(hours: t, low: values.min() ?? 0, high: values.max() ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            readout
            Chart {
                ForEach(points, id: \.hours) { p in
                    AreaMark(x: .value("Tempo (h)", p.hours), yStart: .value("Mínimo", p.low), yEnd: .value("Máximo", p.high))
                        .foregroundStyle(color.opacity(0.25))
                }
                ForEach(points, id: \.hours) { p in
                    LineMark(x: .value("Tempo (h)", p.hours), y: .value("C/C_max", p.high), series: .value("Borda", "max"))
                        .foregroundStyle(color)
                        .lineStyle(metric.origin.stroke())
                }
                ForEach(points, id: \.hours) { p in
                    LineMark(x: .value("Tempo (h)", p.hours), y: .value("C/C_max", p.low), series: .value("Borda", "min"))
                        .foregroundStyle(color)
                        .lineStyle(metric.origin.stroke(width: 1))
                }
                if let selectedHour {
                    RuleMark(x: .value("Seleção", selectedHour))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXSelection(value: $selectedHour)
            .chartXScale(domain: 0...maxHour)
            .chartYScale(domain: 0...1)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel {
                        if let h = value.as(Double.self) { Text(tickLabel(max(h, 0))).foregroundStyle(Theme.textSecondary) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 0.25, 0.5, 0.75, 1]) { value in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(Formatting.decimal(Decimal(v), maxFractionDigits: 2)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .chartYAxisLabel(position: .leading) {
                Text("C / C_max (adimensional)").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .chartXAxisLabel(position: .bottom) {
                Text("Tempo após uma aplicação").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .frame(height: chartHeight)
            .accessibilityLabel(Text("Sensibilidade do perfil normalizado a k_e"))
            .accessibilityValue(Text(metric.tMax.map {
                "t_max \(Formatting.duration(hours: $0.hours)) com t½ de eliminação \(Formatting.decimal(Decimal($0.eliminationHalfLifeHours), maxFractionDigits: 1)) h"
            }.joined(separator: ". ")))

            VStack(alignment: .leading, spacing: 4) {
                Text("t_max conforme o k_e assumido")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(metric.tMax, id: \.eliminationHalfLifeHours) { item in
                    InfoRow(label: String(localized: "t½ de eliminação \(Formatting.decimal(Decimal(item.eliminationHalfLifeHours), maxFractionDigits: 1)) h"),
                            value: Formatting.duration(hours: item.hours))
                }
            }
        }
    }

    @ViewBuilder
    private var readout: some View {
        if let selectedHour {
            let kes = ReleaseKinetics.eliminationHalfLivesHours
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Formatting.duration(hours: selectedHour)) após a aplicação")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(kes, id: \.self) { halfLife in
                    HStack {
                        Text("t½ de eliminação \(Formatting.decimal(Decimal(halfLife), maxFractionDigits: 1)) h").foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(Formatting.decimal(Decimal(ReleaseKinetics.batemanNormalized(selectedHour, ka: metric.ka,
                                                                                         ke: ReleaseKinetics.rate(halfLifeHours: halfLife))),
                                                minFractionDigits: 2, maxFractionDigits: 2))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .font(.footnote)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Faixa de C/C_max de uma dose única para \(eliminationSweepLabel). Toque e arraste para ler.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Tabela de métricas: t½ e origem, k_a, t_90, t_99, C_max relativo, t_max (com k_e) e incerteza do C_max.
struct MetricsTableView: View {
    let metrics: [ReleaseMetrics]
    var highlightKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(2)) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(metric.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(metric.id == highlightKey ? Theme.accent : Theme.textPrimary)
                        Spacer()
                        OriginBadge(origin: metric.origin)
                    }
                    InfoRow(label: "t½", value: Formatting.halfLife(hours: metric.halfLifeHours))
                    InfoRow(label: "k_a", value: "\(Formatting.decimal(Decimal(metric.ka), minFractionDigits: 4, maxFractionDigits: 4)) h⁻¹")
                    InfoRow(label: "t_90", value: Formatting.duration(hours: metric.t90))
                    InfoRow(label: "t_99", value: Formatting.duration(hours: metric.t99))
                    InfoRow(label: String(localized: "C_max relativo (propionato = 1)"),
                            value: metric.cmaxRelative.isFinite ? "\(Formatting.decimal(Decimal(metric.cmaxRelative), minFractionDigits: 2, maxFractionDigits: 2))×" : "—")
                    InfoRow(label: "t_max", value: durationRange(metric.tMax.map(\.hours)))
                    if let uncertainty = metric.uncertainty {
                        InfoRow(label: String(localized: "Incerteza do C_max (P95/P5)"),
                                value: "\(Formatting.decimal(Decimal(uncertainty.ratio), minFractionDigits: 1, maxFractionDigits: 1))×")
                    }
                }
                .accessibilityElement(children: .combine)
                if metric.id != metrics.last?.id {
                    Divider().overlay(Theme.border)
                }
            }
            Text("t_max varia com o k_e assumido (\(eliminationSweepLabel)). C_max relativo vale para dose molar igual do esteroide-pai, sob flip-flop.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
