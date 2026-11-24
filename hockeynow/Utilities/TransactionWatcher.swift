import Foundation
import UserNotifications

// MARK: - Trade, signing and injury alerts for followed teams
// Polls ESPN's league transactions and injury lists about every 20 minutes. The first pass only records what already
// exists, so nothing old is announced. All JSON is read loosely because these feeds are unofficial.
@MainActor
final class TransactionWatcher {
    static let shared = TransactionWatcher()
    private init() {}

    private let seenKey = "watcher_seen_transaction_ids"
    private let injuryKey = "watcher_injury_snapshot"
    private var lastRun: Date?

    private func abbreviation(forTeamName name: String) -> String? {
        nhlAllTeams.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.abbreviation
    }

    func runIfDue() async {
        guard UserDefaults.standard.bool(forKey: "notifications_enabled_toggle") else { return }
        if let lastRun, Date().timeIntervalSince(lastRun) < 20 * 60 { return }
        lastRun = Date()
        let tradeTeams = AlertProfiles.teamsWanting(.trades)
        let injuryTeams = AlertProfiles.teamsWanting(.injuries)
        guard !tradeTeams.isEmpty || !injuryTeams.isEmpty else { return }
        if !tradeTeams.isEmpty { await checkTransactions(teams: tradeTeams) }
        if !injuryTeams.isEmpty { await checkInjuries(teams: injuryTeams) }
    }

    // MARK: Transactions
    private func checkTransactions(teams: Set<String>) async {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/transactions"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["transactions"] as? [[String: Any]] else { return }
        var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        let firstRun = UserDefaults.standard.object(forKey: seenKey) == nil
        var fresh: [(id: String, team: String, text: String)] = []
        for item in items {
            let text = (item["description"] as? String) ?? (item["text"] as? String) ?? ""
            guard !text.isEmpty else { continue }
            let team = item["team"] as? [String: Any]
            let name = (team?["displayName"] as? String) ?? (team?["name"] as? String) ?? ""
            let abbr = (team?["abbreviation"] as? String).map { NHLStrengthService.canonical($0) } ?? abbreviation(forTeamName: name) ?? ""
            let id = "\(abbr)|\((item["date"] as? String) ?? "")|\(text)"
            if seen.contains(id) { continue }
            seen.insert(id)
            if !firstRun, teams.contains(abbr) { fresh.append((id, abbr, text)) }
        }
        UserDefaults.standard.set(Array(seen.suffix(600)), forKey: seenKey)
        for entry in fresh.prefix(4) {
            NotificationManager.post(title: "\(entry.team) transaction", body: entry.text, identifier: "txn-\(abs(entry.id.hashValue))", url: nil)
        }
    }

    // MARK: Injuries
    private func checkInjuries(teams: Set<String>) async {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/injuries"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clubs = root["injuries"] as? [[String: Any]] else { return }
        var snapshot: [String: String] = [:]
        for club in clubs {
            guard let teamName = club["displayName"] as? String, let abbr = abbreviation(forTeamName: teamName) else { continue }
            for item in (club["injuries"] as? [[String: Any]]) ?? [] {
                let player = ((item["athlete"] as? [String: Any])?["displayName"] as? String) ?? ""
                guard !player.isEmpty else { continue }
                snapshot["\(abbr)|\(player)"] = (item["status"] as? String) ?? "Out"
            }
        }
        guard !snapshot.isEmpty else { return }
        let previous = UserDefaults.standard.dictionary(forKey: injuryKey) as? [String: String]
        UserDefaults.standard.set(snapshot, forKey: injuryKey)
        guard let previous else { return }       // first pass: just remember the list
        var sent = 0
        for (key, status) in snapshot where previous[key] != status {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, teams.contains(parts[0]), sent < 4 else { continue }
            sent += 1
            NotificationManager.post(title: "\(parts[0]) injury update", body: "\(parts[1]): \(status)", identifier: "inj-\(abs(key.hashValue))", url: nil)
        }
        for (key, _) in previous where snapshot[key] == nil {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, teams.contains(parts[0]), sent < 4 else { continue }
            sent += 1
            NotificationManager.post(title: "\(parts[0]) injury update", body: "\(parts[1]) is off the injury report.", identifier: "inj-\(abs(key.hashValue))", url: nil)
        }
    }
}
