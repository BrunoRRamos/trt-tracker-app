import Foundation
import LocalAuthentication

/// Bloqueio com Face ID / Touch ID ou código do aparelho (RF-DAD-05).
@MainActor
enum LockManager {
    /// Tempo em segundo plano a partir do qual o app volta bloqueado.
    static let relockInterval: TimeInterval = 60

    enum Biometry {
        case faceID, touchID, opticID, passcode
    }

    static var biometry: Biometry {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    static var biometryName: String {
        switch biometry {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .passcode: String(localized: "código do aparelho")
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Autenticação biométrica com alternativa pelo código do aparelho.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancelar")
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
