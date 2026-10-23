import Foundation
import Observation
import UserNotifications

enum AppTab: Hashable {
    case today, protocols, history, settings
}

/// Pedido para abrir a folha de confirmação de uma aplicação (toque na notificação, RF-NOT-03).
struct ApplicationRequest: Identifiable {
    let id = UUID()
    let compoundID: UUID
    let dayKey: String?
}

/// Aviso temporário com ação opcional de desfazer (RF-AGE-05).
struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let undo: (() -> Void)?
}

/// Estado global da interface.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    /// Relógio da interface, atualizado periodicamente para recalcular situações e projeções.
    var now = Date()
    var selectedTab: AppTab = .today
    var toast: Toast?
    var applicationRequest: ApplicationRequest?
    var showNotificationPrimer = false
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// Muda quando todos os dados são apagados, para recriar as pilhas de navegação.
    var dataEpoch = 0

    // Bloqueio (RF-DAD-05)
    var isLocked = false
    var backgroundedAt: Date?

    private var toastTask: Task<Void, Never>?

    func tick() {
        now = Date()
    }

    /// Mostra o aviso por 5 segundos.
    func showToast(_ message: String, undo: (() -> Void)? = nil) {
        let toast = Toast(message: message, undo: undo)
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, self?.toast?.id == toast.id else { return }
            self?.toast = nil
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    /// Mostra a explicação antes do pedido de permissão quando o primeiro lembrete é ativado (RF-NOT-02).
    func requestNotificationPrimerIfNeeded(remindersEnabled: Bool) {
        guard remindersEnabled, notificationStatus == .notDetermined else { return }
        Task {
            // Aguarda a folha anterior fechar antes de apresentar a próxima.
            try? await Task.sleep(for: .milliseconds(600))
            showNotificationPrimer = true
        }
    }
}
