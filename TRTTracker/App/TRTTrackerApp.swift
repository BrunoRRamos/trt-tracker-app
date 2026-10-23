import SwiftData
import SwiftUI

@main
struct TRTTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

    init() {
        // O bloqueio começa ativo na abertura do app (RF-DAD-05).
        let prefs = AppPreferences.current(in: Persistence.container.mainContext)
        AppState.shared.isLocked = prefs.biometricLockEnabled
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(\.locale, Theme.locale)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(Persistence.container)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.schedule()
            await NotificationScheduler.shared.reschedule()
        }
    }
}
