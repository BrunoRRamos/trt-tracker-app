import SwiftUI
import TRTCore

/// Escolha da substância a partir do catálogo de compostos (substância → éster/forma), ou "Outro".
struct CatalogPickerView: View {
    let selectedKey: String?
    var isCustom = false
    let onSelect: (CatalogEntry?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let catalog = CompoundCatalog.shared

    private func matches(_ compound: CatalogCompound) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let haystack = ([compound.name, compound.chemicalName] + compound.esters.compactMap(\.ester)).joined(separator: " ")
        return haystack.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    var body: some View {
        List {
            ForEach(catalog.compounds.filter(matches)) { compound in
                Section {
                    ForEach(catalog.entries(of: compound)) { entry in
                        Button {
                            onSelect(entry)
                            dismiss()
                        } label: {
                            row(entry)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compound.name)
                        Text([compound.chemicalName, compound.compoundClass].compactMap { $0 }.joined(separator: " · "))
                            .textCase(nil)
                            .font(.caption)
                    }
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Label("Outro (fora da lista)", systemImage: "square.and.pencil")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if isCustom {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                .accessibilityLabel(Text("Selecionado"))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Para compostos fora da lista, informe o nome e, se souber, a meia-vida para ver a curva estimada.")
            }
            .listRowBackground(Theme.surface)
        }
        .listStyle(.insetGrouped)
        .sheetBackground()
        .searchable(text: $query, prompt: Text("Buscar substância ou éster"))
        .navigationTitle("Substância")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ entry: CatalogEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.variantLabel ?? String(localized: "Sem éster"))
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(details(entry))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                if let note = entry.variant.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if entry.key == selectedKey {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(Text("Selecionado"))
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func details(_ entry: CatalogEntry) -> String {
        var parts = [entry.variant.route.title,
                     String(localized: "meia-vida \(Formatting.halfLife(hours: entry.variant.halfLifeHours))"),
                     String(localized: "\(Formatting.percentValue(entry.variant.activeDosePercent)) ativo")]
        if entry.variant.halfLifeOrigin != nil {
            parts.append(entry.variant.halfLifeOrigin.label)
        }
        return parts.joined(separator: " · ")
    }
}

extension AdministrationRoute {
    var title: String {
        switch self {
        case .oral: String(localized: "Oral")
        case .intramuscular: String(localized: "Intramuscular")
        }
    }
}
