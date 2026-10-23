import SwiftUI

/// Explica o motivo antes do pedido de permissão do sistema (RF-NOT-02).
struct NotificationPrimerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing(3)) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Ative os lembretes")
                    .font(.title.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Para avisar na hora de cada aplicação, o TRT-Tracker precisa da sua permissão para enviar notificações.")
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("As notificações são criadas no próprio aparelho, sem internet. Você pode marcar a aplicação ou adiar 30 min direto pela notificação, e ocultar nomes e doses em Ajustes.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Theme.spacing(1)) {
                    Button {
                        isRequesting = true
                        Task {
                            _ = await NotificationScheduler.shared.requestAuthorization()
                            isRequesting = false
                            dismiss()
                        }
                    } label: {
                        Text("Continuar")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isRequesting)

                    Button("Agora não") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, Theme.spacing(2))
            }
            .padding(Theme.spacing(3))
        }
        .sheetBackground()
        .presentationDetents([.large])
    }
}
