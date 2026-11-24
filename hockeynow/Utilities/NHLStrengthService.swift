import Foundation

nonisolated struct ThreeStar: Identifiable, Equatable {
    let id: Int
    let name: String
    let team: String
    let position: String
    let line: String
    var headshot: String? = nil
}

nonisolated struct NextGameInfo: Equatable {
    let opponent: String
    let isHome: Bool
    let start: Date
}

actor NHLStrengthService {
    static let shared = NHLStrengthService()

    private var nhlIDs: [String: Int] = [:]
    private var lastFetch: [String: Date] = [:]
    private var lastResult: [String: GameStrength] = [:]
    private let minimumInterval: TimeInterval = 6
    private var starsCache: [String: [ThreeStar]] = [:]
    private var starsAttempt: [String: Date] = [:]
    private var nextCache: [String: (fetched: Date, info: NextGameInfo?)] = [:]

    static func canonical(_ abbreviation: String) -> String {
        let upper = abbreviation.uppercased()
        let aliases = ["UTAH": "UTA", "TB": "TBL", "NJ": "NJD", "SJ": "SJS", "LA": "LAK", "MON": "MTL"]
        return aliases[upper] ?? upper
    }

    func strength(espnGameID: String, awayAbbr: String, homeAbbr: String, start: Date?) async -> GameStrength? {
        if let last = lastFetch[espnGameID], Date().timeIntervalSince(last) < minimumInterval { return lastResult[espnGameID] }
        lastFetch[espnGameID] = Date()
        guard let nhlID = await resolveID(espnGameID: espnGameID, awayAbbr: awayAbbr, homeAbbr: homeAbbr, start: start) else {
            NSLog("[HockeyNow] strength: no NHL game found for %@ @ %@", awayAbbr, homeAbbr)
            return lastResult[espnGameID]
        }
        guard
              let url = URL(string: "https://api-web.nhle.com/v1/gamecenter/\(nhlID)/play-by-play"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plays = root["plays"] as? [[String: Any]] else { return lastResult[espnGameID] }
        for play in plays.reversed() {
            let raw = play["situationCode"]
            let code = (raw as? String) ?? (raw as? Int).map { String(format: "%04d", $0) }
            if let code, let strength = GameStrength(situationCode: code) {
                lastResult[espnGameID] = strength
                return strength
            }
        }
        return lastResult[espnGameID]
    }

    func threeStars(espnGameID: String, awayAbbr: String, homeAbbr: String, start: Date?) async -> [ThreeStar] {
        if let cached = starsCache[espnGameID], !cached.isEmpty { return cached }
        if let last = starsAttempt[espnGameID], Date().timeIntervalSince(last) < 30 { return [] }
        starsAttempt[espnGameID] = Date()
        guard let nhlID = await resolveID(espnGameID: espnGameID, awayAbbr: awayAbbr, homeAbbr: homeAbbr, start: start),
              let url = URL(string: "https://api-web.nhle.com/v1/gamecenter/\(nhlID)/landing"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let summary = root["summary"] as? [String: Any]
        guard let items = (root["threeStars"] as? [[String: Any]]) ?? (summary?["threeStars"] as? [[String: Any]]) else { return [] }
        func number(_ any: Any?) -> Double? {
            if let n = any as? NSNumber { return n.doubleValue }
            if let s = any as? String { return Double(s) }
            return nil
        }
        var stars: [ThreeStar] = []
        for (index, item) in items.enumerated() {
            let star = (item["star"] as? Int) ?? index + 1
            let name = ((item["name"] as? [String: Any])?["default"] as? String) ?? (item["name"] as? String) ?? ""
            guard !name.isEmpty else { continue }
            let position = (item["position"] as? String) ?? (item["positionCode"] as? String) ?? ""
            var line = ""
            if position == "G" {
                if let sv = number(item["savePctg"]) { line = String(format: "%.3f", sv).replacingOccurrences(of: "0.", with: ".") + " SV%" }
            } else if let g = number(item["goals"]), let a = number(item["assists"]) {
                line = "\(Int(g))G \(Int(a))A"
            } else if let p = number(item["points"]) {
                line = "\(Int(p))P"
            }
            stars.append(ThreeStar(id: star, name: name, team: (item["teamAbbrev"] as? String) ?? "", position: position, line: line,
                                  headshot: (item["headshot"] as? String).flatMap { $0.isEmpty ? nil : $0 }))
        }
        stars.sort { $0.id < $1.id }
        if !stars.isEmpty { starsCache[espnGameID] = stars }
        return stars
    }

    private var shotCache: [String: (fetched: Date, data: ShotMapData)] = [:]

    func shotMap(espnGameID: String, awayAbbr: String, homeAbbr: String, start: Date?) async -> ShotMapData? {
        if let cached = shotCache[espnGameID], Date().timeIntervalSince(cached.fetched) < 12 { return cached.data }
        guard let nhlID = await resolveID(espnGameID: espnGameID, awayAbbr: awayAbbr, homeAbbr: homeAbbr, start: start),
              let url = URL(string: "https://api-web.nhle.com/v1/gamecenter/\(nhlID)/play-by-play"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plays = root["plays"] as? [[String: Any]] else { return shotCache[espnGameID]?.data }
        let homeID = (root["homeTeam"] as? [String: Any])?["id"] as? Int
        let awayID = (root["awayTeam"] as? [String: Any])?["id"] as? Int
        guard let homeID, let awayID else { return shotCache[espnGameID]?.data }
        func number(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
        var shots: [ShotEvent] = []
        for (index, play) in plays.enumerated() {
            let type = (play["typeDescKey"] as? String) ?? ""
            let kind: ShotEvent.Kind
            switch type {
            case "goal": kind = .goal
            case "shot-on-goal": kind = .shot
            case "missed-shot": kind = .miss
            default: continue
            }
            guard let details = play["details"] as? [String: Any], let rawX = number(details["xCoord"]), let rawY = number(details["yCoord"]),
                  let owner = details["eventOwnerTeamId"] as? Int else { continue }
            let isHome = owner == homeID
            if !isHome && owner != awayID { continue }
            let homeDefendsLeft = ((play["homeTeamDefendingSide"] as? String) ?? "") != "right"
            let attacksRight = (isHome == homeDefendsLeft)
            let x = attacksRight ? rawX : -rawX, y = attacksRight ? rawY : -rawY
            let distance = hypot(89 - x, y)
            let angle = abs(atan2(abs(y), max(89 - x, 0.5))) * 180 / .pi
            let xg = ShotEvent.expectedGoal(distance: distance, angle: angle, isMiss: kind == .miss)
            let period = ((play["periodDescriptor"] as? [String: Any])?["number"] as? Int) ?? 0
            shots.append(ShotEvent(id: (play["eventId"] as? Int) ?? index, x: x, y: y, isHome: isHome, kind: kind, xg: xg,
                                   shotType: (details["shotType"] as? String) ?? "", period: period, clock: (play["timeInPeriod"] as? String) ?? ""))
        }
        let result = ShotMapData(shots: shots, awayAbbr: awayAbbr, homeAbbr: homeAbbr)
        shotCache[espnGameID] = (Date(), result)
        return result
    }

    func nextGame(for team: String) async -> NextGameInfo? {
        let abbr = Self.canonical(team)
        if let cached = nextCache[abbr], Date().timeIntervalSince(cached.fetched) < 900,
           cached.info == nil || (cached.info?.start ?? .distantPast) > Date() { return cached.info }
        guard let url = URL(string: "https://api-web.nhle.com/v1/club-schedule-season/\(abbr)/now"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let games = root["games"] as? [[String: Any]] else { return nextCache[abbr]?.info }
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()
        var best: NextGameInfo?
        for game in games {
            guard let text = game["startTimeUTC"] as? String, let start = plain.date(from: text) ?? fractional.date(from: text), start > now else { continue }
            let state = (game["gameState"] as? String) ?? "FUT"
            if state == "FINAL" || state == "OFF" { continue }
            guard let away = (game["awayTeam"] as? [String: Any])?["abbrev"] as? String,
                  let home = (game["homeTeam"] as? [String: Any])?["abbrev"] as? String else { continue }
            let isHome = Self.canonical(home) == abbr
            if !isHome && Self.canonical(away) != abbr { continue }
            if best == nil || start < best!.start { best = NextGameInfo(opponent: isHome ? away : home, isHome: isHome, start: start) }
        }
        nextCache[abbr] = (Date(), best)
        return best
    }

    func resolveID(espnGameID: String, awayAbbr: String, homeAbbr: String, start: Date?) async -> Int? {
        if let cached = nhlIDs[espnGameID] { return cached }
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = eastern
        formatter.timeZone = eastern.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let base = start ?? Date()
        var days = [base]
        if let prev = eastern.date(byAdding: .day, value: -1, to: base) { days.append(prev) }
        for day in days {
            guard let url = URL(string: "https://api-web.nhle.com/v1/score/\(formatter.string(from: day))"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let id = Self.findGame(in: json, away: awayAbbr, home: homeAbbr) {
                nhlIDs[espnGameID] = id
                return id
            }
        }
        return nil
    }

    private static func findGame(in node: Any, away: String, home: String) -> Int? {
        if let dict = node as? [String: Any] {
            if let id = dict["id"] as? Int,
               let a = (dict["awayTeam"] as? [String: Any])?["abbrev"] as? String,
               let h = (dict["homeTeam"] as? [String: Any])?["abbrev"] as? String,
               NHLStrengthService.canonical(a) == NHLStrengthService.canonical(away), NHLStrengthService.canonical(h) == NHLStrengthService.canonical(home) { return id }
            for value in dict.values { if let found = findGame(in: value, away: away, home: home) { return found } }
        } else if let array = node as? [Any] {
            for value in array { if let found = findGame(in: value, away: away, home: home) { return found } }
        }
        return nil
    }
}

nonisolated struct ShotEvent: Identifiable, Equatable {
    enum Kind { case goal, shot, miss }
    let id: Int
    let x: Double
    let y: Double
    let isHome: Bool
    let kind: Kind
    let xg: Double
    let shotType: String
    let period: Int
    let clock: String

    static func expectedGoal(distance: Double, angle: Double, isMiss: Bool) -> Double {
        let p = 1 / (1 + exp(1.0 + 0.06 * distance + 0.012 * angle))
        return isMiss ? p * 0.7 : p
    }
}

nonisolated struct ShotMapData: Equatable {
    var shots: [ShotEvent]
    let awayAbbr: String
    let homeAbbr: String

    func shots(home: Bool) -> [ShotEvent] { shots.filter { $0.isHome == home } }
    func expected(home: Bool) -> Double { shots(home: home).reduce(0) { $0 + $1.xg } }
    func goals(home: Bool) -> Int { shots(home: home).filter { $0.kind == .goal }.count }
    func onGoal(home: Bool) -> Int { shots(home: home).filter { $0.kind != .miss }.count }
}
