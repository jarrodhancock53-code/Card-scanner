import Foundation
import PackRipCore

/// Sessions and settings. Sessions are saved as one JSON file after every change.
@MainActor
final class AppModel: ObservableObject {
    @Published var history: [PackSession] = []
    @Published var current: PackSession?
    @Published var dataURL: String { didSet { UserDefaults.standard.set(dataURL, forKey: "dataURL") } }
    @Published var hitThreshold: Double { didSet { UserDefaults.standard.set(hitThreshold, forKey: "hitThreshold") } }

    private let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sessions.json")

    init() {
        dataURL = UserDefaults.standard.string(forKey: "dataURL") ?? ""
        let t = UserDefaults.standard.double(forKey: "hitThreshold")
        hitThreshold = t > 0 ? t : 5
        if let d = try? Data(contentsOf: file), let h = try? JSONDecoder().decode([PackSession].self, from: d) { history = h }
    }

    func startSession(totalCost: Double, packCount: Int) {
        current = PackSession(totalCost: totalCost, packCount: packCount, hitThreshold: hitThreshold)
    }

    func startPack(setId: String) {
        guard current != nil else { return }
        // A pack with no cards yet is replaced, not stacked.
        if let last = current?.packs.last, last.cards.isEmpty { current?.packs.removeLast() }
        current?.packs.append(Pack(setId: setId))
    }

    var currentPackIndex: Int? { current.flatMap { $0.packs.isEmpty ? nil : $0.packs.count - 1 } }

    func add(_ card: PulledCard) {
        guard let i = currentPackIndex else { return }
        current?.packs[i].cards.append(card)
    }

    func replace(_ card: PulledCard) {
        guard let s = current else { return }
        for (pi, p) in s.packs.enumerated() {
            if let ci = p.cards.firstIndex(where: { $0.id == card.id }) { current?.packs[pi].cards[ci] = card; return }
        }
    }

    func remove(cardID: UUID) {
        guard var s = current else { return }
        for i in s.packs.indices { s.packs[i].cards.removeAll { $0.id == cardID } }
        current = s
    }

    func endSession() {
        guard var s = current else { return }
        s.endedAt = Date()
        history.insert(s, at: 0)
        current = nil
        save()
    }

    func delete(_ s: PackSession) { history.removeAll { $0.id == s.id }; save() }

    func save() {
        if let d = try? JSONEncoder().encode(history) { try? d.write(to: file, options: .atomic) }
    }
}
