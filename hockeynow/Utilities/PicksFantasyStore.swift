import Foundation
import Combine

struct PinnedPlayer: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let team: String
    let position: String
    let headshot: String?
}

struct GamePick: Codable, Equatable {
    let gameID: String
    let pick: String
    let away: String
    let home: String
    let date: Date
}

struct PickRecord {
    var wins = 0
    var losses = 0
    var streak = 0
    var total: Int { wins + losses }
    var percentage: Int { total == 0 ? 0 : Int((Double(wins) / Double(total) * 100).rounded()) }
}

@MainActor
final class PicksFantasyStore: ObservableObject {
    static let shared = PicksFantasyStore()
    private let pinnedKey = "fantasy_pinned_players"
    private let picksKey = "pickem_picks"

    @Published private(set) var pinned: [PinnedPlayer] = []
    @Published private(set) var picks: [String: GamePick] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: pinnedKey), let list = try? JSONDecoder().decode([PinnedPlayer].self, from: data) { pinned = list }
        if let data = UserDefaults.standard.data(forKey: picksKey), let map = try? JSONDecoder().decode([String: GamePick].self, from: data) { picks = map }
    }

    func isPinned(_ id: String) -> Bool { pinned.contains { $0.id == id } }

    func pin(_ player: PinnedPlayer) {
        guard !isPinned(player.id), pinned.count < 12 else { return }
        pinned.append(player)
        save()
    }

    func unpin(_ id: String) { pinned.removeAll { $0.id == id }; save() }

    func choose(_ team: String, in game: ESPNEvent) {
        guard game.abstractState == "Preview", let away = game.awayTeam?.team.threeLetterAbbreviation,
              let home = game.homeTeam?.team.threeLetterAbbreviation else { return }
        if picks[game.id]?.pick == team { picks.removeValue(forKey: game.id) }
        else { picks[game.id] = GamePick(gameID: game.id, pick: team, away: away, home: home, date: game.systemCalendarDate ?? Date()) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pinned) { UserDefaults.standard.set(data, forKey: pinnedKey) }
        if let data = try? JSONEncoder().encode(picks) { UserDefaults.standard.set(data, forKey: picksKey) }
    }

    static func winner(of game: ESPNEvent) -> String? {
        guard game.abstractState == "Final", let away = game.awayTeam, let home = game.homeTeam,
              let a = Int(away.score), let h = Int(home.score), a != h else { return nil }
        return a > h ? away.team.threeLetterAbbreviation : home.team.threeLetterAbbreviation
    }

    func gradedPicks(finals: [ESPNEvent]) -> [(pick: GamePick, correct: Bool)] {
        var winners: [String: String] = [:]
        for game in finals { if let w = Self.winner(of: game) { winners[game.id] = w } }
        return picks.values.sorted { $0.date < $1.date }.compactMap { pick in
            winners[pick.gameID].map { (pick, $0 == pick.pick) }
        }
    }

    func record(finals: [ESPNEvent]) -> PickRecord {
        var record = PickRecord()
        for entry in gradedPicks(finals: finals) {
            if entry.correct { record.wins += 1; record.streak = max(record.streak, 0) + 1 }
            else { record.losses += 1; record.streak = min(record.streak, 0) - 1 }
        }
        return record
    }
}

enum FantasyScoring {
    static let goal = 3.0, assist = 2.0, shot = 0.5
    static let summary = "Goal 3 · Assist 2 · Shot on goal 0.5"

    struct Line { var goals = 0; var assists = 0; var shots = 0
        var points: Double { Double(goals) * FantasyScoring.goal + Double(assists) * FantasyScoring.assist + Double(shots) * FantasyScoring.shot }
    }

    static func line(for playerID: String, in groups: [ESPNGameSummary.ESPNBoxscore.ESPNBoxscorePlayerGroup]) -> Line? {
        for group in groups {
            for category in group.statistics ?? [] {
                guard let athletes = category.athletes else { continue }
                for entry in athletes where entry.athlete?.id == playerID {
                    guard let stats = entry.stats else { continue }
                    func value(keys: [String], labels: [String]) -> Int {
                        if let names = category.keys {
                            for key in keys { if let i = names.firstIndex(where: { $0.lowercased() == key.lowercased() }), stats.indices.contains(i), let n = Int(stats[i]) { return n } }
                        }
                        if let names = category.labels {
                            for label in labels { if let i = names.firstIndex(where: { $0.uppercased() == label.uppercased() }), stats.indices.contains(i), let n = Int(stats[i]) { return n } }
                        }
                        return 0
                    }
                    return Line(goals: value(keys: ["goals"], labels: ["G"]), assists: value(keys: ["assists"], labels: ["A"]),
                                shots: value(keys: ["shotsTotal", "shots", "shotsOnGoal"], labels: ["S", "SOG"]))
                }
            }
        }
        return nil
    }
}
