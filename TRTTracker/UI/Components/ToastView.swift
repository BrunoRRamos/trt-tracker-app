import SwiftUI

/// Aviso inferior com "Desfazer", visível por 5 segundos (RF-AGE-05).
struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacing(2)) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
                .accessibilityHidden(true)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let undo = toast.undo {
                Button("Desfazer") {
                    undo()
                    onDismiss()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, Theme.spacing(2))
        .padding(.vertical, Theme.spacing(1))
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, Theme.spacing(2))
        .accessibilityElement(children: .contain)
    }
}
