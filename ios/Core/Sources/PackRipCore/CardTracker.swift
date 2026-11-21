import Foundation

/// Counts each physical card once in a video: the same card seen again within `gap` seconds is the
/// same flip; the same card after a different card, or after a gap, is a new card.
public struct CardTracker: Sendable {
    public var gap: TimeInterval
    private var lastCardId: String?
    private var lastSeen: TimeInterval = -.infinity

    public init(gap: TimeInterval = 1.0) { self.gap = gap }

    /// Returns true when this observation starts a new card.
    public mutating func observe(cardId: String, at time: TimeInterval) -> Bool {
        defer { lastCardId = cardId; lastSeen = time }
        if cardId == lastCardId && time - lastSeen <= gap { return false }
        return true
    }

    public mutating func reset() { lastCardId = nil; lastSeen = -.infinity }
}
