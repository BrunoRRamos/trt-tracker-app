import SwiftUI
import TRTCore

/// Frequência, dias da semana e recontagem do "dia sim, dia não" (RF-AGE-01).
struct ScheduleEditor: View {
    @Binding var draft: ScheduleDraft
    let protocolStart: Date

    var body: some View {
        Picker("Frequência", selection: $draft.frequency) {
            ForEach(Frequency.allCases, id: \.self) { frequency in
                Text(frequency.title).tag(frequency)
            }
        }
        .onChange(of: draft.frequency) { _, newValue in
            // Ao trocar a frequência, os dias padrão da nova opção são pré-selecionados.
            draft.weekdays = newValue.defaultWeekdays
        }

        switch draft.frequency {
        case .threeTimesWeek, .twoTimesWeek:
            WeekdayChips(selection: $draft.weekdays, requiredCount: draft.frequency.requiredWeekdayCount)
                .padding(.vertical, 4)
        case .everyOtherDay:
            Text(draft.restartsCount
                 ? String(localized: "A cada 2 dias, contando a partir de \(Formatting.numericDate(draft.anchorDate)).")
                 : String(localized: "A cada 2 dias, contando a partir da data de início (\(Formatting.numericDate(protocolStart)))."))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Toggle("Reiniciar contagem a partir de uma data", isOn: $draft.restartsCount)
            if draft.restartsCount {
                BRDateField(title: String(localized: "Contar a partir de"), date: $draft.anchorDate)
            }
        case .daily:
            Text("Todos os dias da semana.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
