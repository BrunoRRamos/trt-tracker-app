import SwiftData
import SwiftUI
import TRTCore

/// Detalhe do protocolo (RF-PRO-04) com encerrar e excluir (RF-PRO-06).
struct ProtocolDetailView: View {
    let treatment: TreatmentProtocol

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var showEdit = false
    @State private var confirmEnd = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var compoundToDelete: Compound?
    @State private var showCannotDeleteCompound = false

    private var now: Date { appState.now }
    private var today: LocalDay { LocalDay(now) }

    var body: some View {
        Group {
            if isDeleting || treatment.isDeleted {
                Color.clear
            } else {
                content
            }
        }
        .screenBackground()
        .navigationTitle(isDeleting ? "" : treatment.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Editar") { showEdit = true }
                    .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showEdit) {
            ProtocolFormView(mode: .edit(treatment))
        }
        .confirmationDialog("Encerrar o protocolo hoje?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Encerrar agora", role: .destructive, action: endNow)
        } message: {
            Text("A data de fim passa a ser hoje e os lembretes futuros são cancelados. O histórico é mantido.")
        }
        .alert("Excluir composto?", isPresented: Binding(get: { compoundToDelete != nil }, set: { if !$0 { compoundToDelete = nil } }),
               presenting: compoundToDelete) { compound in
            Button("Excluir", role: .destructive) {
                Haptics.warning()
                let name = compound.name
                CompoundService.delete(compound, in: context)
                appState.tick()
                appState.showToast(String(localized: "\(name) excluído"))
            }
            Button("Cancelar", role: .cancel) {}
        } message: { compound in
            Text("Esta ação é irreversível: \(compound.name), seus vials e todo o histórico de aplicações dele serão apagados.")
        }
        .alert("Não é possível excluir", isPresented: $showCannotDeleteCompound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Este é o único composto do protocolo, e o protocolo precisa de pelo menos um. Adicione outro composto ou exclua o protocolo.")
        }
        .alert("Excluir protocolo?", isPresented: $confirmDelete) {
            Button("Excluir", role: .destructive, action: deleteProtocol)
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta ação é irreversível: o protocolo, seus compostos, vials e todo o histórico serão apagados.")
        }
    }

    private var content: some View {
        let status = treatment.status(today: today)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing(2)) {
                header(status)
                permissionNotice
                ForEach(treatment.orderedCompounds) { compound in
                    CompoundSummaryCard(compound: compound, now: now)
                        .contextMenu {
                            Button("Excluir composto", systemImage: "trash", role: .destructive) {
                                if CompoundService.canDelete(compound) { compoundToDelete = compound } else { showCannotDeleteCompound = true }
                            }
                        }
                }
                links
                actions(status)
            }
            .padding(Theme.spacing(2))
        }
    }

    private func header(_ status: ProtocolStatus) -> some View {
        let total = treatment.totalDays
        let elapsed = treatment.elapsedDays(today: today)
        return VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            AdaptiveStack {
                Text(treatment.name)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                StatusBadge(status)
            }
            Text(Formatting.period(start: treatment.startDay, end: treatment.endDay))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline) {
                Text(daysText(status))
                    .font(.rounded(.title3, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("Dia \(elapsed) de \(total)")
                    .font(.rounded(.subheadline, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            ProgressView(value: Double(elapsed), total: Double(total))
                .tint(Theme.accent)
                .motion(elapsed)
                .accessibilityLabel(Text("Progresso do protocolo"))
                .accessibilityValue(Text("Dia \(elapsed) de \(total)"))
        }
        .card()
    }

    private func daysText(_ status: ProtocolStatus) -> String {
        switch status {
        case .scheduled:
            return String(localized: "Começa \(relativeDays(from: today, to: treatment.startDay))")
        case .active:
            let remaining = today.days(to: treatment.endDay)
            return remaining == 0 ? String(localized: "Último dia") : String(localized: "\(Plural.days(remaining)) restantes")
        case .ended:
            return String(localized: "Encerrado em \(Formatting.numericDate(treatment.endDay))")
        }
    }

    /// Aviso quando a permissão de notificações foi negada (RF-NOT-02).
    @ViewBuilder
    private var permissionNotice: some View {
        if treatment.hasAnyReminderEnabled && treatment.status(today: today) != .ended {
            switch appState.notificationStatus {
            case .denied:
                VStack(alignment: .leading, spacing: Theme.spacing(1)) {
                    NoticeView(tone: .warning, title: String(localized: "Notificações desativadas"),
                               message: String(localized: "Os lembretes deste protocolo não serão exibidos."))
                    Button("Abrir ajustes de notificação") { NotificationScheduler.openSystemNotificationSettings() }
                        .buttonStyle(SecondaryButtonStyle(tint: Theme.accent))
                }
            case .notDetermined:
                VStack(alignment: .leading, spacing: Theme.spacing(1)) {
                    NoticeView(tone: .info, title: String(localized: "Lembretes ainda não ativados"))
                    Button("Ativar lembretes") { appState.showNotificationPrimer = true }
                        .buttonStyle(SecondaryButtonStyle(tint: Theme.accent))
                }
            default:
                EmptyView()
            }
        }
    }

    private var links: some View {
        VStack(spacing: Theme.spacing(1)) {
            NavigationLink {
                ProtocolCalendarView(treatment: treatment)
            } label: {
                linkLabel(String(localized: "Calendário"), icon: "calendar")
            }
            NavigationLink {
                PlasmaLevelsView(treatment: treatment)
            } label: {
                linkLabel(String(localized: "Níveis estimados"), icon: "chart.xyaxis.line")
            }
            NavigationLink {
                HistoryListScreen(treatment: treatment)
            } label: {
                linkLabel(String(localized: "Histórico"), icon: "clock.arrow.circlepath")
            }
        }
    }

    private func linkLabel(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .card()
    }

    private func actions(_ status: ProtocolStatus) -> some View {
        VStack(spacing: Theme.spacing(1)) {
            if status != .ended {
                Button("Encerrar agora") { confirmEnd = true }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.warning))
            }
            Button("Excluir protocolo") { confirmDelete = true }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.critical))
        }
        .padding(.top, Theme.spacing(1))
    }

    private func endNow() {
        treatment.endDay = LocalDay(Date())
        treatment.endedManually = true
        try? context.save()
        Haptics.warning()
        appState.tick()
        Task { await NotificationScheduler.shared.reschedule() }
    }

    private func deleteProtocol() {
        Haptics.warning()
        isDeleting = true
        dismiss()
        let modelContext = context
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            modelContext.delete(treatment)
            try? modelContext.save()
            await NotificationScheduler.shared.reschedule()
        }
    }
}

