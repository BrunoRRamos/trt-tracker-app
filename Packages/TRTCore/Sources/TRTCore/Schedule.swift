import Foundation

/// Dia da semana com os mesmos valores de `Calendar.weekday` (1 = domingo).
public enum Weekday: Int, CaseIterable, Codable, Sendable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// Ordem de exibição dos chips: Seg a Dom.
    public static let mondayFirst: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    public var mondayFirstIndex: Int { Weekday.mondayFirst.firstIndex(of: self)! }

    public var bit: Int { 1 << (rawValue - 1) }

    public static func mask(_ days: Set<Weekday>) -> Int {
        days.reduce(0) { $0 | $1.bit }
    }

    public static func set(fromMask mask: Int) -> Set<Weekday> {
        Set(allCases.filter { mask & $0.bit != 0 })
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.mondayFirstIndex < rhs.mondayFirstIndex
    }
}

/// Frequência da agenda (RF-AGE-01).
public enum Frequency: String, CaseIterable, Codable, Sendable {
    case daily
    case everyOtherDay
    case threeTimesWeek
    case twoTimesWeek

    /// Quantidade exata de dias que precisa ser escolhida, quando a frequência usa dias da semana.
    public var requiredWeekdayCount: Int? {
        switch self {
        case .daily, .everyOtherDay: nil
        case .threeTimesWeek: 3
        case .twoTimesWeek: 2
        }
    }

    public var usesWeekdays: Bool { requiredWeekdayCount != nil }

    public var defaultWeekdays: Set<Weekday> {
        switch self {
        case .daily: Set(Weekday.allCases)
        case .everyOtherDay: []
        case .threeTimesWeek: [.monday, .wednesday, .friday]
        case .twoTimesWeek: [.monday, .thursday]
        }
    }
}

/// Agenda de um composto: frequência, dias e, em "dia sim, dia não", a data de recontagem.
public struct Schedule: Equatable, Sendable {
    public var frequency: Frequency
    public var weekdays: Set<Weekday>
    /// Recontagem do "dia sim, dia não": a partir deste dia a paridade é contada dele (RF-AGE-01, P1).
    public var alternateAnchor: LocalDay?

    public init(frequency: Frequency, weekdays: Set<Weekday>? = nil, alternateAnchor: LocalDay? = nil) {
        self.frequency = frequency
        self.weekdays = weekdays ?? frequency.defaultWeekdays
        self.alternateAnchor = alternateAnchor
    }

    /// A agenda só é válida com a quantidade exata de dias exigida pela frequência.
    public var isValid: Bool {
        guard let required = frequency.requiredWeekdayCount else { return true }
        return weekdays.count == required
    }

    public func occurs(on day: LocalDay, protocolStart: LocalDay) -> Bool {
        switch frequency {
        case .daily:
            return true
        case .everyOtherDay:
            var base = protocolStart
            if let anchor = alternateAnchor, day >= anchor { base = anchor }
            let distance = base.days(to: day)
            return ((distance % 2) + 2) % 2 == 0
        case .threeTimesWeek, .twoTimesWeek:
            return weekdays.contains(day.weekday)
        }
    }

    /// Dias com aplicação prevista no intervalo fechado `[from, through]`, percorrendo a agenda dia a dia.
    public func days(from: LocalDay, through: LocalDay, protocolStart: LocalDay) -> [LocalDay] {
        guard from <= through, isValid else { return [] }
        var result: [LocalDay] = []
        var day = from
        while day <= through {
            if occurs(on: day, protocolStart: protocolStart) { result.append(day) }
            day = day.adding(days: 1)
        }
        return result
    }

    /// Nº de aplicações previstas entre o início e o fim do protocolo (RF-VIA-09).
    public func applicationCount(start: LocalDay, end: LocalDay) -> Int {
        days(from: start, through: end, protocolStart: start).count
    }
}
