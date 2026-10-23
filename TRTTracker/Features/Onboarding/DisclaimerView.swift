import SwiftData
import SwiftUI

/// Aviso de uso no primeiro acesso, também disponível em Ajustes (RF-DAD-04).
struct DisclaimerView: View {
    enum Mode { case firstLaunch, readOnly }

    let mode: Mode
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing(3)) {
                Image(systemName: "cross.case")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Antes de começar")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.textPrimary)
                VStack(alignment: .leading, spacing: Theme.spacing(2)) {
                    point(icon: "square.and.pencil",
                          text: String(localized: "O TRT-Tracker é uma ferramenta de registro e lembrete das suas aplicações."))
                    point(icon: "person.fill.questionmark",
                          text: String(localized: "As doses, os compostos e os protocolos são informados por você. O app não sugere nem ajusta doses."))
                    point(icon: "chart.xyaxis.line",
                          text: String(localized: "Os gráficos de liberação e de perfil são estimativas teóricas e normalizadas, feitas pela meia-vida de uma tabela de referência. Não indicam concentração no sangue e não substituem exames."))
                    point(icon: "stethoscope",
                          text: String(localized: "O app não substitui orientação médica. Siga sempre a prescrição do seu médico."))
                    point(icon: "lock.iphone",
                          text: String(localized: "Seus dados ficam apenas neste aparelho. Não há conta, servidor nem coleta de dados."))
                }
                if mode == .firstLaunch {
                    Button("Entendi e aceito") {
                        let prefs = AppPreferences.current(in: context)
                        prefs.disclaimerAcceptedAt = Date()
                        try? context.save()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, Theme.spacing(2))
                }
            }
            .padding(Theme.spacing(3))
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(mode == .readOnly ? String(localized: "Aviso de uso") : "")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(mode == .firstLaunch)
    }

    private func point(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(2)) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
