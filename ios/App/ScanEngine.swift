import CoreGraphics
import Foundation
import PackRipCore

/// Shared between the camera thread and the main actor.
final class FrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _latest: CGImage?
    private var _processing = false
    private var _live = false

    func store(_ f: CGImage) { lock.lock(); _latest = f; lock.unlock() }
    var latest: CGImage? { lock.lock(); defer { lock.unlock() }; return _latest }
    func setLive(_ v: Bool) { lock.lock(); _live = v; lock.unlock() }
    /// True when the caller should process this frame (live mode on, previous frame finished).
    func beginProcessing() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard _live, !_processing else { return false }
        _processing = true
        return true
    }
    func endProcessing() { lock.lock(); _processing = false; lock.unlock() }
}

struct PendingPick: Identifiable {
    let id = UUID()
    let candidateIds: [String]
    let crop: CGImage
    let guess: Printing?
}

@MainActor
final class ScanEngine: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case photo = "Photo", live = "Live", video = "Video file"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .photo { didSet { gate.setLive(mode == .live); picker = BestFramePicker<CGImage>(); tracker.reset() } }
    @Published var status = "Point the camera at a card"
    @Published var pending: [PendingPick] = []
    @Published var videoProgress: Double?
    let index = ReferenceIndex()
    let gate = FrameGate()
    var thresholds = MatchThresholds()

    private let model: AppModel
    private let data: DataStore
    private var picker = BestFramePicker<CGImage>()
    private var tracker = CardTracker()

    init(model: AppModel, data: DataStore) { self.model = model; self.data = data }

    func prepare(setId: String) async {
        status = "Preparing \(setId) cards..."
        await index.build(setId: setId, cards: data.cards(in: setId))
        status = index.isReady ? "Ready" : "Could not load card images for this set (check your connection)"
    }

    // MARK: Camera entry point (called on the camera queue)

    nonisolated func ingest(_ frame: CGImage, at t: TimeInterval) {
        gate.store(frame)
        guard gate.beginProcessing() else { return }
        let det = CardRecognizer.detectCard(in: frame)
        var crop: CGImage?
        var score = 0.0
        if let det, let c = CardRecognizer.crop(frame, det) {
            crop = c
            score = CardRecognizer.frameScore(crop: c, fill: det.fill)
        }
        Task { @MainActor in
            self.feed(crop: crop, score: score, at: t)
            self.gate.endProcessing()
        }
    }

    private func feed(crop: CGImage?, score: Double, at t: TimeInterval) {
        guard mode == .live || mode == .video else { return }
        if let best = picker.add(frame: crop, score: score, at: t) { resolve(crop: best, at: t) }
    }

    // MARK: Modes

    /// Photo mode: take whatever the camera sees right now.
    func shutter() {
        guard let frame = gate.latest else { status = "No camera frame yet"; return }
        guard let det = CardRecognizer.detectCard(in: frame), let crop = CardRecognizer.crop(frame, det) else {
            status = "No card found. Hold it flat in view."
            return
        }
        resolve(crop: crop, at: Date.timeIntervalSinceReferenceDate)
    }

    func processVideo(url: URL) async {
        picker = BestFramePicker<CGImage>()
        tracker.reset()
        videoProgress = 0
        status = "Reading video..."
        do {
            try await VideoFileReader.frames(from: url, handler: { frame, t in
                let result: (CGImage?, Double) = await Task.detached(priority: .userInitiated) {
                    if let det = CardRecognizer.detectCard(in: frame), let c = CardRecognizer.crop(frame, det) {
                        return (c, CardRecognizer.frameScore(crop: c, fill: det.fill))
                    }
                    return (nil, 0)
                }.value
                if let best = self.picker.add(frame: result.0, score: result.1, at: t) { self.resolve(crop: best, at: t) }
            }, progress: { self.videoProgress = $0 })
            if let last = picker.flush() { resolve(crop: last, at: .infinity) }
            status = "Video done"
        } catch {
            status = "Could not read that video"
        }
        videoProgress = nil
    }

    // MARK: Recognition and results

    private func resolve(crop: CGImage, at t: TimeInterval) {
        guard index.isReady else { status = "Card images are still loading"; return }
        guard let (rec, result) = CardRecognizer.recognize(crop: crop, index: index, prices: data.prices, thresholds: thresholds) else {
            status = "Could not recognize that card"
            return
        }
        if result.needsTap {
            pending.append(PendingPick(candidateIds: result.top5, crop: rec.crop, guess: rec.printing?.printing))
            status = "Not sure about one card. Tap it to pick."
            return
        }
        guard let id = result.cardId, let card = data.card(id: id) else { return }
        guard tracker.observe(cardId: id, at: t.isFinite ? t : 1e9) else { return }
        let pulled = makePulled(card, printing: result.printing, flagged: result.flagged, corrected: false)
        model.add(pulled)
        status = "\(card.name) \(Recapper.money(pulled.value))"
    }

    func makePulled(_ card: CatalogCard, printing: Printing?, flagged: Bool, corrected: Bool) -> PulledCard {
        if SkipRules.isZeroValue(supertype: card.supertype) {
            return PulledCard(cardId: card.id, name: card.name, setId: card.setId, number: card.number,
                              rarity: card.rarity, printing: nil, value: 0, flagged: false, corrected: corrected)
        }
        let q = data.prices.quote(cardId: card.id, printing: printing)
        let value = q?.market ?? 0
        return PulledCard(cardId: card.id, name: card.name, setId: card.setId, number: card.number, rarity: card.rarity,
                          printing: q?.printing ?? printing, value: value, valueHigh: q?.high ?? value,
                          flagged: flagged || (q == nil), corrected: corrected)
    }

    func resolvePending(_ p: PendingPick, cardId: String, printing: Printing?) {
        guard let card = data.card(id: cardId) else { return }
        model.add(makePulled(card, printing: printing, flagged: false, corrected: true))
        pending.removeAll { $0.id == p.id }
    }

    func dismissPending(_ p: PendingPick) { pending.removeAll { $0.id == p.id } }

    func addCodeCard(setId: String) {
        model.add(PulledCard(cardId: SkipRules.codeCardId, name: "Code card", setId: setId, number: "", rarity: "", printing: nil, value: 0))
    }

    func recorrect(_ old: PulledCard, cardId: String, printing: Printing?) {
        guard let card = data.card(id: cardId) else { return }
        var new = makePulled(card, printing: printing, flagged: false, corrected: true)
        new = PulledCard(id: old.id, cardId: new.cardId, name: new.name, setId: new.setId, number: new.number, rarity: new.rarity,
                         printing: new.printing, value: new.value, valueHigh: new.valueHigh, flagged: false, corrected: true,
                         capturedAt: old.capturedAt)
        model.replace(new)
    }
}
