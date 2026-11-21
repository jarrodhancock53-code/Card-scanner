import Foundation

/// The printing of a card. Price differs by printing, so it is part of every price key.
public enum Printing: String, Codable, CaseIterable, Sendable {
    case normal, holo, reverseHolo, firstEdition

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .holo: return "Holo"
        case .reverseHolo: return "Reverse holo"
        case .firstEdition: return "1st edition"
        }
    }
}

/// One card from catalog/<set>.json (written by tools/sync.py).
public struct CatalogCard: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let number: String
    public let rarity: String
    public let supertype: String
    public let setId: String
    public let setName: String
    public let printedTotal: Int?
    public let imageSmall: String?
    public let imageLarge: String?

    public init(id: String, name: String, number: String, rarity: String = "", supertype: String = "Pokémon",
                setId: String, setName: String, printedTotal: Int? = nil,
                imageSmall: String? = nil, imageLarge: String? = nil) {
        self.id = id; self.name = name; self.number = number; self.rarity = rarity
        self.supertype = supertype; self.setId = setId; self.setName = setName
        self.printedTotal = printedTotal; self.imageSmall = imageSmall; self.imageLarge = imageLarge
    }
}

/// One set as listed in sets.json.
public struct SetInfo: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let cards: Int
    public let printedTotal: Int?
    public let priced: Int
    public let printings: [String]
}

public struct PriceEntry: Codable, Hashable, Sendable {
    public let market: Double
    public let low: Double?
    public let high: Double?
    public init(market: Double, low: Double? = nil, high: Double? = nil) {
        self.market = market; self.low = low; self.high = high
    }
}

/// prices/<set>.json: cardId -> printing key -> entry.
public struct PriceFile: Codable, Sendable {
    public let updatedAt: String
    public let cards: [String: [String: PriceEntry]]
    public init(updatedAt: String, cards: [String: [String: PriceEntry]]) {
        self.updatedAt = updatedAt; self.cards = cards
    }
}
