import SwiftUI
import PackRipCore

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var data: DataStore
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                if let err = data.loadError {
                    Section { Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                Section {
                    if model.current != nil {
                        NavigationLink("Resume session") { SessionView() }
                    }
                    Button(model.current == nil ? "New session" : "Start a different session") { showNew = true }
                }
                Section("Past sessions") {
                    if model.history.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                    ForEach(model.history) { s in
                        NavigationLink { RecapView(session: s, isLive: false) } label: {
                            let r = Recapper.recap(s)
                            VStack(alignment: .leading) {
                                Text(s.startedAt.formatted(date: .abbreviated, time: .shortened))
                                Text("\(r.cardCount) cards, \(Recapper.money(r.totalValue)) from \(Recapper.money(r.cost))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in idx.map { model.history[$0] }.forEach(model.delete) }
                }
                Section { NavigationLink("Settings") { SettingsView() } }
            }
            .navigationTitle("Pack Rip Tracker")
            .sheet(isPresented: $showNew) { NewSessionView() }
        }
    }
}

struct NewSessionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var cost = ""
    @State private var packs = "36"

    var body: some View {
        NavigationStack {
            Form {
                Section("What you paid") {
                    TextField("Box or bundle price ($)", text: $cost).keyboardType(.decimalPad)
                    TextField("Packs in it", text: $packs).keyboardType(.numberPad)
                }
                if let c = Double(cost), let n = Int(packs), n > 0 {
                    Text("That is \(Recapper.money(c / Double(n))) per pack.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        model.startSession(totalCost: Double(cost) ?? 0, packCount: Int(packs) ?? 1)
                        dismiss()
                    }.disabled(Double(cost) == nil || (Int(packs) ?? 0) < 1)
                }
            }
        }
    }
}
