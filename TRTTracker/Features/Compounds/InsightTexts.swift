import Foundation
import TRTCore

/// Frases das projeções nos formatos da especificação.
enum InsightText {
    /// "70% · 7,0 ml restantes"
    static func level(_ vial: Vial) -> String {
        "\(Formatting.percent(vial.percentRemaining)) · " + String(localized: "\(Formatting.milliliters(vial.remainingMicroliters)) restantes")
    }

    /// "Dura até qui, 13 nov · 4 aplicações restantes" (RF-VIA-06)
    static func duration(_ insights: CompoundInsights) -> String? {
        guard let vial = insights.currentVial, let projection = insights.currentProjection else { return nil }
        if insights.upcoming.isEmpty {
            return String(localized: "Sem aplicações previstas até o fim do protocolo")
        }
        if projection.coversAllUpcoming {
            let remaining = insights.applicationsRemaining(in: vial)
            return String(localized: "Dura até o fim do protocolo · \(Plural.applications(remaining)) restantes")
        }
        guard let last = projection.lastCovered else {
            return String(localized: "Volume insuficiente para a próxima aplicação")
        }
        return String(localized: "Dura até \(Formatting.weekdayDayMonth(last)) · \(Plural.applications(projection.coveredCount)) restantes")
    }

    /// "Próximo vial a partir de seg, 14 dez"
    static func nextVial(_ insights: CompoundInsights) -> String? {
        guard let next = insights.currentProjection?.firstNeedingNext else { return nil }
        return String(localized: "Próximo vial a partir de \(Formatting.weekdayDayMonth(next))")
    }

    /// "2 vials de 10 ml · 24 aplicações · 12,0 ml no total · sobra 8,0 ml" (RF-VIA-09)
    static func requirement(_ requirement: VialRequirement) -> String {
        let size = Formatting.milliliters(requirement.reference.volumeMicroliters, minFractionDigits: 0)
        return [
            String(localized: "\(Plural.vials(requirement.vialsNeeded)) de \(size)"),
            Plural.applications(requirement.applicationCount),
            String(localized: "\(Formatting.milliliters(requirement.totalMicroliters)) no total"),
            String(localized: "sobra \(Formatting.milliliters(requirement.leftoverMicroliters))")
        ].joined(separator: " · ")
    }

    /// "Vial 1, 55% restante, 5,5 ml restantes, dura até 13 de novembro" (RF-UI-05)
    static func vialAccessibility(compound: Compound, vial: Vial, insights: CompoundInsights?) -> String {
        var parts = [
            String(localized: "Vial \(compound.number(of: vial))"),
            String(localized: "\(Formatting.percent(vial.percentRemaining)) restante"),
            String(localized: "\(Formatting.milliliters(vial.remainingMicroliters)) restantes")
        ]
        if let insights, insights.currentVial?.id == vial.id, let last = insights.currentProjection?.lastCovered {
            parts.append(String(localized: "dura até \(Formatting.dayMonthLong(last))"))
        }
        return parts.joined(separator: ", ")
    }

    /// "0,5 ml · 50 UI"
    static func volume(_ microliters: Int) -> String {
        "\(Formatting.milliliters(microliters)) · \(Formatting.insulinUnits(microliters))"
    }
}
