import SwiftUI
import TRTCore

/// Vials mínimos, vials a comprar e projeção do estoque de um composto (RF-VIA-07 e 09).
struct StockInsightsView: View {
    let compound: Compound
    let insights: CompoundInsights

    /// Vial de referência informado na própria tela quando não há vial atual (RF-VIA-09).
    @State private var volumeText = ""
    @State private var concentrationText = ""

    private var manualReference: VialReference? {
        guard case .success(let volume) = Validation.vialVolume(volumeText),
              case .success(let concentration) = Validation.concentration(concentrationText) else { return nil }
        return VialReference(volumeMicroliters: volume, concentrationMicrogramsPerMl: concentration)
    }

    private var reference: VialReference? { insights.currentReference ?? manualReference }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            requirementSection
            if insights.status != .ended {
                stockSection
            }
        }
    }

    @ViewBuilder
    private var requirementSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1)) {
            Text("Vials para o protocolo")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            if insights.currentReference == nil {
                Text("Sem vial atual: informe um vial de referência para o cálculo.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                DecimalField(title: String(localized: "Volume do vial"), text: $volumeText, unit: "ml", prompt: "10")
                DecimalField(title: String(localized: "Concentração"), text: $concentrationText, unit: "mg/ml", prompt: "200")
            }
            if let requirement = insights.requirement(reference: reference) {
                Text(InsightText.requirement(requirement))
                    .font(.rounded(.body, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .motion(requirement)
                if insights.status == .active, let toBuy = insights.vialsToBuy(reference: reference) {
                    Text(toBuy == 0
                         ? String(localized: "Nenhum vial a comprar até o fim")
                         : String(localized: "Faltam comprar: \(Plural.vials(toBuy))"))
                        .font(.subheadline)
                        .foregroundStyle(toBuy == 0 ? Theme.textSecondary : Theme.warning)
                }
            }
        }
    }

    @ViewBuilder
    private var stockSection: some View {
        let stock = insights.stock
        if compound.activeVials.isEmpty {
            NoticeView(tone: .warning, title: String(localized: "Sem vial cadastrado"),
                       message: String(localized: "As aplicações podem ser registradas sem descontar estoque."))
        } else if stock.isSufficient {
            NoticeView(tone: .success, title: String(localized: "Estoque suficiente até o fim do protocolo"),
                       message: String(localized: "Vai sobrar \(Formatting.milliliters(stock.leftoverMicroliters))."))
        } else if let shortage = stock.firstShortage {
            NoticeView(tone: .critical, title: String(localized: "Estoque insuficiente"), message: shortageMessage(shortage))
        }
    }

    private func shortageMessage(_ shortage: Date) -> String {
        var lines = [String(localized: "Acaba em \(Formatting.weekdayDayMonth(shortage)), \(Plural.days(insights.shortageDaysBeforeEnd ?? 0)) antes do fim.")]
        if let missing = insights.shortageMicroliters(reference: reference) {
            lines.append(String(localized: "Faltam \(Formatting.milliliters(missing))."))
        }
        if let toBuy = insights.vialsToBuy(reference: reference), toBuy > 0 {
            lines.append(String(localized: "Compre \(Plural.vials(toBuy))."))
        }
        return lines.joined(separator: " ")
    }
}
