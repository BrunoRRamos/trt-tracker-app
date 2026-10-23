import Foundation
import SwiftData
import TRTCore

/// Cadastro, fila, ajuste e arquivamento de vials (RF-VIA-02, 03, 05 e 08).
@MainActor
enum VialService {
    struct VialInput {
        var totalMicroliters: Int
        var concentrationMicrogramsPerMl: Int
        var remainingMicroliters: Int
        var nickname: String
        var openedAt: Date?
        var lot: String
        var expiresAt: Date?
    }

    /// Novo vial entra no fim da fila; o primeiro do composto vira o vial atual.
    @discardableResult
    static func add(_ input: VialInput, to compound: Compound, in context: ModelContext) -> Vial {
        let vial = Vial(totalMicroliters: input.totalMicroliters,
                        concentrationMicrogramsPerMl: input.concentrationMicrogramsPerMl,
                        initialMicroliters: input.remainingMicroliters)
        apply(input, to: vial)
        vial.queueIndex = (compound.vials.map(\.queueIndex).max() ?? -1) + 1
        context.insert(vial)
        vial.compound = compound
        compound.lowStockAlertSent = false
        try? context.save()
        return vial
    }

    /// "Adicionar mais um igual": duplica o último vial cadastrado, cheio (RF-VIA-02, P1).
    @discardableResult
    static func duplicateLast(of compound: Compound, in context: ModelContext) -> Vial? {
        guard let last = compound.lastRegisteredVial else { return nil }
        let input = VialInput(totalMicroliters: last.totalMicroliters,
                              concentrationMicrogramsPerMl: last.concentrationMicrogramsPerMl,
                              remainingMicroliters: last.totalMicroliters,
                              nickname: last.nickname, openedAt: nil, lot: last.lot, expiresAt: last.expiresAt)
        return add(input, to: compound, in: context)
    }

    /// Edita um vial. Se o volume restante mudar num vial já usado ou ajustado, a diferença vira um evento "Ajuste".
    static func update(_ vial: Vial, with input: VialInput, in context: ModelContext) {
        let previousRemaining = vial.remainingMicroliters
        vial.totalMicroliters = input.totalMicroliters
        vial.concentrationMicrogramsPerMl = input.concentrationMicrogramsPerMl
        apply(input, to: vial)
        if input.remainingMicroliters != previousRemaining {
            if vial.usages.isEmpty && vial.adjustments.isEmpty {
                vial.initialMicroliters = input.remainingMicroliters
            } else {
                addAdjustment(to: vial, before: previousRemaining, after: input.remainingMicroliters,
                              note: String(localized: "Edição do vial"), in: context)
            }
        }
        vial.lowAlertSent = false
        try? context.save()
    }

    /// Ajuste manual do nível (RF-VIA-05).
    static func adjust(_ vial: Vial, to newRemaining: Int, note: String, in context: ModelContext) {
        let before = vial.remainingMicroliters
        guard before != newRemaining else { return }
        addAdjustment(to: vial, before: before, after: newRemaining, note: note, in: context)
        try? context.save()
    }

    private static func addAdjustment(to vial: Vial, before: Int, after: Int, note: String, in context: ModelContext) {
        let adjustment = VialAdjustment(beforeMicroliters: before, afterMicroliters: min(max(0, after), vial.totalMicroliters), note: note)
        context.insert(adjustment)
        adjustment.vial = vial
    }

    /// Reordena a fila de estoque; o vial atual continua em primeiro (RF-VIA-03).
    static func reorderStock(of compound: Compound, newOrder: [Vial], in context: ModelContext) {
        guard let current = compound.currentVial else { return }
        let inactiveMax = compound.inactiveVials.map(\.queueIndex).max() ?? -1
        for (offset, vial) in ([current] + newOrder).enumerated() {
            vial.queueIndex = inactiveMax + 1 + offset
        }
        try? context.save()
    }

    static func archive(_ vial: Vial, in context: ModelContext) {
        vial.isArchived = true
        try? context.save()
    }

    /// Exclui o vial. Se ele tiver aplicações, os registros continuam no histórico, sem o vínculo
    /// e sem o volume descontado deste vial; por isso a interface oferece arquivar como alternativa (RF-VIA-08).
    static func delete(_ vial: Vial, in context: ModelContext) {
        let id = vial.id
        for usage in vial.usages {
            usage.event = nil
            usage.vial = nil
            context.delete(usage)
        }
        vial.compound = nil
        context.delete(vial)
        try? context.save()
        Task {
            await NotificationScheduler.shared.removeNotifications(mentioning: [id])
            await NotificationScheduler.shared.reschedule()
        }
    }

    private static func apply(_ input: VialInput, to vial: Vial) {
        vial.nickname = input.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        vial.openedAt = input.openedAt
        vial.lot = input.lot.trimmingCharacters(in: .whitespacesAndNewlines)
        vial.expiresAt = input.expiresAt
    }
}
