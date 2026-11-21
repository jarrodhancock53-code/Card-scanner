import CoreGraphics
import Foundation
import ImageIO

/// Downloads reference card images once and keeps them in the Caches folder.
enum ImageCache {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("cards", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func load(_ urlString: String?, key: String) async -> CGImage? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        let file = dir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".img")
        if let data = try? Data(contentsOf: file), let img = decode(data) { return img }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let img = decode(data) else { return nil }
            try? data.write(to: file)
            return img
        } catch { return nil }
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
