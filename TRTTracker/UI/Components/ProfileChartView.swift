import Charts
import SwiftUI
import TRTCore

/// Perfil plasmático normalizado do protocolo: faixa (envelope sobre k_e) por composto, em múltiplos
/// do pico de uma dose única — grandeza adimensional. Linha cheia para t½ medido, tracejada para extrapolado.
struct ProfileChartView: View {
    let series: [ProfileSeries]
    let now: Date
    var protocolEnd: Date?

    @State private var selectedDate: Date?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 220

    private var domain: ClosedRange<Date>? {
        let dates = series.flatMap(\.envelope).map(\.date)
        guard let min = dates.min(), let max = dates.max(), max > min else { return nil }
        return min...max
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            readout
            chart
            legend
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { item in
                let color = Theme.chart(item.colorIndex)
                ForEach(item.envelope, id: \.date) { point in
                    AreaMark(x: .value("Data", point.date), yStart: .value("Mínimo", point.low),
                             yEnd: .value("Máximo", point.high), series: .value("Faixa", "\(item.id)"))
                        .foregroundStyle(color.opacity(0.22))
                }
                ForEach(item.envelope, id: \.date) { point in
                    LineMark(x: .value("Data", point.date), y: .value("Perfil", point.high),
                             series: .value("Borda", "\(item.id)-max"))
                        .foregroundStyle(color)
                        .lineStyle(item.origin.stroke())
                }
                ForEach(item.envelope, id: \.date) { point in
                    LineMark(x: .value("Data", point.date), y: .value("Perfil", point.low),
                             series: .value("Borda", "\(item.id)-min"))
                        .foregroundStyle(color)
                        .lineStyle(item.origin.stroke(width: 1))
                }
            }

            RuleMark(y: .value("Pico de uma dose", 1.0))
                .foregroundStyle(Theme.border)
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    Text("1× = pico de uma dose").font(.caption2).foregroundStyle(Theme.textSecondary)
                }

            if let domain, domain.contains(now) {
                RuleMark(x: .value("Hoje", now))
                    .foregroundStyle(Theme.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("Hoje").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
            }
            if let protocolEnd, let domain, domain.contains(protocolEnd) {
                RuleMark(x: .value("Fim", protocolEnd))
                    .foregroundStyle(Theme.border)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("Fim").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
            }

            if let selectedDate {
                RuleMark(x: .value("Seleção", selectedDate))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: domain ?? now...now.addingTimeInterval(86400))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Formatting.decimal(Decimal(v), maxFractionDigits: 1))×").foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Formatting.numericDate(date).prefix(5)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .chartYAxisLabel(position: .leading) {
            Text("× pico de uma dose (adimensional)").font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(height: chartHeight)
        .accessibilityLabel(Text("Perfil normalizado do protocolo"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    @ViewBuilder
    private var readout: some View {
        if let selectedDate {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Formatting.weekdayDayMonth(selectedDate)) · \(Formatting.time(selectedDate))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(series) { item in
                    HStack(spacing: Theme.spacing(1)) {
                        StrokeSample(color: Theme.chart(item.colorIndex), measured: item.origin.isMeasured)
                        Text(item.name).foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: Theme.spacing(1))
                        Text(multipleRange(item.band(at: selectedDate)))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .font(.footnote)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Toque e arraste no gráfico para ler a faixa em cada data.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            if series.count > 1 {
                ForEach(series) { item in
                    HStack(spacing: Theme.spacing(1)) {
                        StrokeSample(color: Theme.chart(item.colorIndex), measured: item.origin.isMeasured)
                        Text(item.name).font(.footnote).foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            OriginLineKey()
            Text("Faixa: \(eliminationSweepLabel).")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var accessibilitySummary: String {
        series.map { item in
            let current = multipleRange(item.band(at: now))
            if let steady = item.steadyState {
                return String(localized: "\(item.name): agora \(current) do pico de uma dose; estável entre \(multipleRange(steady.trough)) e \(multipleRange(steady.peak))")
            }
            return String(localized: "\(item.name): agora \(current) do pico de uma dose")
        }
        .joined(separator: ". ")
    }
}

/// Meia-vida de absorção com origem, t_90, estabilização, pico e vale estáveis (faixas sobre k_e).
struct ProfileStatsView: View {
    let series: ProfileSeries

    var body: some View {
        let ka = ReleaseKinetics.absorptionRate(halfLifeHours: series.absorptionHalfLifeHours)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("t½ de absorção").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(Formatting.halfLife(hours: series.absorptionHalfLifeHours)).foregroundStyle(Theme.textPrimary)
            }
            .font(.subheadline)
            OriginBadge(origin: series.origin)
            InfoRow(label: String(localized: "90% da dose liberada (t_90)"),
                    value: Formatting.duration(hours: ReleaseKinetics.timeToFraction(ka: ka, fraction: 0.9)))
            if let steady = series.steadyState {
                InfoRow(label: String(localized: "Estado estável a partir de"), value: Formatting.numericDate(steady.reachedAt))
                InfoRow(label: String(localized: "Pico estável"), value: multipleRange(steady.peak))
                InfoRow(label: String(localized: "Vale estável"), value: multipleRange(steady.trough))
                Text("Em múltiplos do pico de uma dose única; faixas sobre \(eliminationSweepLabel).")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("O período não chega ao estado estável (5 meias-vidas de absorção = \(Formatting.duration(hours: series.absorptionHalfLifeHours * RegimenProfile.steadyStateHalfLives))).")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
