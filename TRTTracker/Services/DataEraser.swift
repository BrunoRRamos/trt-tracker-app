import Foundation
import SwiftData

/// Apaga todos os dados e cancela todas as notificações (RF-DAD-06).
@MainActor
enum DataEraser {
    static func eraseAll(in context: ModelContext) {
        deleteAll(TreatmentProtocol.self, in: context)
        deleteAll(DoseEvent.self, in: context)
        deleteAll(VialUsage.self, in: context)
        deleteAll(VialAdjustment.self, in: context)
        deleteAll(Vial.self, in: context)
        deleteAll(SnoozedReminder.self, in: context)
        deleteAll(Compound.self, in: context)
        deleteAll(AppPreferences.self, in: context)
        try? context.save()
        NotificationScheduler.shared.cancelAll()
        _ = AppPreferences.current(in: context)

        let state = AppState.shared
        state.isLocked = false
        state.dismissToast()
        state.applicationRequest = nil
        state.dataEpoch += 1
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for item in items {
            context.delete(item)
        }
    }
}
