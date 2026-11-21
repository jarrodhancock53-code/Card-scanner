import Foundation

public enum CSVExport {
    static func field(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func csv(for s: PackSession) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["pack,set,card_id,name,number,rarity,printing,value,value_high,flagged,corrected,captured_at"]
        for (i, pack) in s.packs.enumerated() {
            for c in pack.cards {
                lines.append([
                    String(i + 1), pack.setId, c.cardId, field(c.name), c.number, field(c.rarity),
                    c.printing?.rawValue ?? "unknown", String(format: "%.2f", c.value), String(format: "%.2f", c.valueHigh),
                    c.flagged ? "yes" : "no", c.corrected ? "yes" : "no", iso.string(from: c.capturedAt),
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
