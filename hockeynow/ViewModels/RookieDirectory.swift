import Foundation
import Combine

@MainActor
final class RookieDirectory: ObservableObject {
    @Published private(set) var rookieIDs = Set<String>()
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    private var loadedDayKey = ""

    func load(teamIDs: [String]) async {
        let ids = Array(Set(teamIDs))
        guard !ids.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dayKey = formatter.string(from: Date())
        guard loadedDayKey != dayKey else { return }

        if let saved = FinalGameStore.load([String].self, kind: "rookies", id: dayKey), !saved.isEmpty {
            rookieIDs = Set(saved)
            hasLoaded = true
            loadedDayKey = dayKey
            return
        }

        isLoading = true
        var found = Set<String>()
        var gotAnyRoster = false
        await withTaskGroup(of: [String]?.self) { group in
            for teamID in ids {
                group.addTask { await Self.fetchRookies(teamID: teamID) }
            }
            for await result in group {
                if let result { gotAnyRoster = true; found.formUnion(result) }
            }
        }
        isLoading = false
        hasLoaded = true
        guard gotAnyRoster else { return }
        rookieIDs = found
        loadedDayKey = dayKey
        if !found.isEmpty { FinalGameStore.save(Array(found), kind: "rookies", id: dayKey) }
    }

    nonisolated private static func fetchRookies(teamID: String) async -> [String]? {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/teams/\(teamID)/roster") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(RosterResponse.self, from: data)
            var rookies: [String] = []
            func visit(_ entries: [RosterEntry]) {
                for entry in entries {
                    if let id = entry.playerID, entry.isRookie { rookies.append(id) }
                    visit(entry.items ?? [])
                }
            }
            visit(decoded.athletes ?? [])
            return rookies
        } catch {
            return nil
        }
    }
}

private struct RosterResponse: Decodable { let athletes: [RosterEntry]? }

private struct RosterEntry: Decodable {
    let playerID: String?
    let items: [RosterEntry]?
    let experienceYears: Int?
    let experienceText: String?

    nonisolated var isRookie: Bool {
        if let experienceYears { return experienceYears == 0 }
        return experienceText?.lowercased() == "rookie"
    }

    enum CodingKeys: String, CodingKey { case id, items, experience }
    struct Experience: Decodable {
        let years: Int?
        let displayValue: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decodeIfPresent(String.self, forKey: .id) {
            playerID = text
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .id) {
            playerID = String(number)
        } else {
            playerID = nil
        }
        items = try? container.decodeIfPresent([RosterEntry].self, forKey: .items)
        let experience = try? container.decodeIfPresent(Experience.self, forKey: .experience)
        experienceYears = experience?.years
        experienceText = experience?.displayValue
    }
}
