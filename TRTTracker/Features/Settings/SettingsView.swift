import SwiftData
import SwiftUI
import UserNotifications

/// Ajustes: notificações, privacidade, aviso de uso e apagar dados.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var preferences: [AppPreferences]

    @State private var confirmEraseFirst = false
    @State private var confirmEraseSecond = false
    @State private var lockError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let prefs = preferences.first {
                    form(prefs)
                } else {
                    ProgressView()
                }
            }
            .screenBackground()
            .navigationTitle("Ajustes")
        }
    }

    private func form(_ prefs: AppPreferences) -> some View {
        @Bindable var prefs = prefs
        return Form {
            notificationsSection(prefs)

            Section {
                Toggle("Notificações discretas", isOn: $prefs.discreteNotifications)
                    .onChange(of: prefs.discreteNotifications) { _, _ in saveAndReschedule() }
            } footer: {
                Text("Oculta o nome do composto e a dose, exibindo apenas \"Lembrete de aplicação\" na tela bloqueada.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Picker("Lembrete de atraso", selection: $prefs.overdueReminderHours) {
                    Text("Desligado").tag(0)
                    Text("1 h").tag(1)
                    Text("2 h").tag(2)
                    Text("4 h").tag(4)
                }
                .onChange(of: prefs.overdueReminderHours) { _, _ in saveAndReschedule() }
                Stepper(value: $prefs.lowVialThreshold, in: 1...5) {
                    Text("Avisar com \(prefs.lowVialThreshold) aplicação(ões) restante(s) no vial")
                }
                .onChange(of: prefs.lowVialThreshold) { _, _ in saveAndReschedule() }
            } header: {
                Text("Alertas")
            } footer: {
                Text("Se a aplicação não for registrada nem pulada, um segundo lembrete é enviado após o intervalo escolhido. Também há aviso quando o estoque de um composto cobre menos de 7 dias.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle("Bloquear com \(LockManager.biometryName)", isOn: Binding(
                    get: { prefs.biometricLockEnabled },
                    set: { newValue in Task { await setLock(newValue, prefs: prefs) } }
                ))
                FieldError(message: lockError)
            } header: {
                Text("Privacidade")
            } footer: {
                Text("Exige autenticação ao abrir o app e ao voltar após 1 minuto em segundo plano. O conteúdo fica oculto no seletor de apps.")
            }
            .listRowBackground(Theme.surface)

            Section("Sobre") {
                NavigationLink("Aviso de uso") {
                    DisclaimerView(mode: .readOnly)
                }
                NavigationLink("Cinética dos ésteres") {
                    KineticsCatalogView()
                }
                Label("Dados apenas neste aparelho, sem conta e sem coleta.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    InfoRow(label: String(localized: "Versão"), value: version)
                }
            }
            .listRowBackground(Theme.surface)

            Section {
                Button("Apagar todos os dados", role: .destructive) { confirmEraseFirst = true }
            } footer: {
                Text("Apaga protocolos, compostos, vials, histórico e preferências, e cancela todas as notificações.")
            }
            .listRowBackground(Theme.surface)
        }
        .confirmationDialog("Apagar todos os dados?", isPresented: $confirmEraseFirst, titleVisibility: .visible) {
            Button("Continuar", role: .destructive) { confirmEraseSecond = true }
        } message: {
            Text("Todos os protocolos, vials e o histórico serão apagados deste aparelho.")
        }
        .alert("Tem certeza?", isPresented: $confirmEraseSecond) {
            Button("Apagar tudo", role: .destructive) {
                Haptics.warning()
                DataEraser.eraseAll(in: context)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta ação não pode ser desfeita.")
        }
    }

    @ViewBuilder
    private func notificationsSection(_ prefs: AppPreferences) -> some View {
        Section("Notificações") {
            switch appState.notificationStatus {
            case .authorized, .provisional, .ephemeral:
                Label("Permitidas", systemImage: "bell.badge.fill")
                    .foregroundStyle(Theme.success)
            case .denied:
                Label("Negadas", systemImage: "bell.slash.fill")
                    .foregroundStyle(Theme.warning)
                Button("Abrir ajustes de notificação") { NotificationScheduler.openSystemNotificationSettings() }
            default:
                Label("Ainda não ativadas", systemImage: "bell")
                    .foregroundStyle(Theme.textSecondary)
                Button("Ativar lembretes") { appState.showNotificationPrimer = true }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private func saveAndReschedule() {
        try? context.save()
        Task { await NotificationScheduler.shared.reschedule() }
    }

    /// Só ativa o bloqueio depois de uma autenticação bem-sucedida.
    private func setLock(_ enabled: Bool, prefs: AppPreferences) async {
        lockError = nil
        guard enabled else {
            prefs.biometricLockEnabled = false
            try? context.save()
            return
        }
        guard LockManager.isAvailable else {
            lockError = String(localized: "Configure um código ou biometria no aparelho para usar o bloqueio.")
            return
        }
        if await LockManager.authenticate(reason: String(localized: "Ativar o bloqueio do TRT-Tracker")) {
            prefs.biometricLockEnabled = true
            try? context.save()
        }
    }
}
