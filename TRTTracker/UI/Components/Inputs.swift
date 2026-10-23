import SwiftUI
import TRTCore
import UIKit

/// Campo numérico com teclado decimal, aceitando vírgula (RF-UI-04), e erro junto ao campo.
struct DecimalField: View {
    let title: String
    @Binding var text: String
    let unit: String
    var prompt: String = ""
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AdaptiveStack {
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.spacing(1))
                HStack(spacing: 4) {
                    TextField(prompt, text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.rounded(.body, weight: .medium))
                        .monospacedDigit()
                        .frame(minWidth: 64)
                        .accessibilityLabel(Text(title))
                        .accessibilityValue(Text(text.isEmpty ? String(localized: "vazio") : "\(text) \(unit)"))
                    Text(unit)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            FieldError(message: error)
        }
    }
}

struct FieldError: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.critical)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Chips de Seg a Dom (RF-AGE-01).
struct WeekdayChips: View {
    @Binding var selection: Set<Weekday>
    var requiredCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: Theme.spacing(1))], spacing: Theme.spacing(1)) {
                ForEach(Weekday.mondayFirst, id: \.self) { day in
                    chip(day)
                }
            }
            if let requiredCount {
                let count = selection.count
                let ok = count == requiredCount
                Label(String(localized: "Selecione exatamente \(requiredCount) dias (\(count) selecionados)."),
                      systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(ok ? Theme.textSecondary : Theme.critical)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chip(_ day: Weekday) -> some View {
        let isOn = selection.contains(day)
        return Button {
            if isOn { selection.remove(day) } else { selection.insert(day) }
        } label: {
            Text(day.shortName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isOn ? Theme.background : Theme.textPrimary)
                .background(isOn ? Theme.accent : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(isOn ? Color.clear : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.fullName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Seletor de hora e minuto nativo, 24 h, com passo de 5 minutos (RF-NOT-01).
struct ReminderTimePicker: UIViewRepresentable {
    @Binding var hour: Int
    @Binding var minute: Int

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval = 5
        picker.locale = Theme.locale
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        if picker.date != date { picker.date = date }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: ReminderTimePicker

        init(_ parent: ReminderTimePicker) {
            self.parent = parent
        }

        @objc func changed(_ picker: UIDatePicker) {
            let c = Calendar.current.dateComponents([.hour, .minute], from: picker.date)
            parent.hour = c.hour ?? 0
            parent.minute = ((c.minute ?? 0) / 5) * 5
        }
    }
}

/// Linha com o seletor de horário.
struct ReminderTimeRow: View {
    let title: String
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            ReminderTimePicker(hour: $hour, minute: $minute)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title): \(Formatting.time(hour: hour, minute: minute))"))
    }
}

/// Data no formato brasileiro dd/mm/aaaa que abre o calendário nativo (RF-UI-04).
struct BRDateField: View {
    let title: String
    @Binding var date: Date
    var range: ClosedRange<Date>?
    var partialUpTo: Date?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1)) {
            Button {
                withMotion { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(Formatting.numericDate(date))
                        .font(.rounded(.body, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(isExpanded ? Theme.accent : Theme.textPrimary)
                        .padding(.horizontal, Theme.spacing(1.5))
                        .padding(.vertical, 6)
                        .background(Theme.border.opacity(0.6), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(Formatting.numericDate(date)))
            .accessibilityHint(Text("Toque para escolher a data"))

            if isExpanded {
                picker
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Theme.locale)
                    .tint(Theme.accent)
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        let binding = Binding<Date>(
            get: { date },
            set: { newValue in
                // Mantém o horário já escolhido ao trocar o dia.
                let cal = Calendar.current
                let time = cal.dateComponents([.hour, .minute], from: date)
                var day = cal.dateComponents([.year, .month, .day], from: newValue)
                day.hour = time.hour
                day.minute = time.minute
                date = cal.date(from: day) ?? newValue
            })
        if let range {
            DatePicker(title, selection: binding, in: range, displayedComponents: .date).labelsHidden()
        } else if let partialUpTo {
            DatePicker(title, selection: binding, in: ...partialUpTo, displayedComponents: .date).labelsHidden()
        } else {
            DatePicker(title, selection: binding, displayedComponents: .date).labelsHidden()
        }
    }
}

/// Botão "OK" acima do teclado numérico.
struct KeyboardDoneToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

extension View {
    func keyboardDoneButton() -> some View {
        modifier(KeyboardDoneToolbar())
    }
}
