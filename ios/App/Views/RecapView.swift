import SwiftUI
import PackRipCore

struct RecapView: View {
    @EnvironmentObject var model: AppModel
    let session: PackSession
    let isLive: Bool
    var onClose: (() -> Void)? = nil

    var body: some View {
        let r = Recapper.recap(session)
        List {
            Section {
                row("Pulled value", Recapper.money(r.totalValue))
                row("Pack cost", Recapper.money(r.cost))
                HStack {
                    Text("Net").bold()
                    Spacer()
                    Text((r.net >= 0 ? "+" : "-") + Recapper.money(abs(r.net)))
                        .bold().monospacedDigit().foregroundStyle(r.net >= 0 ? .green : .red)
                }
                row("Cards", "\(r.cardCount)")
                row("Hit rate (\(Recapper.money(session.hitThreshold))+)", "\(r.hits) of \(r.cardCount)")
            }
            if let best = r.best, best.value > 0 {
                Section("Best pull") { CardRow(card: best) }
            }
            let flagged = session.packs.flatMap(\.cards).filter(\.flagged)
            if !flagged.isEmpty {
                Section("Check these (flagged)") { ForEach(flagged) { CardRow(card: $0) } }
            }
            ForEach(Array(session.packs.enumerated()), id: \.element.id) { i, pack in
                if !pack.cards.isEmpty {
                    Section("Pack \(i + 1) · \(Recapper.money(pack.cards.reduce(0) { $0 + $1.value }))") {
                        ForEach(pack.cards) { CardRow(card: $0) }
                    }
                }
            }
            Section {
                ShareLink(item: csvFile(), preview: SharePreview("Pack rip session.csv")) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                if isLive {
                    Button("End session and save", role: .destructive) { model.endSession(); onClose?() }
                }
            }
        }
        .navigationTitle("Recap")
        .toolbar { if isLive { ToolbarItem(placement: .cancellationAction) { Button("Back") { onClose?() } } } }
    }

    private func row(_ l: String, _ v: String) -> some View {
        HStack { Text(l); Spacer(); Text(v).monospacedDigit() }
    }

    private func csvFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pack-rip-\(session.id.uuidString.prefix(8)).csv")
        try? CSVExport.csv(for: session).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
