import SwiftUI
import TRTCore

/// Item de aplicação prevista: composto, protocolo, horário, dose, volume, vial e situação (RF-AGE-04).
struct OccurrenceCard: View {
    let occurrence: Occurrence
    let now: Date
    var highlightOverdue = false
    var showDate = false
    let onApply: () -> Void
    let onSkip: () -> Void

    private var compound: Compound { occurrence.compound }
    private var status: OccurrenceStatus { occurrence.status(now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            header
            details
            vialLine
            if let event = occurrence.event {
                resolution(event)
            }
            if status.isPending || status == .missed {
                actions
            }
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(highlightOverdue ? Theme.warning : Color.clear, lineWidth: 1.5)
        )
        .motion(status)
    }

    private var header: some View {
        AdaptiveStack(spacing: Theme.spacing(1)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(compound.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(compound.treatmentProtocol?.name ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            StatusBadge(status)
        }
    }

    private var details: some View {
        AdaptiveStack(spacing: Theme.spacing(2)) {
            metric(title: showDate ? Formatting.weekdayDayMonth(occurrence.day) : String(localized: "Horário"),
                   value: Formatting.time(occurrence.scheduledAt))
            metric(title: String(localized: "Dose"), value: Formatting.milligrams(compound.doseMicrograms))
            if let vial = compound.currentVial {
                let ml = compound.perApplicationMicroliters(for: vial)
                metric(title: String(localized: "Volume"), value: Formatting.milliliters(ml),
                       caption: Formatting.insulinUnits(ml))
            }
        }
    }

    private func metric(title: String, value: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.rounded(.title3, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if let caption {
                    Text(caption)
                        .font(.rounded(.caption, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var vialLine: some View {
        if let vial = compound.currentVial {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(compound.displayName(of: vial)) · \(InsightText.level(vial))")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                LevelBar(fraction: vial.fractionRemaining)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(InsightText.vialAccessibility(compound: compound, vial: vial, insights: nil))
        } else {
            Label("Sem vial cadastrado", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
        }
    }

    @ViewBuilder
    private func resolution(_ event: DoseEvent) -> some View {
        switch event.kind {
        case .applied:
            Text("Aplicada às \(Formatting.time(event.performedAt)) · \(Formatting.milligrams(event.doseMicrograms))")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        case .skipped:
            Text(event.note.isEmpty ? String(localized: "Pulada") : String(localized: "Pulada: \(event.note)"))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var actions: some View {
        AdaptiveStack(spacing: Theme.spacing(1)) {
            Button(action: onApply) {
                Label("Aplicar", systemImage: "syringe")
            }
            .buttonStyle(PrimaryButtonStyle())
            if status.isPending {
                Button(action: onSkip) {
                    Label("Pular", systemImage: "forward")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
