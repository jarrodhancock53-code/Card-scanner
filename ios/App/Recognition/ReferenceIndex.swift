import CoreGraphics
import Foundation
import PackRipCore
import Vision

/// Feature prints of every card in one set, built on first use and used for nearest-neighbour matching.
@MainActor
final class ReferenceIndex: ObservableObject {
    struct Entry {
        let card: CatalogCard
        let print: VNFeaturePrintObservation
        let shimmer: RegionShimmer?
    }

    @Published private(set) var setId: String?
    @Published private(set) var progress = 0.0
    @Published private(set) var isReady = false
    @Published private(set) var missingImages = 0
    private(set) var entries: [Entry] = []

    func build(setId: String, cards: [CatalogCard]) async {
        if self.setId == setId && isReady { return }
        self.setId = setId; isReady = false; progress = 0; entries = []; missingImages = 0
        var built: [Entry] = []
        for (i, card) in cards.enumerated() {
            if let img = await ImageCache.load(card.imageSmall, key: card.id),
               let fp = Self.featurePrint(img) {
                built.append(Entry(card: card, print: fp, shimmer: RegionShimmer(img)))
            } else {
                missingImages += 1
            }
            progress = Double(i + 1) / Double(max(cards.count, 1))
        }
        entries = built
        isReady = !built.isEmpty
    }

    nonisolated static func featurePrint(_ image: CGImage) -> VNFeaturePrintObservation? {
        let req = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([req]) } catch { return nil }
        return req.results?.first
    }

    /// Candidates sorted by ascending distance. Distances are divided by the median distance so the
    /// thresholds do not depend on Vision's absolute feature-print scale.
    func nearest(to print: VNFeaturePrintObservation, limit: Int = 5) -> [Candidate] {
        var raw: [(Entry, Double)] = []
        for e in entries {
            var d: Float = 0
            if (try? print.computeDistance(&d, to: e.print)) != nil { raw.append((e, Double(d))) }
        }
        guard !raw.isEmpty else { return [] }
        let sorted = raw.sorted { $0.1 < $1.1 }
        let median = max(sorted[sorted.count / 2].1, 1e-6)
        return sorted.prefix(limit).map { Candidate(cardId: $0.0.card.id, number: $0.0.card.number, distance: $0.1 / median) }
    }

    func shimmer(for cardId: String) -> RegionShimmer? { entries.first { $0.card.id == cardId }?.shimmer }
}
