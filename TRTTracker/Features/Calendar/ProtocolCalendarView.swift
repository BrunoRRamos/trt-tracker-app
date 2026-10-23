import SwiftData
import SwiftUI
import TRTCore

/// Visão mensal com marcação por dia; tocar em um dia mostra as aplicações e permite registrar ou pular (RF-AGE-08).
struct ProtocolCalendarView: View {
    let treatment: TreatmentProtocol

    @Environment(AppState.self) private var appState
    @State private var month: LocalDay = LocalDay(Date()).firstDayOfMonth
    @State private var selectedDay: LocalDay = LocalDay(Date())
    @State private var applyTarget: ApplyTarget?
    @State private var skipTarget: Occurrence?

    private var now: Date { appState.now }
    private var today: LocalDay { LocalDay(now) }

    private struct DayInfo {
        var occurrences: [Occurrence] = []
        var extras: [DoseEvent] = []

        func statuses(now: Date) -> [OccurrenceStatus] {
            var result = occurrences.map { $0.status(now: now) }
            if !extras.isEmpty { result.append(.applied) }
            return result
        }
    }

    /// Previstas (com registro ou pulo) e aplicações extras de cada dia do mês.
    private func monthInfo() -> [LocalDay: DayInfo] {
        let first = month.firstDayOfMonth
        let last = first.adding(days: first.numberOfDaysInMonth - 1)
        var info: [LocalDay: DayInfo] = [:]
        for compound in treatment.orderedCompounds {
            for occurrence in OccurrenceEngine.occurrences(for: compound, from: first, through: last, today: today) {
                info[occurrence.day, default: DayInfo()].occurrences.append(occurrence)
            }
            // Protocolos encerrados não geram previstas: mostram os registros e pulos existentes.
            for event in compound.events {
                let day = event.scheduledDay ?? LocalDay(event.performedAt)
                guard day >= first, day <= last else { continue }
                let alreadyShown = info[day]?.occurrences.contains { $0.event?.id == event.id } ?? false
                if !alreadyShown {
                    if event.isExtra || treatment.status(today: today) == .ended {
                        info[day, default: DayInfo()].extras.append(event)
                    }
                }
            }
        }
        return info
    }

    var body: some View {
        let info = monthInfo()
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing(2)) {
                monthHeader
                grid(info)
                legend
                dayDetail(info[selectedDay] ?? DayInfo())
            }
            .padding(Theme.spacing(2))
        }
        .screenBackground()
        .navigationTitle("Calendário")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if today < treatment.startDay {
                month = treatment.startDay.firstDayOfMonth
                selectedDay = treatment.startDay
            }
        }
        .sheet(item: $applyTarget) { target in
            ApplyView(compound: target.compound, dayKey: target.dayKey)
        }
        .sheet(item: $skipTarget) { occurrence in
            SkipView(occurrence: occurrence)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                withMotion { month = month.addingMonths(-1) }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("Mês anterior"))
            Spacer()
            Text(Formatting.monthYear(month))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                withMotion { month = month.addingMonths(1) }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("Próximo mês"))
        }
    }

    private func grid(_ info: [LocalDay: DayInfo]) -> some View {
        let first = month.firstDayOfMonth
        let leading = first.weekday.mondayFirstIndex
        let cells: [LocalDay?] = Array(repeating: nil, count: leading)
            + (0..<first.numberOfDaysInMonth).map { Optional(first.adding(days: $0)) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Weekday.mondayFirst, id: \.self) { day in
                Text(day.shortName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, info: info[day])
                } else {
                    Color.clear.frame(height: 48)
                }
            }
        }
        .card(padding: Theme.spacing(1))
    }

    private func dayCell(_ day: LocalDay, info: DayInfo?) -> some View {
        let statuses = info?.statuses(now: now) ?? []
        let marker = Self.dominant(statuses)
        let isSelected = day == selectedDay
        let inProtocol = day >= treatment.startDay && day <= treatment.endDay
        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(.rounded(.subheadline, weight: day == today ? .bold : .regular))
                    .foregroundStyle(inProtocol ? Theme.textPrimary : Theme.textSecondary)
                if let marker {
                    Image(systemName: marker.icon)
                        .font(.caption2)
                        .foregroundStyle(marker.color)
                } else {
                    Image(systemName: "circle").font(.caption2).hidden()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(isSelected ? Theme.accent.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(day == today ? Theme.accent : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel(day, statuses: statuses)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityLabel(_ day: LocalDay, statuses: [OccurrenceStatus]) -> String {
        let date = Formatting.dayMonthLong(day.date())
        guard !statuses.isEmpty else { return date }
        let summary = Dictionary(grouping: statuses, by: { $0 }).map { "\($0.value.count) \($0.key.title.lowercased())" }
        return "\(date): \(summary.sorted().joined(separator: ", "))"
    }

    /// Situação mais relevante do dia para a marcação.
    private static func dominant(_ statuses: [OccurrenceStatus]) -> OccurrenceStatus? {
        let priority: [OccurrenceStatus] = [.overdue, .missed, .planned, .skipped, .applied]
        if statuses.isEmpty { return nil }
        if statuses.allSatisfy({ $0 == .applied }) { return .applied }
        return priority.first { statuses.contains($0) }
    }

    private var legend: some View {
        let items: [OccurrenceStatus] = [.planned, .applied, .skipped, .overdue, .missed]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], spacing: Theme.spacing(1)) {
            ForEach(items, id: \.self) { status in
                Label(status.title, systemImage: status.icon)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Legenda do calendário"))
    }

    @ViewBuilder
    private func dayDetail(_ info: DayInfo) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            Text(Formatting.weekdayDayMonth(selectedDay).capitalizedFirst)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if info.occurrences.isEmpty && info.extras.isEmpty {
                EmptyStateView(icon: "calendar", title: String(localized: "Nenhuma aplicação neste dia"),
                               message: String(localized: "Você pode registrar uma aplicação extra, fora da agenda."),
                               actionTitle: treatment.status(today: today) == .ended ? nil : String(localized: "Registrar aplicação extra")) {
                    applyTarget = ApplyTarget(compound: treatment.orderedCompounds.first, dayKey: nil)
                }
            }
            ForEach(info.occurrences.sorted { $0.scheduledAt < $1.scheduledAt }) { occurrence in
                let status = occurrence.status(now: now)
                OccurrenceCard(occurrence: occurrence, now: now, highlightOverdue: status == .overdue,
                               onApply: { applyTarget = ApplyTarget(compound: occurrence.compound, dayKey: occurrence.day.key) },
                               onSkip: { skipTarget = occurrence })
            }
            ForEach(info.extras) { event in
                EventRow(event: event)
                    .card()
            }
        }
    }
}
