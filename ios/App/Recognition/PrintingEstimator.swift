import Foundation
import PackRipCore

/// Guesses normal / holo / reverse holo by comparing the photo with the flat catalog image of the same card.
/// This is a heuristic with starting thresholds. It has not been calibrated on real photos yet:
/// run the 20-pack test (tools/validate.py) and tune `threshold` and `slope` from the result.
enum PrintingEstimator {
    static var threshold = 0.05
    static var slope = 5.0

    static func guess(available: [Printing], observed: RegionShimmer, reference: RegionShimmer?) -> PrintingGuess? {
        if available.count == 1, let only = available.first { return PrintingGuess(printing: only, confidence: 1.0) }
        guard let reference, available.count > 1 else { return nil }
        let artDelta = observed.art - reference.art
        let textDelta = observed.text - reference.text

        let hasHolo = available.contains(.holo), hasReverse = available.contains(.reverseHolo)
        let hasNormal = available.contains(.normal)
        let foil: Printing
        let evidence: Double
        if hasReverse && hasNormal {
            foil = .reverseHolo; evidence = textDelta
        } else if hasHolo && hasNormal {
            foil = .holo; evidence = artDelta
        } else if hasHolo && hasReverse {
            // Holo shimmers in the art, reverse in the text area.
            let isHolo = artDelta >= textDelta
            return PrintingGuess(printing: isHolo ? .holo : .reverseHolo,
                                 confidence: min(0.95, 0.5 + abs(artDelta - textDelta) * slope))
        } else {
            return nil
        }
        let isFoil = evidence > threshold
        let confidence = min(0.95, 0.5 + abs(evidence - threshold) * slope)
        return PrintingGuess(printing: isFoil ? foil : .normal, confidence: confidence)
    }
}
