import SwiftUI
import TRTCore

/// Tokens de cor do Asset Catalog e métricas de layout (RF-UI-02 e 03).
enum Theme {
    static let background = Color("background")
    static let surface = Color("surface")
    static let surfaceElevated = Color("surfaceElevated")
    static let border = Color("border")
    static let textPrimary = Color("textPrimary")
    static let textSecondary = Color("textSecondary")
    static let accent = Color("accent")
    static let success = Color("success")
    static let warning = Color("warning")
    static let critical = Color("critical")


    static let cornerRadius: CGFloat = 16
    /// Grade de 8 pt.
    static func spacing(_ units: CGFloat) -> CGFloat { units * 8 }

    static let animationDuration: Double = 0.25
    static let locale = Locale(identifier: "pt_BR")
}

extension Font {
    /// SF Pro Rounded para números de destaque.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// Anima apenas quando "Reduzir movimento" está desligado (RF-UI-05), com no máximo 0,3 s.
struct MotionAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeInOut(duration: Theme.animationDuration), value: value)
    }
}

extension View {
    func motion<Value: Equatable>(_ value: Value) -> some View {
        modifier(MotionAnimation(value: value))
    }

    func card(padding: CGFloat = Theme.spacing(2)) -> some View {
        modifier(CardStyle(padding: padding))
    }

    /// Fundo padrão das telas.
    func screenBackground() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }

    /// Fundo das folhas (sheets).
    func sheetBackground() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.surfaceElevated.ignoresSafeArea())
            .presentationBackground(Theme.surfaceElevated)
    }
}

func withMotion(_ body: () -> Void) {
    if UIAccessibility.isReduceMotionEnabled {
        body()
    } else {
        withAnimation(.easeInOut(duration: Theme.animationDuration), body)
    }
}

/// Card com cantos de 16 pt e contorno sutil, sem sombra.
struct CardStyle: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// Botão principal com acento e texto escuro (contraste > 4,5:1).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.background)
            .padding(.horizontal, Theme.spacing(2))
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(Theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.spacing(2))
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(Theme.surfaceElevated.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// Empilha na horizontal, ou na vertical nos tamanhos de acessibilidade do Dynamic Type, sem cortar texto.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var spacing: CGFloat = Theme.spacing(1)
    @ViewBuilder var content: () -> Content

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing, content: content)
        } else {
            HStack(spacing: spacing, content: content)
        }
    }
}
