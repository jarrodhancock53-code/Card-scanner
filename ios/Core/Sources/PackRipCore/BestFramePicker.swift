import Foundation

/// Watches a stream of frames and emits the single best frame for each card that passes through the view.
/// Feed it every sampled frame: `frame` is nil when no card is in view. It emits once the card has been
/// gone for `absentGap` seconds, or has been held longer than `maxHold` seconds.
public struct BestFramePicker<Frame> {
    public var absentGap: TimeInterval
    public var maxHold: TimeInterval
    public var minFrames: Int

    private var best: Frame?
    private var bestScore = -Double.infinity
    private var frames = 0
    private var startedAt: TimeInterval = 0
    private var lastSeen: TimeInterval = 0

    public init(absentGap: TimeInterval = 0.5, maxHold: TimeInterval = 4.0, minFrames: Int = 3) {
        self.absentGap = absentGap; self.maxHold = maxHold; self.minFrames = minFrames
    }

    public mutating func add(frame: Frame?, score: Double, at t: TimeInterval) -> Frame? {
        if let frame {
            if frames == 0 { startedAt = t }
            frames += 1
            lastSeen = t
            if score > bestScore { best = frame; bestScore = score }
            if t - startedAt >= maxHold { return emit() }
            return nil
        }
        guard frames > 0, t - lastSeen >= absentGap else { return nil }
        return emit()
    }

    /// Call at the end of a video to get the last card, if any.
    public mutating func flush() -> Frame? { frames > 0 ? emit() : nil }

    private mutating func emit() -> Frame? {
        defer { best = nil; bestScore = -.infinity; frames = 0 }
        return frames >= minFrames ? best : nil
    }
}
