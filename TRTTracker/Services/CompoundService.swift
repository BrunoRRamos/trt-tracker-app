import Foundation
import SwiftData

/// Exclusão de compostos.
@MainActor
enum CompoundService {
    /// O protocolo precisa de pelo menos um composto (RF-PRO-01).
    static func canDelete(_ compound: Compound) -> Bool {
        (compound.treatmentProtocol?.compounds.count ?? 0) > 1
    }

    /// Exclui o composto com seus vials, histórico e adiamentos, e cancela as notificações dele.
    static func delete(_ compound: Compound, in context: ModelContext) {
        let ids = [compound.id] + compound.vials.map(\.id)
        compound.treatmentProtocol = nil
        context.delete(compound)
        try? context.save()
        Task {
            await NotificationScheduler.shared.removeNotifications(mentioning: ids)
            await NotificationScheduler.shared.reschedule()
        }
    }
}
