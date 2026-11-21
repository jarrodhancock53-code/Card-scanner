import Foundation

/// Cards that are in every pack but should never cost a tap or move the recap.
public enum SkipRules {
    public static let codeCardId = "code-card"

    /// Basic energy cards are worth $0 for the recap.
    public static func isZeroValue(supertype: String) -> Bool {
        supertype.caseInsensitiveCompare("Energy") == .orderedSame
    }

    public static func isCodeCard(cardId: String) -> Bool { cardId == codeCardId }
}
