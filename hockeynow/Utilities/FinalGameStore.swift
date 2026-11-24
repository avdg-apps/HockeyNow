import Foundation

// MARK: - Saved game details
// Everything the app needs to redraw a finished game without asking ESPN again.
struct SavedGameDetails: Codable {
    var scoringPlays: [ESPNPlay]
    var teamStats: [String: [ESPNEvent.ESPNCompetitor.ESPNStatistic]]
    var penalties: [ESPNPenaltyItem]
    var winProbability: [Double]
    var playByPlay: [ESPNPlay]? = nil
    var lineups: [ESPNGameSummary.ESPNBoxscore.ESPNBoxscorePlayerGroup]? = nil
}

// MARK: - On-disk store for finished games
// A finished game never changes, so once it has been downloaded it is saved under Application Support and read back on
// later launches instead of being fetched again. That makes launch much faster and saves network and energy.
// Bump `schemaVersion` if the saved shapes ever change; old files are then simply ignored.
enum FinalGameStore {
    private nonisolated static let schemaVersion = "v1"

    private nonisolated static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("HockeyNow/Saved-\(schemaVersion)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private nonisolated static func folder(_ kind: String) -> URL {
        let url = root.appendingPathComponent(kind, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private nonisolated static func fileURL(kind: String, id: String) -> URL {
        // IDs are numeric, but strip anything unexpected so they can never escape the folder.
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return folder(kind).appendingPathComponent("\(safe).json")
    }

    nonisolated static func save<T: Encodable>(_ value: T, kind: String, id: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL(kind: kind, id: id), options: .atomic)
    }

    nonisolated static func load<T: Decodable>(_ type: T.Type, kind: String, id: String) -> T? {
        guard let data = try? Data(contentsOf: fileURL(kind: kind, id: id)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // Whole past months of the schedule are stored as the raw ESPN response.
    nonisolated static func saveMonth(_ data: Data, key: String) { try? data.write(to: fileURL(kind: "months", id: key), options: .atomic) }
    nonisolated static func loadMonth(key: String) -> Data? { try? Data(contentsOf: fileURL(kind: "months", id: key)) }

    nonisolated static func clearAll() { try? FileManager.default.removeItem(at: root) }
}