/// Resumo do composto no detalhe do protocolo: dose, agenda, lembrete, vial atual e projeções (RF-PRO-04).
struct CompoundSummaryCard: View {
    let compound: Compound
    let now: Date

    var body: some View {
        let insights = CompoundInsights(compound: compound, now: now)
        VStack(alignment: .leading, spacing: Theme.spacing(2)) {
            NavigationLink {
                CompoundDetailView(compound: compound)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compound.name)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(Formatting.milligrams(compound.doseMicrograms)) · \(compound.schedule.summary)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Text(reminderText)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)

            CurrentVialSummary(compound: compound, insights: insights)

            StockInsightsView(compound: compound, insights: insights)
        }
        .card()
    }

    private var reminderText: String {
        guard compound.reminderEnabled else { return String(localized: "Lembrete desligado") }
        let time = compound.reminderTime
        return String(localized: "Lembrete às \(Formatting.time(hour: time.hour, minute: time.minute))")
    }
}

/// Vial atual com anel, porcentagem e ml restantes, "dura até" e próximo vial (RF-VIA-06).
struct CurrentVialSummary: View {
    let compound: Compound
    let insights: CompoundInsights

    var body: some View {
        if let vial = insights.currentVial {
            AdaptiveStack(spacing: Theme.spacing(2)) {
                VialRing(fraction: vial.fractionRemaining,
                         percentText: Formatting.percent(vial.percentRemaining),
                         millilitersText: Formatting.milliliters(vial.remainingMicroliters),
                         tint: vial.levelTint(applicationsRemaining: insights.applicationsRemaining(in: vial)),
                         size: 96,
                         accessibilityText: InsightText.vialAccessibility(compound: compound, vial: vial, insights: insights))
                VStack(alignment: .leading, spacing: 4) {
                    Text(compound.displayName(of: vial))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(InsightText.level(vial))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    if let per = insights.perApplicationMicroliters {
                        Text("\(InsightText.volume(per)) por aplicação")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let duration = InsightText.duration(insights) {
                        Text(duration)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let next = InsightText.nextVial(insights) {
                        Text(next)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        } else {
            NoticeView(tone: .warning, title: String(localized: "Sem vial cadastrado"),
                       message: String(localized: "Cadastre um vial no composto para acompanhar o nível e a duração."))
        }
    }
}
