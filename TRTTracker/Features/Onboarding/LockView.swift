import SwiftUI

/// Tela de bloqueio com Face ID / Touch ID / código (RF-DAD-05).
struct LockView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: Theme.spacing(3)) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("TRT-Tracker bloqueado")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Button {
                    Task { await unlock() }
                } label: {
                    Text("Desbloquear com \(LockManager.biometryName)")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isAuthenticating)
                .padding(.horizontal, Theme.spacing(4))
            }
        }
        .task {
            if scenePhase == .active { await unlock() }
        }
    }

    private func unlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        let success = await LockManager.authenticate(reason: String(localized: "Desbloquear o TRT-Tracker"))
        isAuthenticating = false
        if success {
            withMotion { appState.isLocked = false }
        }
    }
}

/// Cobertura exibida no seletor de apps.
struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
        }
    }
}
