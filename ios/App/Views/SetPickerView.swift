import SwiftUI
import PackRipCore

/// Choosing the set up front means recognition only searches that set's cards.
struct SetPickerView: View {
    @EnvironmentObject var data: DataStore
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(filtered) { s in
                Button { onPick(s.id); dismiss() } label: {
                    HStack {
                        Text(s.name)
                        Spacer()
                        Text("\(s.cards) cards").font(.caption).foregroundStyle(.secondary)
                    }
                }.tint(.primary)
            }
            .overlay { if data.sets.isEmpty { Text("No sets loaded. See Settings.").foregroundStyle(.secondary) } }
            .searchable(text: $query)
            .navigationTitle("Which set is this pack?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var filtered: [SetInfo] {
        query.isEmpty ? data.sets : data.sets.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
