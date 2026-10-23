import SwiftUI
import TRTCore

// Textos de exibição dos tipos do domínio, no String Catalog.

extension Weekday {
    var shortName: String {
        switch self {
        case .monday: String(localized: "Seg")
        case .tuesday: String(localized: "Ter")
        case .wednesday: String(localized: "Qua")
        case .thursday: String(localized: "Qui")
        case .friday: String(localized: "Sex")
        case .saturday: String(localized: "Sáb")
        case .sunday: String(localized: "Dom")
        }
    }

    var fullName: String {
        switch self {
        case .monday: String(localized: "Segunda-feira")
        case .tuesday: String(localized: "Terça-feira")
        case .wednesday: String(localized: "Quarta-feira")
        case .thursday: String(localized: "Quinta-feira")
        case .friday: String(localized: "Sexta-feira")
        case .saturday: String(localized: "Sábado")
        case .sunday: String(localized: "Domingo")
        }
    }
}

extension Frequency {
    var title: String {
        switch self {
        case .daily: String(localized: "Todos os dias")
        case .everyOtherDay: String(localized: "Dia sim, dia não")
        case .threeTimesWeek: String(localized: "3x por semana")
        case .twoTimesWeek: String(localized: "2x por semana")
        }
    }
}

extension Schedule {
    /// "2x por semana · Seg, Qui"
    var summary: String {
        guard frequency.usesWeekdays else { return frequency.title }
        let days = weekdays.sorted().map(\.shortName).joined(separator: ", ")
        return "\(frequency.title) · \(days)"
    }
}

extension ProtocolStatus {
    var title: String {
        switch self {
        case .active: String(localized: "Ativo")
        case .scheduled: String(localized: "Agendado")
        case .ended: String(localized: "Encerrado")
        }
    }

    var sectionTitle: String {
        switch self {
        case .active: String(localized: "Ativos")
        case .scheduled: String(localized: "Agendados")
        case .ended: String(localized: "Encerrados")
        }
    }

    var icon: String {
        switch self {
        case .active: "play.circle.fill"
        case .scheduled: "calendar.badge.clock"
        case .ended: "checkmark.seal"
        }
    }

    var color: Color {
        switch self {
        case .active: Theme.accent
        case .scheduled: Theme.warning
        case .ended: Theme.textSecondary
        }
    }
}

extension OccurrenceStatus {
    var title: String {
        switch self {
        case .planned: String(localized: "Prevista")
        case .overdue: String(localized: "Atrasada")
        case .applied: String(localized: "Aplicada")
        case .skipped: String(localized: "Pulada")
        case .missed: String(localized: "Não registrada")
        }
    }

    var icon: String {
        switch self {
        case .planned: "clock"
        case .overdue: "exclamationmark.triangle.fill"
        case .applied: "checkmark.circle.fill"
        case .skipped: "forward.fill"
        case .missed: "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .planned: Theme.accent
        case .overdue: Theme.warning
        case .applied: Theme.success
        case .skipped: Theme.textSecondary
        case .missed: Theme.critical
        }
    }
}

extension NumberInputError {
    /// Mensagem junto ao campo.
    func message(min: String, max: String) -> String {
        switch self {
        case .empty: String(localized: "Campo obrigatório.")
        case .invalid: String(localized: "Digite um número válido.")
        case .belowMinimum: String(localized: "O mínimo é \(min).")
        case .aboveMaximum: String(localized: "O máximo é \(max).")
        case .step: String(localized: "Use passos de 0,1 ml.")
        }
    }
}

extension NameInputError {
    var message: String {
        switch self {
        case .empty: String(localized: "Informe um nome.")
        case .tooLong(let max): String(localized: "Use no máximo \(max) caracteres.")
        }
    }
}

enum Plural {
    static func vials(_ n: Int) -> String {
        n == 1 ? String(localized: "1 vial") : String(localized: "\(n) vials")
    }

    static func applications(_ n: Int) -> String {
        n == 1 ? String(localized: "1 aplicação") : String(localized: "\(n) aplicações")
    }

    static func days(_ n: Int) -> String {
        n == 1 ? String(localized: "1 dia") : String(localized: "\(n) dias")
    }

    static func compounds(_ n: Int) -> String {
        n == 1 ? String(localized: "1 composto") : String(localized: "\(n) compostos")
    }
}

extension String {
    /// "qui, 22 out" → "Qui, 22 out"
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

/// "hoje", "amanhã", "em 4 dias"
func relativeDays(from today: LocalDay, to day: LocalDay) -> String {
    let diff = today.days(to: day)
    switch diff {
    case ..<0: return String(localized: "há \(Plural.days(-diff))")
    case 0: return String(localized: "hoje")
    case 1: return String(localized: "amanhã")
    default: return String(localized: "em \(Plural.days(diff))")
    }
}
