import Foundation
import Combine

// MARK: - Per-team alert profiles
// Every followed team can have its own mix of alerts (goals only for one team, finals only for another, a team muted for
// the night). Profiles are stored as JSON in UserDefaults. A team with no saved profile uses the defaults below.
enum AlertKind: String, CaseIterable, Identifiable {
    case goals, periods, finals, gameDay, trades, injuries, popouts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .goals: return "Goals"
        case .periods: return "Periods"
        case .finals: return "Finals"
        case .gameDay: return "Game day"
        case .trades: return "Trades"
        case .injuries: return "Injuries"
        case .popouts: return "Notch"
        }
    }
}

struct TeamAlertProfile: Codable, Equatable {
    var muted = false
    var goals = true
    var periods = true
    var finals = true
    var gameDay = true
    var trades = true
    var injuries = true
    var popouts = true

    init() {}
    // Older saved profiles may lack newer switches; missing ones fall back to their defaults instead of discarding everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        goals = try c.decodeIfPresent(Bool.self, forKey: .goals) ?? true
        periods = try c.decodeIfPresent(Bool.self, forKey: .periods) ?? true
        finals = try c.decodeIfPresent(Bool.self, forKey: .finals) ?? true
        gameDay = try c.decodeIfPresent(Bool.self, forKey: .gameDay) ?? true
        trades = try c.decodeIfPresent(Bool.self, forKey: .trades) ?? true
        injuries = try c.decodeIfPresent(Bool.self, forKey: .injuries) ?? true
        popouts = try c.decodeIfPresent(Bool.self, forKey: .popouts) ?? true
    }

    func allows(_ kind: AlertKind) -> Bool {
        if muted { return false }
        switch kind {
        case .goals: return goals
        case .periods: return periods
        case .finals: return finals
        case .gameDay: return gameDay
        case .trades: return trades
        case .injuries: return injuries
        case .popouts: return popouts
        }
    }

    mutating func set(_ kind: AlertKind, _ value: Bool) {
        switch kind {
        case .goals: goals = value
        case .periods: periods = value
        case .finals: finals = value
        case .gameDay: gameDay = value
        case .trades: trades = value
        case .injuries: injuries = value
        case .popouts: popouts = value
        }
    }
}

enum AlertProfiles {
    static let defaultsKey = "team_alert_profiles"

    static func all() -> [String: TeamAlertProfile] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: TeamAlertProfile].self, from: data) else { return [:] }
        return decoded
    }

    static func profile(for team: String) -> TeamAlertProfile { all()[team] ?? TeamAlertProfile() }

    static func save(_ profile: TeamAlertProfile, for team: String) {
        var current = all()
        if profile == TeamAlertProfile() { current.removeValue(forKey: team) } else { current[team] = profile }
        if let data = try? JSONEncoder().encode(current) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    // The followed teams playing in this game.
    static func followedTeams(in away: String, _ home: String) -> [String] {
        hockeyNowFavouriteTeams().filter { $0 == away || $0 == home }
    }

    // Does any followed team in this game want this kind of alert? Games with no followed team return `nil`
    // so each caller can apply its own rule for strangers (goals respect "my team only"; the rest stay quiet).
    static func followedTeamsAllow(_ kind: AlertKind, away: String, home: String) -> Bool? {
        let teams = followedTeams(in: away, home)
        if teams.isEmpty { return nil }
        let profiles = all()
        return teams.contains { (profiles[$0] ?? TeamAlertProfile()).allows(kind) }
    }

    // Followed teams that want this kind of alert, for team-based alerts such as trades and injuries.
    static func teamsWanting(_ kind: AlertKind) -> Set<String> {
        let profiles = all()
        return Set(hockeyNowFavouriteTeams().filter { (profiles[$0] ?? TeamAlertProfile()).allows(kind) })
    }
}
