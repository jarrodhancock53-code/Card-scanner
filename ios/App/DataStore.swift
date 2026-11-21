import Foundation
import PackRipCore

/// Catalog and prices, read from the app's Documents/data folder (after an update) or the bundled copy.
@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var sets: [SetInfo] = []
    @Published private(set) var prices = PriceTable(files: [])
    @Published private(set) var loadError: String?
    private var catalogs: [String: [CatalogCard]] = [:]

    static var documentsData: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("data", isDirectory: true)
    }

    private var root: URL? {
        let docs = Self.documentsData
        if FileManager.default.fileExists(atPath: docs.appendingPathComponent("sets.json").path) { return docs }
        return Bundle.main.url(forResource: "data", withExtension: nil)
    }

    func load() {
        loadError = nil
        guard let root else { loadError = "No card data found. Run tools/sync.py, then rebuild or use Settings > Update data."; return }
        do {
            let dec = JSONDecoder()
            let sets = try dec.decode([SetInfo].self, from: Data(contentsOf: root.appendingPathComponent("sets.json")))
            var cats: [String: [CatalogCard]] = [:]
            var files: [PriceFile] = []
            for s in sets {
                cats[s.id] = try dec.decode([CatalogCard].self, from: Data(contentsOf: root.appendingPathComponent("catalog/\(s.id).json")))
                files.append(try dec.decode(PriceFile.self, from: Data(contentsOf: root.appendingPathComponent("prices/\(s.id).json"))))
            }
            self.sets = sets.sorted { $0.name < $1.name }
            self.catalogs = cats
            self.prices = PriceTable(files: files)
        } catch {
            loadError = "Could not read card data: \(error.localizedDescription)"
        }
    }

    func cards(in setId: String) -> [CatalogCard] { catalogs[setId] ?? [] }
    func card(id: String) -> CatalogCard? { catalogs[String(id.split(separator: "-").first ?? "")]?.first { $0.id == id } }

    /// Downloads sets.json, catalog and prices from a folder URL (e.g. a GitHub Pages site fed by the daily sync).
    func update(from base: URL) async throws {
        let fm = FileManager.default
        let dest = Self.documentsData
        try fm.createDirectory(at: dest.appendingPathComponent("catalog"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dest.appendingPathComponent("prices"), withIntermediateDirectories: true)
        func fetch(_ rel: String) async throws -> Data {
            let (data, resp) = try await URLSession.shared.data(from: base.appendingPathComponent(rel))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
        let setsData = try await fetch("sets.json")
        let sets = try JSONDecoder().decode([SetInfo].self, from: setsData)
        for s in sets {
            try await fetch("catalog/\(s.id).json").write(to: dest.appendingPathComponent("catalog/\(s.id).json"))
            try await fetch("prices/\(s.id).json").write(to: dest.appendingPathComponent("prices/\(s.id).json"))
        }
        try setsData.write(to: dest.appendingPathComponent("sets.json"))
        load()
    }
}
