import Foundation

public struct PriceQuote: Equatable, Sendable {
    /// nil when the printing is unknown and the quote is a range across printings.
    public let printing: Printing?
    public let market: Double
    public let low: Double
    public let high: Double
    public var isRange: Bool { high > low && printing == nil }
}

/// Looks prices up in the local table. Never makes a network call.
public struct PriceTable: Sendable {
    private let cards: [String: [Printing: PriceEntry]]
    public let updatedAt: String

    public init(files: [PriceFile]) {
        var merged: [String: [Printing: PriceEntry]] = [:]
        for file in files {
            for (cardId, byPrinting) in file.cards {
                var m: [Printing: PriceEntry] = [:]
                for (key, entry) in byPrinting {
                    if let p = Printing(rawValue: key) { m[p] = entry }
                }
                merged[cardId] = m
            }
        }
        self.cards = merged
        self.updatedAt = files.map(\.updatedAt).max() ?? ""
    }

    public init(file: PriceFile) { self.init(files: [file]) }

    public func printings(for cardId: String) -> [Printing] {
        guard let m = cards[cardId] else { return [] }
        return Printing.allCases.filter { m[$0] != nil }
    }

    /// True when the card has more than one priced printing and the prices differ enough
    /// that guessing wrong would show a materially wrong number.
    public func printingMatters(cardId: String, minDifference: Double = 0.25) -> Bool {
        guard let m = cards[cardId], m.count > 1 else { return false }
        let prices = m.values.map(\.market)
        return (prices.max() ?? 0) - (prices.min() ?? 0) >= minDifference
    }

    /// Exact quote for a known printing, or a range across printings when `printing` is nil.
    /// Returns nil when the card or printing has no price.
    public func quote(cardId: String, printing: Printing?) -> PriceQuote? {
        guard let m = cards[cardId], !m.isEmpty else { return nil }
        if let printing {
            guard let e = m[printing] else { return nil }
            return PriceQuote(printing: printing, market: e.market, low: e.low ?? e.market, high: e.high ?? e.market)
        }
        if m.count == 1, let (p, e) = m.first {
            return PriceQuote(printing: p, market: e.market, low: e.low ?? e.market, high: e.high ?? e.market)
        }
        let markets = m.values.map(\.market)
        let lo = markets.min() ?? 0, hi = markets.max() ?? 0
        return PriceQuote(printing: nil, market: lo, low: lo, high: hi)
    }
}
