import SwiftData
import SwiftUI

/// Confirmação de exclusão de vial. Num vial com aplicações, oferece arquivar (preserva o vínculo
/// com o histórico, RF-VIA-08) ou excluir mesmo assim.
struct VialDeletionDialog: ViewModifier {
    @Binding var vial: Vial?
    /// Exclusão personalizada (ex.: voltar da tela antes de excluir); padrão: exclui na hora.
    var onDelete: ((Vial) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    private var isPresented: Binding<Bool> {
        Binding(get: { vial != nil }, set: { if !$0 { vial = nil } })
    }

    func body(content: Content) -> some View {
        content.confirmationDialog("Excluir vial?", isPresented: isPresented, titleVisibility: .visible, presenting: vial) { vial in
            if vial.hasApplications && !vial.isArchived {
                Button("Arquivar") { archive(vial) }
            }
            Button(vial.hasApplications ? String(localized: "Excluir mesmo assim") : String(localized: "Excluir"),
                   role: .destructive) { delete(vial) }
            Button("Cancelar", role: .cancel) {}
        } message: { vial in
            Text(message(for: vial))
        }
    }

    private func message(for vial: Vial) -> String {
        let name = vial.compound.map { $0.displayName(of: vial) } ?? String(localized: "Este vial")
        let applications = Set(vial.usages.compactMap { $0.event?.id }).count
        guard applications > 0 else {
            return String(localized: "\(name) não tem aplicações registradas e será apagado.")
        }
        return String(localized: "\(name) tem \(Plural.applications(applications)) registrada(s). Elas continuam no histórico, mas sem o vínculo com o vial e sem o volume descontado dele. Arquive para manter o vínculo.")
    }

    private func archive(_ vial: Vial) {
        VialService.archive(vial, in: context)
        appState.tick()
        appState.showToast(String(localized: "Vial arquivado"))
        Task { await NotificationScheduler.shared.reschedule() }
    }

    private func delete(_ vial: Vial) {
        Haptics.warning()
        if let onDelete {
            onDelete(vial)
        } else {
            VialService.delete(vial, in: context)
            appState.tick()
            appState.showToast(String(localized: "Vial excluído"))
        }
    }
}

extension View {
    func vialDeletionDialog(vial: Binding<Vial?>, onDelete: ((Vial) -> Void)? = nil) -> some View {
        modifier(VialDeletionDialog(vial: vial, onDelete: onDelete))
    }

    /// Ações de deslizar de uma linha de vial: excluir e, quando houver aplicações, arquivar.
    func vialSwipeActions(_ vial: Vial, onDelete: @escaping () -> Void, onArchive: @escaping () -> Void) -> some View {
        swipeActions(edge: .trailing) {
            Button(action: onDelete) {
                Label("Excluir", systemImage: "trash")
            }
            .tint(Theme.critical)
            if vial.hasApplications && !vial.isArchived {
                Button(action: onArchive) {
                    Label("Arquivar", systemImage: "archivebox")
                }
                .tint(Theme.warning)
            }
        }
    }
}
