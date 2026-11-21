import CoreGraphics
import Foundation
import PackRipCore

/// A small RGBA bitmap of an image, used for cheap luma / colour statistics.
struct PixelGrid {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    init?(_ image: CGImage, width: Int, height: Int) {
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        self.width = width; self.height = height; self.rgba = buf
    }

    var luma: [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Double(rgba[i * 4]), g = Double(rgba[i * 4 + 1]), b = Double(rgba[i * 4 + 2])
            out[i] = UInt8(max(0, min(255, 0.299 * r + 0.587 * g + 0.114 * b)))
        }
        return out
    }

    /// Standard deviation of (saturation + half of brightness spread) inside a region given in 0...1 fractions.
    /// Foil shimmer raises both, flat printed card stock does not.
    func shimmer(x0: Double, y0: Double, x1: Double, y1: Double) -> Double {
        let xs = Int(x0 * Double(width)), xe = max(xs + 1, Int(x1 * Double(width)))
        let ys = Int(y0 * Double(height)), ye = max(ys + 1, Int(y1 * Double(height)))
        var sat: [Double] = [], val: [Double] = []
        for y in ys..<min(ye, height) {
            for x in xs..<min(xe, width) {
                let i = (y * width + x) * 4
                let r = Double(rgba[i]) / 255, g = Double(rgba[i + 1]) / 255, b = Double(rgba[i + 2]) / 255
                let mx = max(r, g, b), mn = min(r, g, b)
                sat.append(mx == 0 ? 0 : (mx - mn) / mx)
                val.append(mx)
            }
        }
        return Self.std(sat) + 0.5 * Self.std(val)
    }

    private static func std(_ v: [Double]) -> Double {
        guard v.count > 1 else { return 0 }
        let m = v.reduce(0, +) / Double(v.count)
        return (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)).squareRoot()
    }
}

/// Shimmer measured in the two regions that tell printings apart.
struct RegionShimmer {
    /// Artwork window: holofoil cards shimmer here.
    let art: Double
    /// Lower text/border area: reverse holo cards shimmer here, regular holos do not.
    let text: Double

    init(art: Double, text: Double) { self.art = art; self.text = text }

    init?(_ image: CGImage) {
        guard let g = PixelGrid(image, width: 96, height: 134) else { return nil }
        art = g.shimmer(x0: 0.08, y0: 0.12, x1: 0.92, y1: 0.50)
        text = g.shimmer(x0: 0.08, y0: 0.58, x1: 0.92, y1: 0.92)
    }
}
