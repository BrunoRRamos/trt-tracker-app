import SwiftUI
import TRTCore

extension Optional where Wrapped == HalfLifeOrigin {
    /// "t½ medido", "t½ extrapolado", "origem do t½ não informada"
    var label: String {
        switch self {
        case .measured?: String(localized: "t½ medido")
        case .extrapolated?: String(localized: "t½ extrapolado")
        case nil: String(localized: "origem do t½ não informada")
        }
    }

    /// Linha cheia só para t½ medido; tracejada para extrapolado ou sem origem. A distinção é dado.
    var isMeasured: Bool { self == .measured }

    func stroke(width: CGFloat = 2) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: isMeasured ? [] : [5, 4])
    }
}

/// Selo da origem da meia-vida (ícone + texto, nunca só estilo de linha).
struct OriginBadge: View {
    let origin: HalfLifeOrigin?

    var body: some View {
        StatusBadge(title: origin.label,
                    icon: origin.isMeasured ? "checkmark.seal" : "questionmark.diamond",
                    color: origin.isMeasured ? Theme.textSecondary : Theme.warning)
    }
}

/// Amostra de traço usada nas legendas (cheio = medido, tracejado = extrapolado/não informado).
struct StrokeSample: View {
    let color: Color
    var measured: Bool = true
    var width: CGFloat = 2

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 3))
            path.addLine(to: CGPoint(x: 22, y: 3))
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, dash: measured ? [] : [5, 4]))
        .frame(width: 22, height: 6)
        .accessibilityHidden(true)
    }
}

/// Legenda do estilo de linha pela origem do t½.
struct OriginLineKey: View {
    var body: some View {
        AdaptiveStack(spacing: Theme.spacing(2)) {
            HStack(spacing: 6) {
                StrokeSample(color: Theme.textSecondary, measured: true)
                Text("t½ medido").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                StrokeSample(color: Theme.textSecondary, measured: false)
                Text("t½ extrapolado ou não informado").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rodapé obrigatório das figuras: nenhuma concentração absoluta é inferível.
struct KineticsFootnote: View {
    var body: some View {
        Text("Modelo de depósito intramuscular oleoso, com a meia-vida tabelada tratada como de absorção (flip-flop). V_d e F se cancelam na normalização: nenhuma concentração absoluta é inferível. Estimativa teórica; não substitui exames laboratoriais.")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Faixa "1,9–2,1×".
func multipleRange(_ range: ClosedRange<Double>) -> String {
    let low = Formatting.decimal(Decimal(range.lowerBound), minFractionDigits: 1, maxFractionDigits: 2)
    let high = Formatting.decimal(Decimal(range.upperBound), minFractionDigits: 1, maxFractionDigits: 2)
    return low == high ? "\(low)×" : "\(low)–\(high)×"
}

/// Faixa de horas para t_max: "4,5–30,9 h".
func durationRange(_ values: [Double]) -> String {
    guard let low = values.min(), let high = values.max() else { return "—" }
    return low == high ? Formatting.duration(hours: low) : "\(Formatting.duration(hours: low)) – \(Formatting.duration(hours: high))"
}

/// Faixa das meias-vidas de eliminação varridas, para acompanhar todo valor que depende de k_e.
var eliminationSweepLabel: String {
    let values = ReleaseKinetics.eliminationHalfLivesHours.map { Formatting.decimal(Decimal($0), maxFractionDigits: 1) }
    return String(localized: "k_e com t½ de eliminação \(values.joined(separator: ", ")) h")
}
