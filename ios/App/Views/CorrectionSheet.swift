import SwiftUI
import PackRipCore

/// Pick the right card (top suggestions first, then search the set) and, when it matters, the printing.
struct CorrectionSheet: View {
    @EnvironmentObject var data: DataStore
    @Environment(\.dismiss) private var dismiss
    let setId: String
    let candidates: [String]
    let guess: Printing?
    let onPick: (String, Printing?) -> Void
    @State private var query = ""
    @State private var chosen: CatalogCard?

    var body: some View {
        NavigationStack {
            List {
                if let chosen {
                    Section("Which printing is it?") {
                        ForEach(data.prices.printings(for: chosen.id), id: \.self) { p in
                            Button {
                                onPick(chosen.id, p); dismiss()
                            } label: {
                                HStack {
                                    Text(p.label + (p == guess ? " (best guess)" : ""))
                                    Spacer()
                                    if let q = data.prices.quote(cardId: chosen.id, printing: p) { Text(Recapper.money(q.market)).monospacedDigit() }
                                }
                            }.tint(.primary)
                        }
                    }
                } else {
                    if query.isEmpty && !candidates.isEmpty {
                        Section("Best matches") { ForEach(candidateCards) { row($0) } }
                    }
                    Section(query.isEmpty ? "All cards in the set" : "Results") { ForEach(searchResults) { row($0) } }
                }
            }
            .searchable(text: $query, prompt: "Search by name")
            .navigationTitle(chosen == nil ? "Pick the card" : chosen!.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var candidateCards: [CatalogCard] { candidates.compactMap { data.card(id: $0) } }

    private var searchResults: [CatalogCard] {
        let all = data.cards(in: setId)
        let f = query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.number == query }
        return Array(f.prefix(60))
    }

    private func row(_ c: CatalogCard) -> some View {
        Button { choose(c) } label: {
            HStack {
                AsyncImage(url: c.imageSmall.flatMap(URL.init(string:))) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                    .frame(width: 40, height: 56)
                VStack(alignment: .leading) {
                    Text(c.name)
                    Text("\(c.number) · \(c.rarity)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.tint(.primary)
    }

    private func choose(_ c: CatalogCard) {
        let printings = data.prices.printings(for: c.id)
        if printings.count > 1 { chosen = c } else { onPick(c.id, printings.first); dismiss() }
    }
}
