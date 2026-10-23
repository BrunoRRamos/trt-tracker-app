import SwiftUI
import TRTCore

/// Anel que esvazia conforme o uso, com a porcentagem no centro e os ml restantes abaixo (RF-UI-03).
struct VialRing: View {
    let fraction: Double
    let percentText: String
    let millilitersText: String
    var tint: Color = Theme.accent
    var size: CGFloat = 120
    var accessibilityText: String

    @ScaledMetric private var scale: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var diameter: CGFloat { min(size * scale, size * 1.6) }
    private var lineWidth: CGFloat { max(6, diameter * 0.09) }

    var body: some View {
        VStack(spacing: Theme.spacing(1)) {
            ZStack {
                Circle()
                    .stroke(Theme.border, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.0001, fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(fraction > 0 ? 1 : 0)
                Text(percentText)
                    .font(.rounded(size > 80 ? .title : .subheadline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(lineWidth)
                    .contentTransition(.numericText())
            }
            .frame(width: diameter, height: diameter)
            .motion(fraction)

            Text(millilitersText)
                .font(.rounded(.subheadline, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// Barra horizontal do nível do vial, para linhas compactas.
struct LevelBar: View {
    let fraction: Double
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(tint)
                    .frame(width: proxy.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 6)
        .motion(fraction)
        .accessibilityHidden(true)
    }
}

extension Vial {
    /// Cor do nível: acento, aviso perto do fim ou crítico quando vazio.
    func levelTint(applicationsRemaining: Int, threshold: Int = 2) -> Color {
        if isDepleted { return Theme.critical }
        if applicationsRemaining <= threshold { return Theme.warning }
        return Theme.accent
    }
}
