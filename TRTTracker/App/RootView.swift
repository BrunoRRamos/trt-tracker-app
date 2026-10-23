import Combine
import SwiftData
import SwiftUI

/// Barra de abas (RF-UI-01) com aviso de uso, bloqueio, avisos e abertura pela notificação.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferences: [AppPreferences]

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var prefs: AppPreferences? { preferences.first }
    private var lockEnabled: Bool { prefs?.biometricLockEnabled ?? false }

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $state.selectedTab) {
            TodayView()
                .id(appState.dataEpoch)
                .tabItem { Label("Hoje", systemImage: "sun.max") }
                .tag(AppTab.today)
            ProtocolsListView()
                .id(appState.dataEpoch)
                .tabItem { Label("Protocolos", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.protocols)
            HistoryView()
                .id(appState.dataEpoch)
                .tabItem { Label("Histórico", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)
            SettingsView()
                .id(appState.dataEpoch)
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .toolbarBackground(Theme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .overlay(alignment: .bottom) { toastOverlay }
        .sheet(item: $state.applicationRequest) { request in
            ApplicationRequestSheet(request: request)
        }
        .sheet(isPresented: $state.showNotificationPrimer) {
            NotificationPrimerView()
        }
        .fullScreenCover(isPresented: disclaimerBinding) {
            DisclaimerView(mode: .firstLaunch)
        }
        .overlay {
            if appState.isLocked {
                LockView()
                    .transition(.opacity)
            } else if lockEnabled && scenePhase != .active {
                // Oculta o conteúdo no seletor de apps enquanto o bloqueio estiver ativo (RF-DAD-05).
                PrivacyCoverView()
            }
        }
        .onReceive(clock) { _ in appState.tick() }
        .onChange(of: scenePhase) { _, phase in handle(phase) }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refresh() }
        .task {
            await NotificationScheduler.shared.refreshAuthorizationStatus()
            await NotificationScheduler.shared.reschedule()
        }
    }

    private var disclaimerBinding: Binding<Bool> {
        Binding(get: { prefs != nil && prefs?.disclaimerAcceptedAt == nil }, set: { _ in })
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = appState.toast {
            ToastView(toast: toast) { appState.dismissToast() }
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
        }
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .background:
            appState.backgroundedAt = Date()
            BackgroundRefresh.schedule()
            Persistence.applyFileProtection()
        case .active:
            if lockEnabled, let since = appState.backgroundedAt,
               Date().timeIntervalSince(since) >= LockManager.relockInterval {
                appState.isLocked = true
            }
            appState.backgroundedAt = nil
            refresh()
        default:
            break
        }
    }

    private func refresh() {
        appState.tick()
        Task { await NotificationScheduler.shared.reschedule() }
    }
}

/// Abre a folha de confirmação da aplicação tocada na notificação.
private struct ApplicationRequestSheet: View {
    let request: ApplicationRequest
    @Query private var compounds: [Compound]

    init(request: ApplicationRequest) {
        self.request = request
        let id = request.compoundID
        _compounds = Query(filter: #Predicate<Compound> { $0.id == id })
    }

    var body: some View {
        if let compound = compounds.first {
            ApplyView(compound: compound, dayKey: request.dayKey)
        } else {
            EmptyStateView(icon: "questionmark.circle", title: String(localized: "Aplicação não encontrada"),
                           message: String(localized: "O composto desta notificação não existe mais."))
                .sheetBackground()
        }
    }
}
