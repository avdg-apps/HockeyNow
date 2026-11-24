import AppIntents
import Foundation

@MainActor
enum HockeyNowBridge {
    static weak var fetcher: ESPNNHLFetcher?

    static func resolveTeam(_ text: String) -> String? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return hockeyNowFavouriteTeams().first }
        if let exact = nhlAllTeams.first(where: { $0.abbreviation.lowercased() == query }) { return exact.abbreviation }
        return nhlAllTeams.first { $0.name.lowercased().contains(query) }?.abbreviation
    }

    static func name(of abbreviation: String) -> String {
        nhlAllTeams.first { $0.abbreviation == abbreviation }?.name ?? abbreviation
    }
}

struct NextGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Next game"
    static let description = IntentDescription("When a team plays next, in your local time.")

    @Parameter(title: "Team", description: "Name or abbreviation. Leave empty for your favourite team.", default: "")
    var team: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let abbreviation = HockeyNowBridge.resolveTeam(team) else {
            return .result(dialog: "I couldn't tell which team you meant. Set a favourite team in HockeyNow or say a team name.")
        }
        let zone = HockeyNowBridge.fetcher?.targetZone ?? .current
        guard let next = await NHLStrengthService.shared.nextGame(for: abbreviation) else {
            return .result(dialog: "I can't find an upcoming game for \(HockeyNowBridge.name(of: abbreviation)).")
        }
        let opponent = HockeyNowBridge.name(of: next.opponent)
        let day = hockeyNowDayWord(for: next.start, zone: zone)
        let time = hockeyNowClockString(for: next.start, zone: zone)
        let place = next.isHome ? "at home against" : "on the road against"
        return .result(dialog: "\(HockeyNowBridge.name(of: abbreviation)) play \(place) the \(opponent) \(day) at \(time). That's \(hockeyNowCountdownText(until: next.start)) away.")
    }
}

struct LatestScoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Score"
    static let description = IntentDescription("The score of a team's game that is on now, or its latest result.")

    @Parameter(title: "Team", description: "Name or abbreviation. Leave empty for your favourite team.", default: "")
    var team: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let fetcher = HockeyNowBridge.fetcher else { return .result(dialog: "HockeyNow is still starting up. Try again in a moment.") }
        guard let abbreviation = HockeyNowBridge.resolveTeam(team) else {
            return .result(dialog: "I couldn't tell which team you meant. Set a favourite team in HockeyNow or say a team name.")
        }
        let games = (fetcher.rawFetchedGames + fetcher.gamesInSeason(containing: Date())).filter {
            $0.awayTeam?.team.threeLetterAbbreviation == abbreviation || $0.homeTeam?.team.threeLetterAbbreviation == abbreviation
        }
        let live = games.first { $0.abstractState == "Live" }
        let latestFinal = games.filter { $0.abstractState == "Final" }.max { ($0.systemCalendarDate ?? .distantPast) < ($1.systemCalendarDate ?? .distantPast) }
        guard let game = live ?? latestFinal, let away = game.awayTeam, let home = game.homeTeam else {
            return .result(dialog: "No recent game for \(HockeyNowBridge.name(of: abbreviation)).")
        }
        let line = "\(away.team.safeDisplayName) \(away.score), \(home.team.safeDisplayName) \(home.score)"
        if game.abstractState == "Live" {
            return .result(dialog: "Live: \(line), period \(game.status.period ?? 1), \(game.status.displayClock ?? "").")
        }
        return .result(dialog: "Final: \(line).")
    }
}

struct StandingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Team record"
    static let description = IntentDescription("A team's record, points and place in its division.")

    @Parameter(title: "Team", description: "Name or abbreviation. Leave empty for your favourite team.", default: "")
    var team: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let fetcher = HockeyNowBridge.fetcher, let abbreviation = HockeyNowBridge.resolveTeam(team) else {
            return .result(dialog: "I couldn't tell which team you meant.")
        }
        if fetcher.standingsGroups.isEmpty { await fetcher.refreshStandings() }
        for group in fetcher.standingsGroups {
            if let index = group.entries.firstIndex(where: { $0.teamAbbreviation == abbreviation }) {
                let entry = group.entries[index]
                return .result(dialog: "\(HockeyNowBridge.name(of: abbreviation)) are \(entry.wins)-\(entry.losses)-\(entry.otLosses) with \(entry.points) points, number \(index + 1) in \(group.title).")
            }
        }
        return .result(dialog: "No standings for \(HockeyNowBridge.name(of: abbreviation)) yet.")
    }
}

struct HockeyNowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextGameIntent(), phrases: ["When does my team play in \(.applicationName)", "Next game in \(.applicationName)"],
                    shortTitle: "Next game", systemImageName: "calendar")
        AppShortcut(intent: LatestScoreIntent(), phrases: ["Score in \(.applicationName)", "What's the score in \(.applicationName)"],
                    shortTitle: "Score", systemImageName: "hockey.puck.fill")
        AppShortcut(intent: StandingsIntent(), phrases: ["Standings in \(.applicationName)", "How is my team doing in \(.applicationName)"],
                    shortTitle: "Team record", systemImageName: "list.number")
    }
}
