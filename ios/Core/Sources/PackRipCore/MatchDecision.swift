import Foundation

/// A reference card and how far the scanned crop is from it (lower is closer).
public struct Candidate: Equatable, Sendable {
    public let cardId: String
    public let number: String
    public let distance: Double
    public init(cardId: String, number: String, distance: Double) {
        self.cardId = cardId; self.number = number; self.distance = distance
    }
}

public struct PrintingGuess: Equatable, Sendable {
    public let printing: Printing
    public let confidence: Double
    public init(printing: Printing, confidence: Double) { self.printing = printing; self.confidence = confidence }
}

/// Starting thresholds. The real values come from the 20-pack test (tools/validate.py), not from these guesses.
public struct MatchThresholds: Sendable {
    public var maxDistance = 0.55
    public var minMargin = 0.06
    /// Margin needed to accept when the set number could not be read.
    public var strongMargin = 0.20
    public var minPrintingConfidence = 0.70
    /// Never silently wrong above this price: flag instead.
    public var valueFloor = 5.0
    public init() {}
}

public struct MatchResult: Equatable, Sendable {
    public enum Reason: String, Sendable {
        case accepted, noCandidates, tooFar, closeSecond, numberMismatch, printingUnclear
    }
    public let cardId: String?
    public let printing: Printing?
    /// True when the user must pick; nothing is counted until they do.
    public let needsTap: Bool
    /// True when counted but marked for review at the end of the pack.
    public let flagged: Bool
    public let reason: Reason
    public let top5: [String]
}

public enum MatchDecider {
    public static func normalizeNumber(_ s: String) -> String {
        let head = s.split(separator: "/").first.map(String.init) ?? s
        let digits = head.trimmingCharacters(in: .whitespaces).drop(while: { $0 == "0" })
        return digits.isEmpty ? head.trimmingCharacters(in: .whitespaces) : String(digits).uppercased()
    }

    /// Auto-accept only when the image match is clearly ahead AND the printed set number agrees.
    /// Candidates must be sorted by ascending distance.
    public static func decide(candidates: [Candidate],
                              ocrNumber: String?,
                              printingGuess: PrintingGuess?,
                              prices: PriceTable,
                              thresholds t: MatchThresholds = MatchThresholds()) -> MatchResult {
        let top5 = candidates.prefix(5).map(\.cardId)
        guard let top = candidates.first else {
            return MatchResult(cardId: nil, printing: nil, needsTap: true, flagged: false, reason: .noCandidates, top5: [])
        }
        func tap(_ r: MatchResult.Reason) -> MatchResult {
            MatchResult(cardId: top.cardId, printing: nil, needsTap: true, flagged: false, reason: r, top5: top5)
        }
        if top.distance > t.maxDistance { return tap(.tooFar) }
        let margin = candidates.count > 1 ? candidates[1].distance - top.distance : .infinity

        if let ocr = ocrNumber, !ocr.isEmpty {
            if MatchDecider.normalizeNumber(ocr) != MatchDecider.normalizeNumber(top.number) { return tap(.numberMismatch) }
            if margin < t.minMargin { return tap(.closeSecond) }
        } else if margin < t.strongMargin {
            return tap(.closeSecond)
        }

        // The card is settled; now the printing.
        let matters = prices.printingMatters(cardId: top.cardId)
        var printing: Printing? = nil
        var flagged = false
        var reason = MatchResult.Reason.accepted
        if matters {
            if let g = printingGuess, g.confidence >= t.minPrintingConfidence {
                printing = g.printing
            } else {
                // Printing unclear: show a range, and flag when the range reaches above the value floor.
                reason = .printingUnclear
                if let q = prices.quote(cardId: top.cardId, printing: nil), q.high > t.valueFloor { flagged = true }
            }
        } else if let only = prices.printings(for: top.cardId).first {
            printing = only
        }
        return MatchResult(cardId: top.cardId, printing: printing, needsTap: false, flagged: flagged, reason: reason, top5: top5)
    }
}
