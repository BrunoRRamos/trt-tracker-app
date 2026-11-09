import SwiftUI
import TRTCore

/// Selo de situação: sempre ícone + texto, nunca só cor (RF-UI-05).
struct StatusBadge: View {
    let title: String
    let icon: String
    let color: Color

    init(title: String, icon: String, color: Color) {
        self.title = title
        self.icon = icon
        self.color = color
    }

    init(_ status: ProtocolStatus) {
        self.init(title: status.title, icon: status.icon, color: status.color)
    }

    init(_ status: OccurrenceStatus) {
        self.init(title: status.title, icon: status.icon, color: status.color)
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, Theme.spacing(1))
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Situação: \(title)"))
    }
}

/// Aviso em destaque (estoque, permissão, falta de vial).
struct NoticeView: View {
    enum Tone { case warning, critical, success, info }

    let tone: Tone
    let title: String
    var message: String?

    private var color: Color {
        switch tone {
        case .warning: Theme.warning
        case .critical: Theme.critical
        case .success: Theme.success
        case .info: Theme.accent
        }
    }

    private var icon: String {
        switch tone {
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(1)) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.spacing(1.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Estado vazio com orientação e botão de ação (RF-UI-04).
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
                .foregroundStyle(Theme.textPrimary)
        } description: {
            Text(message)
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .fixedSize()
            }
        }
    }
}

/// Linha "rótulo — valor" que empilha em tamanhos de acessibilidade.
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        AdaptiveStack {
            Text(label)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: Theme.spacing(1))
            Text(value)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

extension Optional where Wrapped == HalfLifeOrigin {
    /// "t½ medido", "t½ extrapolado", "origem do t½ não informada"
    var label: String {
        switch self {
        case .measured?: String(localized: "t½ medido")
        case .extrapolated?: String(localized: "t½ extrapolado")
        case nil: String(localized: "origem do t½ não informada")
        }
    }
}

/// Selo da origem da meia-vida tabelada no catálogo.
struct OriginBadge: View {
    let origin: HalfLifeOrigin?

    var body: some View {
        StatusBadge(title: origin.label,
                    icon: origin == .measured ? "checkmark.seal" : "questionmark.diamond",
                    color: origin == .measured ? Theme.textSecondary : Theme.warning)
    }
}
