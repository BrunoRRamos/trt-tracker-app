import Foundation
import SwiftData

/// Versão 1 do modelo persistido (RF-DAD-02). Congelada: mantida apenas para a migração para a V2.
/// Não altere estas classes; mudanças de modelo entram numa nova versão em `TRTMigrationPlan`.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [TreatmentProtocol.self, Compound.self, Vial.self, VialUsage.self,
         VialAdjustment.self, DoseEvent.self, SnoozedReminder.self, AppPreferences.self]
    }

    @Model
    final class TreatmentProtocol {
        var id: UUID = UUID()
        var name: String = ""
        /// Datas como dias civis `aaaa-mm-dd`, independentes de fuso.
        var startDayKey: String = ""
        var endDayKey: String = ""
        var endedManually: Bool = false
        /// Agenda padrão dos compostos.
        var frequencyRaw: String = "twoTimesWeek"
        var weekdayMask: Int = 0
        var alternateAnchorKey: String?
        /// Horário padrão do lembrete.
        var reminderHour: Int = 9
        var reminderMinute: Int = 0
        var createdAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \Compound.treatmentProtocol)
        var compounds: [Compound] = []

        init(name: String, startDayKey: String, endDayKey: String) {
            self.id = UUID()
            self.name = name
            self.startDayKey = startDayKey
            self.endDayKey = endDayKey
            self.createdAt = Date()
        }
    }

    @Model
    final class Compound {
        var id: UUID = UUID()
        var name: String = ""
        var doseMicrograms: Int = 0
        var notes: String = ""
        var sortIndex: Int = 0
        var createdAt: Date = Date()

        /// Quando falso, usa a agenda própria abaixo.
        var usesProtocolSchedule: Bool = true
        var frequencyRaw: String = "twoTimesWeek"
        var weekdayMask: Int = 0
        var alternateAnchorKey: String?

        var reminderEnabled: Bool = true
        var usesCustomReminderTime: Bool = false
        var reminderHour: Int = 9
        var reminderMinute: Int = 0

        /// Controle do alerta de estoque (RF-NOT-06) para não repetir a mesma notificação.
        var lowStockAlertSent: Bool = false

        var treatmentProtocol: TreatmentProtocol?

        @Relationship(deleteRule: .cascade, inverse: \Vial.compound)
        var vials: [Vial] = []

        @Relationship(deleteRule: .cascade, inverse: \DoseEvent.compound)
        var events: [DoseEvent] = []

        @Relationship(deleteRule: .cascade, inverse: \SnoozedReminder.compound)
        var snoozes: [SnoozedReminder] = []

        init(name: String, doseMicrograms: Int) {
            self.id = UUID()
            self.name = name
            self.doseMicrograms = doseMicrograms
            self.createdAt = Date()
        }
    }

    @Model
    final class Vial {
        var id: UUID = UUID()
        var nickname: String = ""
        var totalMicroliters: Int = 0
        var concentrationMicrogramsPerMl: Int = 0
        /// Volume no cadastro ("Volume restante", igual ao total por padrão).
        var initialMicroliters: Int = 0
        var openedAt: Date?
        var lot: String = ""
        var expiresAt: Date?
        /// Posição na fila de estoque.
        var queueIndex: Int = 0
        var isArchived: Bool = false
        var createdAt: Date = Date()
        /// Controle do alerta de vial acabando (RF-NOT-06).
        var lowAlertSent: Bool = false

        var compound: Compound?

        @Relationship(deleteRule: .cascade, inverse: \VialUsage.vial)
        var usages: [VialUsage] = []

        @Relationship(deleteRule: .cascade, inverse: \VialAdjustment.vial)
        var adjustments: [VialAdjustment] = []

        init(totalMicroliters: Int, concentrationMicrogramsPerMl: Int, initialMicroliters: Int) {
            self.id = UUID()
            self.totalMicroliters = totalMicroliters
            self.concentrationMicrogramsPerMl = concentrationMicrogramsPerMl
            self.initialMicroliters = initialMicroliters
            self.createdAt = Date()
        }
    }

    /// Volume descontado de um vial por uma aplicação registrada.
    @Model
    final class VialUsage {
        var microliters: Int = 0
        /// Ordem da parte dentro da aplicação (0 = vial escolhido, 1 = complemento do próximo).
        var order: Int = 0
        var vial: Vial?
        var event: DoseEvent?

        init(microliters: Int, order: Int) {
            self.microliters = microliters
            self.order = order
        }
    }

    /// Correção manual do nível do vial (RF-VIA-05).
    @Model
    final class VialAdjustment {
        var id: UUID = UUID()
        var date: Date = Date()
        var beforeMicroliters: Int = 0
        var afterMicroliters: Int = 0
        var note: String = ""
        var vial: Vial?

        init(beforeMicroliters: Int, afterMicroliters: Int, note: String) {
            self.id = UUID()
            self.date = Date()
            self.beforeMicroliters = beforeMicroliters
            self.afterMicroliters = afterMicroliters
            self.note = note
        }
    }

    /// Aplicação registrada ou pulada.
    @Model
    final class DoseEvent {
        var id: UUID = UUID()
        /// "applied" ou "skipped".
        var kindRaw: String = "applied"
        /// Dia da aplicação prevista vinculada; nil = aplicação extra, fora da agenda.
        var scheduledDayKey: String?
        /// Data e hora da aplicação (ou de quando foi marcada como pulada).
        var performedAt: Date = Date()
        var doseMicrograms: Int = 0
        /// Observação da aplicação ou motivo do pulo.
        var note: String = ""
        var createdAt: Date = Date()

        var compound: Compound?

        @Relationship(deleteRule: .cascade, inverse: \VialUsage.event)
        var usages: [VialUsage] = []

        init(kindRaw: String, scheduledDayKey: String?, performedAt: Date, doseMicrograms: Int, note: String) {
            self.id = UUID()
            self.kindRaw = kindRaw
            self.scheduledDayKey = scheduledDayKey
            self.performedAt = performedAt
            self.doseMicrograms = doseMicrograms
            self.note = note
            self.createdAt = Date()
        }
    }

    /// Lembrete adiado em 30 min pela ação da notificação.
    @Model
    final class SnoozedReminder {
        var id: UUID = UUID()
        var scheduledDayKey: String = ""
        var fireAt: Date = Date()
        var compound: Compound?

        init(scheduledDayKey: String, fireAt: Date) {
            self.id = UUID()
            self.scheduledDayKey = scheduledDayKey
            self.fireAt = fireAt
        }
    }

    /// Preferências do app (registro único).
    @Model
    final class AppPreferences {
        var disclaimerAcceptedAt: Date?
        var discreteNotifications: Bool = false
        /// Lembrete de atraso: 0 = desligado, 1, 2 (padrão) ou 4 horas.
        var overdueReminderHours: Int = 2
        /// Alerta quando o vial atual tiver este nº de aplicações restantes ou menos (1 a 5).
        var lowVialThreshold: Int = 2
        var biometricLockEnabled: Bool = false

        init() {}
    }
}
