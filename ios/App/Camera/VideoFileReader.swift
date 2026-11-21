import AVFoundation
import CoreGraphics

/// Reads frames from a saved video at a fixed rate, upright, for the "upload a video" mode.
enum VideoFileReader {
    static func frames(from url: URL, perSecond: Double = 8,
                       handler: (CGImage, TimeInterval) async -> Void,
                       progress: (Double) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { return }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1920, height: 1920)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        var t = 0.0
        while t < duration {
            if Task.isCancelled { return }
            if let r = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)) {
                await handler(r.image, t)
            }
            progress(min(t / duration, 1))
            t += 1.0 / perSecond
        }
        progress(1)
    }
}
