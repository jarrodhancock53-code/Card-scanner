import Foundation

/// Pure pixel math for picking the best frame of a tracked card. Input is 8-bit luma, row-major.
public enum FrameScoring {
    /// Variance of the 4-neighbour Laplacian. Higher = sharper.
    public static func laplacianVariance(luma: [UInt8], width: Int, height: Int) -> Double {
        guard width >= 3, height >= 3, luma.count >= width * height else { return 0 }
        var sum = 0.0, sumSq = 0.0
        var n = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let v = 4 * Double(luma[i]) - Double(luma[i - 1]) - Double(luma[i + 1])
                    - Double(luma[i - width]) - Double(luma[i + width])
                sum += v; sumSq += v * v; n += 1
            }
        }
        let mean = sum / n
        return sumSq / n - mean * mean
    }

    /// Fraction of pixels that are blown out (glare).
    public static func glareFraction(luma: [UInt8], threshold: UInt8 = 250) -> Double {
        guard !luma.isEmpty else { return 0 }
        return Double(luma.reduce(0) { $0 + ($1 >= threshold ? 1 : 0) }) / Double(luma.count)
    }

    /// Combined score: sharp, little glare, card fills the frame. Weights are starting values to tune on real rips.
    public static func score(sharpness: Double, glare: Double, fill: Double) -> Double {
        let sharp = min(sharpness / 500.0, 1.0)
        return 0.55 * sharp + 0.25 * (1 - min(glare * 5, 1)) + 0.20 * min(max(fill, 0), 1)
    }
}
