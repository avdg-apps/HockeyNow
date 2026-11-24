import SwiftUI

struct MyTeamView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var fetcher: ESPNNHLFetcher
    let currentLanguage: AppLanguage
    @AppStorage("favorite_team_abbreviation") private var primaryFavouriteAbbreviation = ""
    @AppStorage("extra_favorite_teams") private var extraFavouritesRaw = ""
    @State private var viewedTeamOverride: String?

    private var followedTeams: [String] {
        var teams = primaryFavouriteAbbreviation.isEmpty ? [] : [primaryFavouriteAbbreviation]
        for extra in extraFavouritesRaw.split(separator: ",").map(String.init) where !extra.isEmpty && !teams.contains(extra) { teams.append(extra) }
        return teams
    }

    private var favouriteTeamAbbreviation: String {
        if let override = viewedTeamOverride, followedTeams.contains(override) { return override }
        return primaryFavouriteAbbreviation
    }
    @AppStorage("app_theme") private var storedTheme = AppTheme.system.rawValue

    @State private var expandedGameID: String?
    @State private var selectedSeasonStartYear: Int
    @State private var playoffRace: PlayoffRaceInfo?
    @StateObject private var injuries = InjuryReport()
    @State private var playerSummary: TeamPlayerSummary?
    @State private var isLoadingPlayerSummary = false

    init(fetcher: ESPNNHLFetcher, currentLanguage: AppLanguage) {
        self.fetcher = fetcher
        self.currentLanguage = currentLanguage

        let currentDate = Date()
        let currentYear = Calendar.current.component(.year, from: currentDate)
        let currentMonth = Calendar.current.component(.month, from: currentDate)
        let seasonStartYear = currentMonth >= 9 ? currentYear : currentYear - 1

        _selectedSeasonStartYear = State(initialValue: seasonStartYear)
    }

    private var seasonName: String {
        let nextYear = selectedSeasonStartYear + 1
        return String(selectedSeasonStartYear) + "/" + String(nextYear).suffix(2)
    }

    private var favouriteTeamName: String {
        nhlAllTeams.first(where: { $0.abbreviation == favouriteTeamAbbreviation })?.name ?? "Favourite Team"
    }

    private var favouriteTeamGames: [ESPNEvent] {
        fetcher.seasonGames
            .filter { fetcher.showPreseasonOnly ? $0.isPreseasonGame : !$0.isPreseasonGame }
            .map { fetcher.applyCachedStats(to: $0) }
            .filter { game in
                game.awayTeam?.team.threeLetterAbbreviation == favouriteTeamAbbreviation ||
                game.homeTeam?.team.threeLetterAbbreviation == favouriteTeamAbbreviation
            }
            .sorted { firstGame, secondGame in
                (firstGame.systemCalendarDate ?? .distantPast) <
                (secondGame.systemCalendarDate ?? .distantPast)
            }
    }

    private var recentGames: [ESPNEvent] {
        Array(favouriteTeamGames.filter { $0.abstractState == "Final" }.suffix(5).reversed())
    }

    private var upcomingGames: [ESPNEvent] {
        Array(favouriteTeamGames.filter { $0.abstractState != "Final" }.prefix(5))
    }

    private var favouriteTeamStanding: ComputedStandingEntry? {
        fetcher.standings(for: favouriteTeamGames)
            .flatMap(\.entries)
            .first(where: { $0.teamAbbreviation == favouriteTeamAbbreviation })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if favouriteTeamAbbreviation.isEmpty {
                    emptyState
                } else {
                    HStack {
                        Text("MY TEAM")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.secondary)

                        Spacer()

                        PreseasonToggle(fetcher: fetcher)

                        Menu {
                            ForEach((2016...currentSeasonStartYear).reversed(), id: \.self) { year in
                                Button {
                                    selectedSeasonStartYear = year
                                } label: {
                                    Text(String(year) + "/" + String(year + 1).suffix(2))
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(seasonName)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    if followedTeams.count > 1 { teamChips }

                    if fetcher.isLoadingSeason {
                        VStack(spacing: 8) {
                            ProgressView(value: fetcher.seasonLoadProgress.map { Double($0.completed) / Double(max($0.total, 1)) })
                            Text(fetcher.seasonLoadingMessage())
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    } else if let seasonLoadError = fetcher.seasonLoadError {
                        VStack(spacing: 8) {
                            Text(seasonLoadError)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Button("Retry") {
                                Task {
                                    await fetcher.loadSeason(startingIn: selectedSeasonStartYear)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    favouriteTeamHeader
                    nextGameCountdown
                    recordSummary
                    playoffRaceCard
                    teamPlayersSection
                    injurySection
                    gameSection(title: "RECENT RESULTS", games: recentGames)
                    gameSection(title: "UPCOMING GAMES", games: upcomingGames)
                    seasonStatistics
                }
            }
            .padding(14)
        }
        .frame(height: 480)
        .task(id: selectedSeasonStartYear) {
            await fetcher.loadSeason(startingIn: selectedSeasonStartYear)
        }
        .task(id: playerSummaryKey) {
            await loadPlayerSummary()
        }
    }

    private var finishedFavouriteGames: [ESPNEvent] {
        favouriteTeamGames.filter { $0.abstractState == "Final" }
    }

    private var playerSummaryKey: String {
        let finishedCount = fetcher.seasonGames.reduce(0) { total, game in
            let involves = game.awayTeam?.team.threeLetterAbbreviation == favouriteTeamAbbreviation
                || game.homeTeam?.team.threeLetterAbbreviation == favouriteTeamAbbreviation
            return total + (involves && game.abstractState == "Final" ? 1 : 0)
        }
        return "\(favouriteTeamAbbreviation)-\(selectedSeasonStartYear)-\(fetcher.showPreseasonOnly)-\(fetcher.isLoadingSeason)-\(finishedCount)"
    }

    private func loadPlayerSummary() async {
        guard !favouriteTeamAbbreviation.isEmpty, !fetcher.isLoadingSeason else { return }
        playoffRace = fetcher.playoffRace(for: favouriteTeamAbbreviation)
        await injuries.load()
        let finished = finishedFavouriteGames
        guard !finished.isEmpty else { playerSummary = nil; return }
        isLoadingPlayerSummary = true
        let summary = await fetcher.teamPlayerSummary(for: favouriteTeamAbbreviation, finalGames: finished)
        guard !Task.isCancelled else { return }
        playerSummary = summary
        isLoadingPlayerSummary = false
    }

    @ViewBuilder
    private var playoffRaceCard: some View {
        if let race = playoffRace {
            let colour = getReadableFavouriteTeamColor(abbreviation: favouriteTeamAbbreviation, theme: AppTheme(rawValue: storedTheme) ?? .system, colorScheme: colorScheme)
            VStack(alignment: .leading, spacing: 3) {
                Text("PLAYOFF RACE").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.secondary)
                Text(race.headline).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(race.inPlayoffSpot ? colour : .primary)
                Text(race.detail).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private var injurySection: some View {
        let entries = injuries.entries(forTeamName: nhlAllTeams.first(where: { $0.abbreviation == favouriteTeamAbbreviation })?.name ?? "")
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("INJURIES").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(.secondary)
                VStack(spacing: 0) {
                    ForEach(entries.prefix(8)) { entry in
                        HStack(spacing: 8) {
                            Text(entry.name).font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)
                            if !entry.position.isEmpty {
                                Text(entry.position).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(entry.status.uppercased())
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill((entry.isOut ? Color.red : Color.orange).opacity(0.2)))
                                .foregroundColor(entry.isOut ? .red : .orange)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                }
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var teamChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(followedTeams, id: \.self) { abbreviation in
                    let selected = abbreviation == favouriteTeamAbbreviation
                    let tint = getReadableFavouriteTeamColor(abbreviation: abbreviation, theme: AppTheme(rawValue: storedTheme) ?? .system, colorScheme: colorScheme)
                    Button { viewedTeamOverride = abbreviation } label: {
                        Text(abbreviation)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundColor(selected ? (colorBrightness(tint) > 0.6 ? .black : .white) : .primary)
                            .background(Capsule().fill(selected ? tint : Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var nextGameCountdown: some View {
        if let next = upcomingGames.first, let away = next.awayTeam, let home = next.homeTeam, let date = next.systemCalendarDate {
            let favouriteIsHome = home.team.threeLetterAbbreviation == favouriteTeamAbbreviation
            let opponent = favouriteIsHome ? away.team : home.team
            let isLive = next.abstractState == "Live"
            let colour = getReadableFavouriteTeamColor(abbreviation: favouriteTeamAbbreviation, theme: AppTheme(rawValue: storedTheme) ?? .system, colorScheme: colorScheme)

            HStack(spacing: 12) {
                TeamLogoView(logoURLString: opponent.logo, teamAbbreviation: opponent.threeLetterAbbreviation, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLive ? "LIVE NOW" : "NEXT GAME")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(isLive ? .red : .secondary)
                    Text("\(favouriteTeamIsAway(next) ? "@" : "vs") \(opponent.safeDisplayName)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text("\(hockeyNowDayWord(for: date, zone: fetcher.targetZone).capitalized) · \(hockeyNowClockString(for: date, zone: fetcher.targetZone))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isLive {
                    Text("\(away.score.isEmpty ? "0" : away.score) - \(home.score.isEmpty ? "0" : home.score)")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(hockeyNowCountdownText(until: date, now: timeline.date))
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundColor(colour)
                    }
                }
            }
            .padding(12)
            .background(colour.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private var teamPlayersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEAM LEADERS")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.secondary)

            if let summary = playerSummary, !summary.isEmpty {
                playerGroup(title: "GOALIES") {
                    ForEach(summary.goalies) { goalie in
                        playerRow(name: goalie.displayName, headshot: goalie.headshotURL, subtitle: "G · \(goalie.gamesPlayed) GP",
                                  stats: [("W", "\(goalie.wins)"), ("SV%", savePercentText(goalie.savePercentage)), ("GAA", String(format: "%.2f", goalie.goalsAgainstAverage))])
                    }
                }
                playerGroup(title: "BEST FORWARDS") {
                    ForEach(summary.forwards) { skater in
                        playerRow(name: skater.displayName, headshot: skater.headshotURL, subtitle: "\(skater.position) · \(skater.gamesPlayed) GP",
                                  stats: [("G", "\(skater.goals)"), ("A", "\(skater.assists)"), ("PTS", "\(skater.points)")])
                    }
                }
                playerGroup(title: "BEST DEFENSE") {
                    ForEach(summary.defense) { skater in
                        playerRow(name: skater.displayName, headshot: skater.headshotURL, subtitle: "D · \(skater.gamesPlayed) GP",
                                  stats: [("G", "\(skater.goals)"), ("A", "\(skater.assists)"), ("PTS", "\(skater.points)")])
                    }
                }
            } else if isLoadingPlayerSummary || fetcher.isLoadingSeason {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading player stats…").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            } else {
                Text("No player stats yet")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    private func playerGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.amber)
            VStack(spacing: 0) { content() }
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func playerRow(name: String, headshot: String?, subtitle: String, stats: [(String, String)]) -> some View {
        HStack(spacing: 8) {
            PlayerHeadshotView(headshotURLString: headshot, initials: String(name.split(separator: " ").compactMap { $0.first }.prefix(2)).uppercased(), size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)
                Text(subtitle).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
            }
            Spacer()
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                VStack(spacing: 1) {
                    Text(stat.1).font(.system(size: 11, weight: .black, design: .monospaced))
                    Text(stat.0).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.secondary)
                }
                .frame(width: 42)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func savePercentText(_ value: Double) -> String {
        let text = String(format: "%.3f", value)
        return text.hasPrefix("0") ? String(text.dropFirst()) : text
    }

    private var currentSeasonStartYear: Int {
        let currentDate = Date()
        let currentYear = Calendar.current.component(.year, from: currentDate)
        let currentMonth = Calendar.current.component(.month, from: currentDate)
        return currentMonth >= 9 ? currentYear : currentYear - 1
    }

    private var favouriteTeamHeader: some View {
        let team = favouriteTeamGames
            .first(where: { $0.awayTeam?.team.threeLetterAbbreviation == favouriteTeamAbbreviation || $0.homeTeam?.team.threeLetterAbbreviation == favouriteTeamAbbreviation })
        let teamCompetitor = team?.awayTeam?.team.threeLetterAbbreviation == favouriteTeamAbbreviation
            ? team?.awayTeam
            : team?.homeTeam

        let readableTeamColor = getReadableFavouriteTeamColor(abbreviation: favouriteTeamAbbreviation, theme: AppTheme(rawValue: storedTheme) ?? .system, colorScheme: colorScheme)

        return HStack(spacing: 12) {
            TeamLogoView(
                logoURLString: teamCompetitor?.team.logo,
                teamAbbreviation: favouriteTeamAbbreviation,
                size: 48
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(favouriteTeamName)
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                Text("Season \(seasonName)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "heart.fill")
                .foregroundColor(readableTeamColor)
        }
        .padding(14)
        .background(readableTeamColor.opacity(0.14))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(readableTeamColor.opacity(0.45), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var recordSummary: some View {
        HStack(spacing: 0) {
            summaryMetric(title: "GP", value: favouriteTeamStanding.map { "\($0.gamesPlayed)" } ?? "—")
            summaryMetric(title: "W", value: favouriteTeamStanding.map { "\($0.wins)" } ?? "—")
            summaryMetric(title: "L", value: favouriteTeamStanding.map { "\($0.losses)" } ?? "—")
            summaryMetric(title: "OTL", value: favouriteTeamStanding.map { "\($0.otLosses)" } ?? "—")
            summaryMetric(title: "PTS", value: favouriteTeamStanding.map { "\($0.points)" } ?? "—")
        }
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }

    private var seasonStatistics: some View {
        let completedGames = favouriteTeamGames.filter { $0.abstractState == "Final" }
        let favouriteGoals = completedGames.reduce(0) { total, game in
            total + (Int(favouriteTeamIsAway(game) ? (game.awayTeam?.score ?? "") : (game.homeTeam?.score ?? "")) ?? 0)
        }
        let opponentGoals = completedGames.reduce(0) { total, game in
            total + (Int(favouriteTeamIsAway(game) ? (game.homeTeam?.score ?? "") : (game.awayTeam?.score ?? "")) ?? 0)
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("SEASON STATS")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.secondary)
            HStack(spacing: 0) {
                summaryMetric(title: "GP", value: "\(completedGames.count)")
                summaryMetric(title: "GF", value: "\(favouriteGoals)")
                summaryMetric(title: "GA", value: "\(opponentGoals)")
                summaryMetric(title: "DIFF", value: "\(favouriteGoals - opponentGoals)")
            }
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
        }
    }

    private func favouriteTeamIsAway(_ game: ESPNEvent) -> Bool {
        game.awayTeam?.team.threeLetterAbbreviation == favouriteTeamAbbreviation
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .black, design: .monospaced))
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func gameSection(title: String, games: [ESPNEvent]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.secondary)

            if games.isEmpty {
                Text("No games available")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(games) { game in
                    ESPNGameCard(
                        game: game,
                        currentLanguage: currentLanguage,
                        fetcher: fetcher,
                        isOpen: expandedGameID == game.id,
                        toggleClick: {
                            let spring = Animation.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0)
                            if expandedGameID == game.id { withAnimation(spring) { expandedGameID = nil }; return }
                            if fetcher.hasDetails(for: game.id) { withAnimation(spring) { expandedGameID = game.id }; return }
                            Task {
                                await fetcher.ensureDetails(for: game.id)
                                withAnimation(spring) { expandedGameID = game.id }
                            }
                        }
                    )
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.circle")
                .font(.system(size: 42))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Choose a favourite team in Settings to build your dashboard.")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}
