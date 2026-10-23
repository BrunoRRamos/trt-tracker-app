import Foundation
import SwiftData
import TRTCore
import UIKit
import UserNotifications

/// Lembretes locais em janela móvel (RF-NOT-01 a 07).
///
/// O iOS mantém no máximo 64 notificações pendentes por app; o app agenda até 60 notificações
/// não repetitivas, priorizando as mais próximas, e reagenda ao abrir, ao voltar ao primeiro plano,
/// após qualquer alteração e na atualização em segundo plano.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    static let maxPending = 60

    enum Identifier {
        static let applicationCategory = "APPLICATION"
        static let alertCategory = "ALERT"
        static let markAppliedAction = "MARK_APPLIED"
        static let snoozeAction = "SNOOZE_30"
        static let compoundKey = "compoundID"
        static let dayKey = "dayKey"
        static let kindKey = "kind"
    }

    private enum Kind: String {
        case main = "app"
        case late = "late"
        case snooze = "snooze"
    }

    private struct Candidate {
        let kind: Kind
        let occurrence: Occurrence
        let fireDate: Date
    }

    private let center = UNUserNotificationCenter.current()
    private var isRunning = false
    private var needsAnotherRun = false

    static func registerCategories() {
        let applied = UNNotificationAction(identifier: Identifier.markAppliedAction,
                                           title: String(localized: "Marcar como aplicada"),
                                           options: [.authenticationRequired])
        let snooze = UNNotificationAction(identifier: Identifier.snoozeAction,
                                          title: String(localized: "Adiar 30 min"), options: [])
        let application = UNNotificationCategory(identifier: Identifier.applicationCategory,
                                                 actions: [applied, snooze], intentIdentifiers: [],
                                                 hiddenPreviewsBodyPlaceholder: String(localized: "Lembrete de aplicação"),
                                                 options: [])
        let alert = UNNotificationCategory(identifier: Identifier.alertCategory, actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([application, alert])
    }

    // MARK: Permissão (RF-NOT-02)

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        AppState.shared.notificationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        await reschedule()
        return granted
    }

    static func openSystemNotificationSettings() {
        let urlString: String
        if #available(iOS 16.0, *) {
            urlString = UIApplication.openNotificationSettingsURLString
        } else {
            urlString = UIApplication.openSettingsURLString
        }
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Reagendamento (RF-NOT-04)

    func reschedule() async {
        if isRunning {
            needsAnotherRun = true
            return
        }
        isRunning = true
        repeat {
            needsAnotherRun = false
            await performReschedule()
        } while needsAnotherRun
        isRunning = false
    }

    private func performReschedule() async {
        let settings = await center.notificationSettings()
        AppState.shared.notificationStatus = settings.authorizationStatus

        let pending = await center.pendingNotificationRequests()
        let managed = pending.map(\.identifier).filter { id in
            [Kind.main, .late, .snooze].contains { id.hasPrefix($0.rawValue + ".") }
        }
        center.removePendingNotificationRequests(withIdentifiers: managed)

        let context = Persistence.container.mainContext
        let prefs = AppPreferences.current(in: context)
        let protocols = (try? context.fetch(FetchDescriptor<TreatmentProtocol>())) ?? []
        let now = Date()
        let today = LocalDay(now)

        var candidates: [Candidate] = []
        for treatment in protocols where treatment.status(today: today) != .ended {
            for compound in treatment.compounds {
                candidates += makeCandidates(for: compound, treatment: treatment, prefs: prefs, now: now, today: today, context: context)
            }
        }
        try? context.save()

        guard isAllowed(settings.authorizationStatus) else { return }

        candidates.sort { $0.fireDate < $1.fireDate }
        let truncated = candidates.count > Self.maxPending
        let selected = Array(candidates.prefix(Self.maxPending))
        for (index, candidate) in selected.enumerated() {
            let isWindowEnd = truncated && index == selected.count - 1
            let request = makeRequest(candidate, discrete: prefs.discreteNotifications, windowEnd: isWindowEnd)
            try? await center.add(request)
        }

        evaluateAlerts(protocols: protocols, prefs: prefs, now: now, today: today)
        try? context.save()
    }

    private func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    private func makeCandidates(for compound: Compound, treatment: TreatmentProtocol, prefs: AppPreferences,
                                now: Date, today: LocalDay, context: ModelContext) -> [Candidate] {
        let resolved = compound.eventsByDayKey
        // Adiamentos vencidos ou de aplicações já resolvidas são descartados.
        for snooze in compound.snoozes where snooze.fireAt <= now || resolved[snooze.scheduledDayKey] != nil {
            snooze.compound = nil
            context.delete(snooze)
        }
        guard compound.reminderEnabled else { return [] }

        let lateInterval = TimeInterval(prefs.overdueReminderHours * 3600)
        let endDay = treatment.endDay
        var result: [Candidate] = []
        let occurrences = OccurrenceEngine.occurrences(for: compound, from: today.adding(days: -1), through: endDay, today: today)
        for occurrence in occurrences where occurrence.event == nil {
            if occurrence.scheduledAt > now {
                result.append(Candidate(kind: .main, occurrence: occurrence, fireDate: occurrence.scheduledAt))
            }
            if lateInterval > 0 {
                let fire = occurrence.scheduledAt.addingTimeInterval(lateInterval)
                if fire > now, LocalDay(fire) <= endDay {
                    result.append(Candidate(kind: .late, occurrence: occurrence, fireDate: fire))
                }
            }
            if result.count >= Self.maxPending { break }
        }
        for snooze in compound.snoozes where snooze.fireAt > now && resolved[snooze.scheduledDayKey] == nil {
            guard let occurrence = OccurrenceEngine.occurrence(for: compound, dayKey: snooze.scheduledDayKey, now: now),
                  LocalDay(snooze.fireAt) <= endDay else { continue }
            result.append(Candidate(kind: .snooze, occurrence: occurrence, fireDate: snooze.fireAt))
        }
        return result
    }

    private static func identifier(_ kind: String, compoundID: UUID, dayKey: String) -> String {
        "\(kind).\(compoundID.uuidString).\(dayKey)"
    }

    private func makeRequest(_ candidate: Candidate, discrete: Bool, windowEnd: Bool) -> UNNotificationRequest {
        let compound = candidate.occurrence.compound
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Identifier.applicationCategory
        content.threadIdentifier = compound.treatmentProtocol?.id.uuidString ?? compound.id.uuidString
        content.sound = .default
        content.userInfo = [
            Identifier.compoundKey: compound.id.uuidString,
            Identifier.dayKey: candidate.occurrence.day.key,
            Identifier.kindKey: candidate.kind.rawValue
        ]

        var body: String
        if discrete {
            content.title = String(localized: "Lembrete de aplicação")
            body = ""
        } else {
            content.title = candidate.kind == .late ? String(localized: "Aplicação atrasada") : String(localized: "Hora da aplicação")
            body = Self.doseDescription(for: compound)
        }
        if windowEnd {
            let keepAlive = String(localized: "Abra o app para manter os lembretes ativos.")
            body = body.isEmpty ? keepAlive : body + "\n" + keepAlive
        }
        content.body = body

        // Componentes sem fuso: o lembrete dispara na hora local do aparelho, mesmo após mudança de fuso (RF-NOT-01).
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: candidate.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = Self.identifier(candidate.kind.rawValue, compoundID: compound.id, dayKey: candidate.occurrence.day.key)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// "Cipionato de testosterona · 100 mg · 0,5 ml (50 UI)"
    static func doseDescription(for compound: Compound) -> String {
        var parts = [compound.name, Formatting.milligrams(compound.doseMicrograms)]
        if let vial = compound.currentVial {
            let ml = compound.perApplicationMicroliters(for: vial)
            parts.append("\(Formatting.milliliters(ml)) (\(Formatting.insulinUnits(ml)))")
        }
        return parts.joined(separator: " · ")
    }

    /// Remove da Central de Notificações os avisos de uma aplicação já resolvida.
    func removeDelivered(compound: Compound, dayKey: String?) {
        guard let dayKey else { return }
        let ids = [Kind.main, .late, .snooze].map { Self.identifier($0.rawValue, compoundID: compound.id, dayKey: dayKey) }
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Remove notificações pendentes e entregues cujo identificador cita algum dos ids (composto ou vial excluído).
    func removeNotifications(mentioning ids: [UUID]) async {
        let keys = ids.map(\.uuidString)
        let matches: (String) -> Bool = { identifier in keys.contains { identifier.contains($0) } }
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter(matches)
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter(matches)
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: Alertas de vial e estoque (RF-NOT-06)

    private func evaluateAlerts(protocols: [TreatmentProtocol], prefs: AppPreferences, now: Date, today: LocalDay) {
        let threshold = min(5, max(1, prefs.lowVialThreshold))
        for treatment in protocols where treatment.status(today: today) != .ended {
            for compound in treatment.compounds {
                if let vial = compound.currentVial {
                    let per = compound.perApplicationMicroliters(for: vial)
                    let remaining = VolumeMath.applicationsRemaining(remainingMicroliters: vial.remainingMicroliters, perApplicationMicroliters: per)
                    if per > 0, remaining <= threshold {
                        if !vial.lowAlertSent {
                            vial.lowAlertSent = true
                            let body = prefs.discreteNotifications
                                ? String(localized: "Um vial está perto do fim.")
                                : String(localized: "\(compound.name): \(remaining) aplicação(ões) restante(s) no vial atual.")
                            postAlert(id: "vial.\(vial.id.uuidString)", title: String(localized: "Vial acabando"), body: body, compound: compound)
                        }
                    } else if vial.lowAlertSent {
                        vial.lowAlertSent = false
                    }
                }

                guard !compound.vials.isEmpty else { continue }
                let insights = CompoundInsights(compound: compound, now: now)
                let coversLessThanAWeek: Bool
                if let shortage = insights.stock.firstShortage {
                    coversLessThanAWeek = shortage.timeIntervalSince(now) < 7 * 24 * 3600
                } else {
                    coversLessThanAWeek = false
                }
                if coversLessThanAWeek {
                    if !compound.lowStockAlertSent {
                        compound.lowStockAlertSent = true
                        let body = prefs.discreteNotifications
                            ? String(localized: "O estoque de um composto cobre menos de 7 dias.")
                            : String(localized: "\(compound.name): o estoque cobre menos de 7 dias.")
                        postAlert(id: "stock.\(compound.id.uuidString)", title: String(localized: "Estoque baixo"), body: body, compound: compound)
                    }
                } else if compound.lowStockAlertSent {
                    compound.lowStockAlertSent = false
                }
            }
        }
    }

    private func postAlert(id: String, title: String, body: String, compound: Compound) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Identifier.alertCategory
        content.threadIdentifier = compound.treatmentProtocol?.id.uuidString ?? compound.id.uuidString
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
