import CoreGraphics
import CoreImage
import Foundation
import PackRipCore
import Vision

struct CardDetection {
    let topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint
    /// Fraction of the frame the card's bounding box covers.
    let fill: Double
}

struct Recognition {
    let candidates: [Candidate]
    let ocrNumber: String?
    let printing: PrintingGuess?
    let crop: CGImage
}

/// Apple Vision does all the work on the phone: rectangle finding, feature-print matching, text reading.
enum CardRecognizer {
    private static let ciContext = CIContext()
    static let cropSize = CGSize(width: 480, height: 672)

    // MARK: Detection and crop

    static func detectCard(in image: CGImage) -> CardDetection? {
        let req = VNDetectRectanglesRequest()
        req.minimumAspectRatio = 0.55
        req.maximumAspectRatio = 0.85
        req.minimumSize = 0.25
        req.minimumConfidence = 0.6
        req.quadratureTolerance = 25
        req.maximumObservations = 1
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([req])) != nil, let o = req.results?.first else { return nil }
        return CardDetection(topLeft: o.topLeft, topRight: o.topRight, bottomLeft: o.bottomLeft, bottomRight: o.bottomRight,
                             fill: Double(o.boundingBox.width * o.boundingBox.height))
    }

    /// Flattens the detected card to an upright 480x672 portrait image.
    static func crop(_ image: CGImage, _ d: CardDetection) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        func p(_ n: CGPoint) -> CIVector { CIVector(x: n.x * w, y: n.y * h) }
        guard let f = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        f.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        f.setValue(p(d.topLeft), forKey: "inputTopLeft")
        f.setValue(p(d.topRight), forKey: "inputTopRight")
        f.setValue(p(d.bottomLeft), forKey: "inputBottomLeft")
        f.setValue(p(d.bottomRight), forKey: "inputBottomRight")
        guard let out = f.outputImage, let flat = ciContext.createCGImage(out, from: out.extent) else { return nil }
        // Vision may label the corners of a sideways card differently: force portrait.
        let portrait = flat.width > flat.height ? rotate(flat, quarterTurns: 1) : flat
        return resize(portrait ?? flat, to: cropSize)
    }

    static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    /// Rotates by 90 degrees x quarterTurns (clockwise).
    static func rotate(_ image: CGImage, quarterTurns: Int) -> CGImage? {
        let turns = ((quarterTurns % 4) + 4) % 4
        if turns == 0 { return image }
        let swap = turns % 2 == 1
        let w = swap ? image.height : image.width, h = swap ? image.width : image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.rotate(by: -CGFloat(turns) * .pi / 2)
        ctx.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
        return ctx.makeImage()
    }

    // MARK: Frame score (for picking the best frame of a held card)

    static func frameScore(crop: CGImage, fill: Double) -> Double {
        guard let g = PixelGrid(crop, width: 120, height: 168) else { return 0 }
        let l = g.luma
        return FrameScoring.score(sharpness: FrameScoring.laplacianVariance(luma: l, width: 120, height: 168),
                                  glare: FrameScoring.glareFraction(luma: l), fill: fill)
    }

    // MARK: Recognition

    /// Reads the printed set number (like 015/198) from the bottom strip of an upright card crop.
    static func readSetNumber(_ crop: CGImage) -> String? {
        let h = CGFloat(crop.height), w = CGFloat(crop.width)
        guard let strip = crop.cropping(to: CGRect(x: 0, y: h * 0.88, width: w, height: h * 0.12)) else { return nil }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(cgImage: strip, options: [:]).perform([req])) != nil else { return nil }
        let text = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        guard let m = text.range(of: #"\d{1,3}\s*/\s*\d{1,3}"#, options: .regularExpression) else { return nil }
        return String(text[m]).replacingOccurrences(of: " ", with: "")
    }

    @MainActor
    static func recognize(crop: CGImage, index: ReferenceIndex, prices: PriceTable,
                          thresholds: MatchThresholds) -> (Recognition, MatchResult)? {
        // Try upright, then upside down (a card held the other way up).
        var best: (Recognition, MatchResult)?
        for turns in [0, 2] {
            guard let img = rotate(crop, quarterTurns: turns), let fp = ReferenceIndex.featurePrint(img) else { continue }
            let cands = index.nearest(to: fp)
            guard !cands.isEmpty else { continue }
            let number = readSetNumber(img)
            var guess: PrintingGuess?
            if let top = cands.first, let obs = RegionShimmer(img) {
                guess = PrintingEstimator.guess(available: prices.printings(for: top.cardId), observed: obs,
                                                reference: index.shimmer(for: top.cardId))
            }
            let rec = Recognition(candidates: cands, ocrNumber: number, printing: guess, crop: img)
            let result = MatchDecider.decide(candidates: cands, ocrNumber: number, printingGuess: guess, prices: prices, thresholds: thresholds)
            if !result.needsTap { return (rec, result) }
            if best == nil || cands[0].distance < best!.0.candidates[0].distance { best = (rec, result) }
        }
        return best
    }
}
