import Foundation

/// Formatação pt-BR dos valores do app (vírgula decimal, ponto de milhar, datas dd/mm/aaaa, 24 h).
public enum Formatting {
    public static let locale = Locale(identifier: "pt_BR")

    private static func numberFormatter(min: Int, max: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = min
        f.maximumFractionDigits = max
        f.roundingMode = .halfUp
        return f
    }

    private static let symbolsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        return f
    }()

    public static func decimal(_ value: Decimal, minFractionDigits: Int = 0, maxFractionDigits: Int = 2) -> String {
        numberFormatter(min: minFractionDigits, max: maxFractionDigits).string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// Volume em ml, por padrão com 1 a 2 casas: "7,0", "0,5", "0,25".
    public static func millilitersValue(_ microliters: Int, minFractionDigits: Int = 1, maxFractionDigits: Int = 2) -> String {
        decimal(Decimal(microliters) / 1000, minFractionDigits: minFractionDigits, maxFractionDigits: maxFractionDigits)
    }

    /// "7,0 ml"
    public static func milliliters(_ microliters: Int, minFractionDigits: Int = 1, maxFractionDigits: Int = 2) -> String {
        millilitersValue(microliters, minFractionDigits: minFractionDigits, maxFractionDigits: maxFractionDigits) + " ml"
    }

    public static func milligramsValue(_ micrograms: Int) -> String {
        decimal(Decimal(micrograms) / 1000, minFractionDigits: 0, maxFractionDigits: 3)
    }

    /// "100 mg", "2.400 mg", "0,25 mg"
    public static func milligrams(_ micrograms: Int) -> String {
        milligramsValue(micrograms) + " mg"
    }

    /// "50 UI" (seringa U-100)
    public static func insulinUnits(_ microliters: Int) -> String {
        decimal(VolumeMath.insulinUnits(microliters: microliters), minFractionDigits: 0, maxFractionDigits: 1) + " UI"
    }

    /// "70%" ou "<1%"
    public static func percent(_ value: PercentRemaining) -> String {
        switch value {
        case .whole(let v): "\(v)%"
        case .lessThanOne: "<1%"
        }
    }

    private static func stripDot(_ s: String) -> String {
        s.replacingOccurrences(of: ".", with: "").lowercased()
    }

    /// "qui, 10 dez"
    public static func weekdayDayMonth(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        let weekday = stripDot(symbolsFormatter.shortWeekdaySymbols[(c.weekday ?? 1) - 1])
        let month = stripDot(symbolsFormatter.shortMonthSymbols[(c.month ?? 1) - 1])
        return "\(weekday), \(c.day ?? 1) \(month)"
    }

    public static func weekdayDayMonth(_ day: LocalDay) -> String {
        weekdayDayMonth(day.date(calendar: gregorian), calendar: gregorian)
    }

    /// "10 de dezembro" (rótulos de VoiceOver)
    public static func dayMonthLong(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.day, .month], from: date)
        let month = symbolsFormatter.monthSymbols[(c.month ?? 1) - 1].lowercased()
        return "\(c.day ?? 1) de \(month)"
    }

    /// "outubro de 2026"
    public static func monthYear(_ day: LocalDay) -> String {
        let month = symbolsFormatter.standaloneMonthSymbols[day.month - 1]
        return "\(month.prefix(1).uppercased())\(month.dropFirst()) de \(day.year)"
    }

    /// "22/10/2026"
    public static func numericDate(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", c.day ?? 1, c.month ?? 1, c.year ?? 1970)
    }

    public static func numericDate(_ day: LocalDay) -> String {
        String(format: "%02d/%02d/%04d", day.day, day.month, day.year)
    }

    /// "09:05"
    public static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return time(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    public static func time(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Meia-vida: "14 h", "46,8 h" (abaixo de 2 dias) ou "5 dias", "33,9 dias".
    public static func halfLife(hours: Double) -> String {
        if hours < 48 {
            return decimal(Decimal(hours), minFractionDigits: 0, maxFractionDigits: 1) + " h"
        }
        let days = decimal(Decimal(hours / 24), minFractionDigits: 0, maxFractionDigits: 1)
        return days + " dias"
    }

    /// Duração: "6,5 h" (abaixo de 2 dias) ou "2,7 dias".
    public static func duration(hours: Double) -> String {
        halfLife(hours: hours)
    }

    /// "69%", "87,5%"
    public static func percentValue(_ value: Double) -> String {
        decimal(Decimal(value), minFractionDigits: 0, maxFractionDigits: 1) + "%"
    }

    /// Massa estimada em mg a partir de um Double: "138 mg", "0,8 mg".
    public static func milligrams(estimate value: Double) -> String {
        let digits = value >= 100 ? 0 : 1
        return decimal(Decimal(value), minFractionDigits: 0, maxFractionDigits: digits) + " mg"
    }

    /// "02/11/2026 – 24/01/2027"
    public static func period(start: LocalDay, end: LocalDay) -> String {
        "\(numericDate(start)) – \(numericDate(end))"
    }

    static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
