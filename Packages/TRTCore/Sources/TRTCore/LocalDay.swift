import Foundation

/// Dia civil (ano/mês/dia), independente de fuso horário.
///
/// É a chave estável de uma aplicação prevista: o horário do lembrete pode mudar e o
/// aparelho pode trocar de fuso, mas o dia da agenda continua o mesmo.
/// Internamente usa o número do dia juliano, o que torna a aritmética de dias exata.
public struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let julianDay: Int

    public init(julianDay: Int) {
        self.julianDay = julianDay
    }

    public init(year: Int, month: Int, day: Int) {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        julianDay = day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    /// Dia civil de `date` no calendário (e fuso) informado.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Lê uma chave no formato `aaaa-mm-dd`.
    public init?(key: String) {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public static func today(now: Date = Date(), calendar: Calendar = .current) -> LocalDay {
        LocalDay(now, calendar: calendar)
    }

    public var components: (year: Int, month: Int, day: Int) {
        let a = julianDay + 32044
        let b = (4 * a + 3) / 146097
        let c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        let day = e - (153 * m + 2) / 5 + 1
        let month = m + 3 - 12 * (m / 10)
        let year = 100 * b + d - 4800 + m / 10
        return (year, month, day)
    }

    public var year: Int { components.year }
    public var month: Int { components.month }
    public var day: Int { components.day }

    /// Chave persistida, `aaaa-mm-dd`.
    public var key: String {
        let c = components
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }

    public var weekday: Weekday {
        // JDN 0 cai numa segunda-feira; (jdn + 1) % 7 dá 0 = domingo.
        Weekday(rawValue: (julianDay + 1) % 7 + 1)!
    }

    public func adding(days: Int) -> LocalDay {
        LocalDay(julianDay: julianDay + days)
    }

    /// Dias de `self` até `other` (positivo se `other` for posterior).
    public func days(to other: LocalDay) -> Int {
        other.julianDay - julianDay
    }

    /// Instante local deste dia no horário informado.
    public func date(hour: Int = 0, minute: Int = 0, calendar: Calendar = .current) -> Date {
        let c = components
        let dc = DateComponents(year: c.year, month: c.month, day: c.day, hour: hour, minute: minute)
        return calendar.date(from: dc) ?? Date(timeIntervalSince1970: 0)
    }

    public var firstDayOfMonth: LocalDay {
        LocalDay(year: year, month: month, day: 1)
    }

    public func addingMonths(_ months: Int) -> LocalDay {
        let c = components
        var total = c.year * 12 + (c.month - 1) + months
        if total < 0 { total = 0 }
        return LocalDay(year: total / 12, month: total % 12 + 1, day: 1)
    }

    public var numberOfDaysInMonth: Int {
        firstDayOfMonth.days(to: addingMonths(1))
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        lhs.julianDay < rhs.julianDay
    }

    public var description: String { key }
}
