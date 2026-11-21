import Foundation

public struct PulledCard: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var cardId: String
    public var name: String
    public var setId: String
    public var number: String
    public var rarity: String
    public var printing: Printing?
    public var value: Double
    public var valueHigh: Double
    public var flagged: Bool
    public var corrected: Bool
    public var capturedAt: Date

    public init(id: UUID = UUID(), cardId: String, name: String, setId: String, number: String,
                rarity: String, printing: Printing?, value: Double, valueHigh: Double? = nil,
                flagged: Bool = false, corrected: Bool = false, capturedAt: Date = Date()) {
        self.id = id; self.cardId = cardId; self.name = name; self.setId = setId; self.number = number
        self.rarity = rarity; self.printing = printing; self.value = value
        self.valueHigh = valueHigh ?? value; self.flagged = flagged; self.corrected = corrected
        self.capturedAt = capturedAt
    }
}

public struct Pack: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var setId: String
    public var cards: [PulledCard]
    public var closed: Bool
    public init(id: UUID = UUID(), setId: String, cards: [PulledCard] = [], closed: Bool = false) {
        self.id = id; self.setId = setId; self.cards = cards; self.closed = closed
    }
}

public struct PackSession: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    /// What the box or bundle cost, and how many packs it held. Cost per pack = totalCost / packCount.
    public var totalCost: Double
    public var packCount: Int
    public var hitThreshold: Double
    public var packs: [Pack]

    public init(id: UUID = UUID(), startedAt: Date = Date(), totalCost: Double, packCount: Int,
                hitThreshold: Double = 5, packs: [Pack] = []) {
        self.id = id; self.startedAt = startedAt; self.totalCost = totalCost
        self.packCount = max(packCount, 1); self.hitThreshold = hitThreshold; self.packs = packs
    }

    public var costPerPack: Double { totalCost / Double(max(packCount, 1)) }
}

public struct Recap: Equatable, Sendable {
    public let cost: Double
    public let totalValue: Double
    public var net: Double { totalValue - cost }
    public let cardCount: Int
    public let flaggedCount: Int
    public let hits: Int
    public var hitRate: Double { cardCount == 0 ? 0 : Double(hits) / Double(cardCount) }
    public let best: PulledCard?
}

public enum Recapper {
    /// Cost counts only packs that were actually opened (have cards), at the session's cost per pack.
    public static func recap(_ s: PackSession) -> Recap {
        let opened = s.packs.filter { !$0.cards.isEmpty }
        let cards = opened.flatMap(\.cards)
        let total = cards.reduce(0) { $0 + $1.value }
        return Recap(cost: s.costPerPack * Double(opened.count),
                     totalValue: total,
                     cardCount: cards.count,
                     flaggedCount: cards.filter(\.flagged).count,
                     hits: cards.filter { $0.value >= s.hitThreshold }.count,
                     best: cards.max(by: { $0.value < $1.value }))
    }

    public static func money(_ v: Double) -> String { String(format: "$%.2f", v) }
}
