import Foundation
import SwiftData
import UserNotifications

/// Trata as ações das notificações (RF-NOT-03).
@MainActor
enum NotificationResponder {
    static func handle(actionIdentifier: String, userInfo: [AnyHashable: Any]) async {
        typealias ID = NotificationScheduler.Identifier
        guard let idString = userInfo[ID.compoundKey] as? String, let compoundID = UUID(uuidString: idString) else { return }
        let dayKey = userInfo[ID.dayKey] as? String
        let context = Persistence.container.mainContext
        let descriptor = FetchDescriptor<Compound>(predicate: #Predicate { $0.id == compoundID })
        guard let compound = try? context.fetch(descriptor).first else { return }

        switch actionIdentifier {
        case ID.markAppliedAction:
            // Registra com os valores padrão, sem abrir o app.
            if let dayKey, compound.eventsByDayKey[dayKey] != nil { break }
            DoseService.register(compound: compound, doseMicrograms: compound.doseMicrograms, performedAt: Date(),
                                 vial: compound.currentVial, dayKey: dayKey, note: "", in: context)
        case ID.snoozeAction:
            guard let dayKey else { break }
            let snooze = SnoozedReminder(scheduledDayKey: dayKey, fireAt: Date().addingTimeInterval(30 * 60))
            context.insert(snooze)
            snooze.compound = compound
            try? context.save()
        case UNNotificationDefaultActionIdentifier:
            // Abre o app na folha de confirmação daquela aplicação.
            if userInfo[ID.kindKey] != nil {
                AppState.shared.selectedTab = .today
                AppState.shared.applicationRequest = ApplicationRequest(compoundID: compoundID, dayKey: dayKey)
            }
        default:
            break
        }
        await NotificationScheduler.shared.reschedule()
    }
}
