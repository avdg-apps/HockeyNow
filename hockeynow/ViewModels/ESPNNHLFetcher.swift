import Foundation
import AppKit
import Combine
@preconcurrency import UserNotifications

// MARK: - Main Engine
@MainActor
class ESPNNHLFetcher: ObservableObject {
    @Published var rawFetchedGames: [ESPNEvent] = []
    @Published var standingsGroups: [StandingGroup] = []
    @Published var isLoading = false
    @Published var isLoadingStandings = false
    @Published var hasCompletedInitialLoad = false
    @Published var seasonGames: [ESPNEvent] = []
    @Published var isLoadingSeason = false
    @Published var seasonLoadProgress: (completed: Int, total: Int)?
    @Published var seasonLoadError: String?
    @Published var standingsDate = Date() { didSet { Task { await refreshStandings() } } }
    private var cachedSeasonKey: String? = nil
    // Every season that has been loaded stays in memory under its own key. `seasonGames` is only the season currently on
    // screen (My Team / Playoffs can switch it to an old year); anything that needs a particular date's season asks for
    // `gamesInSeason(containing:)`, so form, lineups and standings can no longer be fed another year's games.
    private var seasonStore: [String: (games: [ESPNEvent], loadedAt: Date)] = [:]
    var finishedGamesCache: [String: [ESPNEvent]] = [:]
    
    // MARK: Player Leaders (Players tab)
    @Published var playersDate = Date() { didSet { Task { await refreshPlayerLeaders() } } }
    @Published var isLoadingPlayerStats = false
    // True once the leaderboard has been fully built, so views never show half-loaded (and constantly changing) data.
    @Published var hasLoadedPlayerLeaders = false
    // Off: standings, player stats and team stats use regular-season (and playoff) games only.
    // On: they use preseason games only.
    @Published var showPreseasonOnly = UserDefaults.standard.bool(forKey: "show_preseason_only") {
        didSet {
            UserDefaults.standard.set(showPreseasonOnly, forKey: "show_preseason_only")
            hasLoadedPlayerLeaders = false
            Task { await refreshStandings(); await refreshPlayerLeaders() }
        }
    }
    @Published var playerStatsLoadProgress: (completed: Int, total: Int)? = nil
    @Published var skaterLeaders: [SkaterSeasonLine] = []
    @Published var goalieLeaders: [GoalieSeasonLine] = []
    // Cached player boxscores avoid repeat downloads.
    var playerBoxscoreCache: [String: [ESPNGameSummary.ESPNBoxscore.ESPNBoxscorePlayerGroup]] = [:]
    var playerLeadersRefreshToken = UUID()
    @Published var selectedDate = Date() { didSet { runCleanFetch() } }
    @Published var scoringSummaries: [String: [ESPNPlay]] = [:]
    @Published var penaltySummaries: [String: [ESPNPenaltyItem]] = [:]
    @Published var winProbabilitySummaries: [String: [Double]] = [:]
    @Published var pregameHomeWin: [String: Double] = [:]          // ESPN's pre-game projection, as the home team's fraction
    @Published var gameStrengths: [String: GameStrength] = [:]     // exact on-ice skaters / goalies from the NHL feed
    @Published var threeStars: [String: [ThreeStar]] = [:]        // finished games: ESPN event id -> the NHL's three stars
    @Published var nextGames: [String: NextGameInfo] = [:]         // team abbreviation -> its next scheduled game
    private var pregameFetchedAt: [String: Date] = [:]
    private var todayMonitorHasLive = false
    @Published var playByPlaySummaries: [String: [ESPNPlay]] = [:]
    @Published var gameLineups: [String: [ESPNGameSummary.ESPNBoxscore.ESPNBoxscorePlayerGroup]] = [:]
    @Published var loadingSummaries: [String: Bool] = [:]
    @Published var historicalTelemetryCache: [String: [String: [ESPNEvent.ESPNCompetitor.ESPNStatistic]]] = [:]
    @Published var lastUpdated: Date?
    @Published var lastFetchError: String?
    @Published var isShowingEmptySchedule = false
    @Published var refreshInterval: RefreshInterval = RefreshInterval(rawValue: UserDefaults.standard.integer(forKey: "refresh_interval_seconds")) ?? .automatic {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refresh_interval_seconds")
            startAutomaticPollingLoop()
        }
    }
    
    @Published var pinnedGameInstance: ESPNEvent? = nil {
        didSet { persistPinnedGame(id: pinnedGameInstance?.id, key: "pinned_game_id") }
    }
    @Published var notchedGameInstance: ESPNEvent? = nil {
        didSet { persistPinnedGame(id: notchedGameInstance?.id, key: "notched_game_id") }
    }

    private func persistPinnedGame(id: String?, key: String) {
        UserDefaults.standard.set(id, forKey: key)
    }
    
    @Published var activeTickerIndex: Int = 0
    @Published var targetZone: TimeZone = .current { didSet { updateStatusString() } }
    @Published var currentStatusString: String = "HockeyNow"
    // Goals, penalties and period ends in followed teams' games; the notch listens and pops out.
    let liveActivity = PassthroughSubject<LiveActivityEvent, Never>()
    private var seenPenaltyCounts: [String: Int] = [:]
    @Published var menuDisplayMode: MenuDisplayMode = MenuDisplayMode(rawValue: UserDefaults.standard.string(forKey: "menu_display_mode") ?? "") ?? .full {
        didSet { UserDefaults.standard.set(menuDisplayMode.rawValue, forKey: "menu_display_mode"); updateStatusString() }
    }
    
    // Compact menu-bar text: just the score once a game is under way ("2-1"), "TOR@MTL" before it, "NHL" with nothing pinned.
    var shortStatusString: String {
        guard let game = pinnedGameInstance, let away = game.awayTeam, let home = game.homeTeam else {
            let full = currentStatusString
            return full == "HockeyNow" ? "NHL" : full
        }
        if game.abstractState == "Preview" { return "\(away.team.threeLetterAbbreviation)@\(home.team.threeLetterAbbreviation)" }
        return "\(away.score.isEmpty ? "0" : away.score)-\(home.score.isEmpty ? "0" : home.score)"
    }
    
    private var effectiveLowPowerMode: Bool {
        UserDefaults.standard.bool(forKey: "low_power_mode_enabled") || ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var lastGameDayScheduleDay: Date?
    private var taskHolder: Task<Void, Never>?
    private var backgroundPollingTask: Task<Void, Never>?
    private var trackedScores: [String: (away: Int, home: Int)] = [:]
    private var trackedPeriods: [String: Int] = [:]
    
    var localFilteredGames: [ESPNEvent] {
        rawFetchedGames.filter { game in
            guard let systemDate = game.systemCalendarDate else { return false }
            var localCal = Calendar.current
            localCal.timeZone = targetZone
            return localCal.isDate(systemDate, inSameDayAs: selectedDate)
        }
    }
    
    // Games involving the favourite team go first; every other game keeps its existing order.
    func favouriteTeamFirst(_ games: [ESPNEvent]) -> [ESPNEvent] {
        let favourite = UserDefaults.standard.string(forKey: "favorite_team_abbreviation") ?? ""
        guard !favourite.isEmpty else { return games }
        func involvesFavourite(_ game: ESPNEvent) -> Bool {
            game.awayTeam?.team.threeLetterAbbreviation == favourite || game.homeTeam?.team.threeLetterAbbreviation == favourite
        }
        return games.filter(involvesFavourite) + games.filter { !involvesFavourite($0) }
    }

    init() {
        requestNotificationAccess()
        runCleanFetch()
        startAutomaticPollingLoop()
        // Load the season and the player leaderboard once at launch, so Standings, My Team and the pre-game sliders
        // are ready the first time they're opened. One task, so the season isn't downloaded twice.
        Task(priority: .utility) { await refreshStandings(); await refreshPlayerLeaders() }
        Task { lastFavoriteTeamCheckDate = Date(); await checkFavoriteTeamNotifications() }
        
        // Re-plan the game-day alerts and the menu bar text when the favourite team or a related setting changes.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ -> String in
                let d = UserDefaults.standard
                return [d.string(forKey: "favorite_team_abbreviation") ?? "", d.string(forKey: "extra_favorite_teams") ?? "", "\(d.bool(forKey: "notifications_enabled_toggle"))",
                        "\(hockeyNowBool("game_day_alerts_enabled", default: true))", "\(hockeyNowBool("smart_menu_bar_text", default: false))",
                        "\(d.bool(forKey: "use_24_hour_time"))"].joined(separator: "|")
            }
            .removeDuplicates()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleGameDayNotifications()
                    self?.updateStatusString()
                }
            }
            .store(in: &cancellables)
        
        // An app left running overnight keeps showing yesterday's slate; roll forward when the day changes or the Mac wakes.
        let dayChanged = NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
        let woke = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        dayChanged.merge(with: woke)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let previousToday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                // Only follow the calendar if the person was looking at "today"; a date they picked stays put.
                if Calendar.current.isDate(self.selectedDate, inSameDayAs: previousToday) { self.selectedDate = Date() }
                else { self.runCleanFetch() }
            }
            .store(in: &cancellables)
    }
    
    private func requestNotificationAccess() {
        NotificationManager.shared.configure()
    }
    
    func runCleanFetch() {
        taskHolder?.cancel()
        taskHolder = Task {
            isLoading = true
            lastFetchError = nil
            isShowingEmptySchedule = false
            await executeFetchPipeline()
            isLoading = false
            hasCompletedInitialLoad = true
            lastUpdated = Date()
        }
    }
    
    private func executeFetchPipeline() async {
        let apiDates = [
            dateParamString(forShift: -1),
            dateParamString(forShift: 0),
            dateParamString(forShift: 1)
        ]
        
        var groupedItems: [ESPNEvent] = []
        var encounteredIDs = Set<String>()
        var receivedValidResponse = false
        
        // The three scoreboards load side by side (and decode off the main thread) instead of one after another.
        var dataByDay: [Int: Data] = [:]
        await withTaskGroup(of: (Int, Data?).self) { group in
            for (index, dateStr) in apiDates.enumerated() {
                group.addTask { (index, await Self.downloadScoreboard(dateString: dateStr)) }
            }
            for await (index, data) in group {
                if let data { dataByDay[index] = data }
            }
        }
        if Task.isCancelled { return }
        // The model types decode on the main actor, so only the downloads run side by side.
        var eventsByDay: [Int: [ESPNEvent]] = [:]
        for (index, data) in dataByDay {
            if let decoded = try? JSONDecoder().decode(ESPNResponse.self, from: data) {
                eventsByDay[index] = decoded.events ?? []
                receivedValidResponse = true
            }
        }
        for index in apiDates.indices {
            for item in eventsByDay[index] ?? [] where !encounteredIDs.contains(item.id) {
                encounteredIDs.insert(item.id)
                groupedItems.append(item)
            }
        }
        
        for (idx, item) in groupedItems.enumerated() {
            let cachedData = historicalTelemetryCache[item.id]
            let priorMatch = self.rawFetchedGames.first(where: { $0.id == item.id })
            
            for compIdx in groupedItems[idx].competitions[0].competitors.indices {
                let competitorID = groupedItems[idx].competitions[0].competitors[compIdx].id
                if let cachedStats = cachedData?[competitorID] {
                    groupedItems[idx].competitions[0].competitors[compIdx].statistics = cachedStats
                } else if let priorCompetitor = priorMatch?.competitions.first?.competitors.first(where: { $0.id == competitorID }),
                          let priorStats = priorCompetitor.statistics, !priorStats.isEmpty {
                    groupedItems[idx].competitions[0].competitors[compIdx].statistics = priorStats
                }
            }
        }
        
        processLiveAlerts(groupedItems)
        
        if !receivedValidResponse {
            lastFetchError = "Unable to load NHL games right now."
            isShowingEmptySchedule = false
            return
        }
        
        self.rawFetchedGames = groupedItems
        isShowingEmptySchedule = localFilteredGames.isEmpty
        lastUpdated = Date()
        
        // Details for every game of the day are loaded now (four at a time, the selected day first), so a game is ready
        // by the time it is tapped.
        let calendar = Calendar.current
        var selectedDayGames: [ESPNEvent] = []
        var otherDayGames: [ESPNEvent] = []
        for game in rawFetchedGames {
            if let date = game.systemCalendarDate, calendar.isDate(date, inSameDayAs: selectedDate) { selectedDayGames.append(game) }
            else { otherDayGames.append(game) }
        }
        let ordered = selectedDayGames + otherDayGames
        var jobs: [(id: String, preview: Bool)] = []
        for game in ordered {
            if game.status.type.name == "STATUS_SCHEDULED" { jobs.append((game.id, true)); continue }
            // A finished game never changes, so load its details once instead of on every poll.
            if game.abstractState == "Final" {
                if finalDetailsLoaded.contains(game.id) { continue }
                finalDetailsLoaded.insert(game.id)
            }
            jobs.append((game.id, false))
        }
        await withTaskGroup(of: Void.self) { group in
            var cursor = 0
            while cursor < jobs.count {
                if cursor >= 4 { await group.next() }      // keep at most four requests in flight
                let job = jobs[cursor]
                cursor += 1
                group.addTask { [self] in
                    if job.preview { await self.fetchPregameOdds(for: job.id) } else { await self.fetchDetails(for: job.id, silent: true) }
                }
            }
            await group.waitForAll()
        }
        
        Task { await self.refreshAuxiliaryData() }   // strength / stars / next game must not hold up the loading state
        
        if let currentPinned = pinnedGameInstance, let updated = groupedItems.first(where: { $0.id == currentPinned.id }) {
            self.pinnedGameInstance = updated
        }
        
 if let currentNotched = notchedGameInstance, let updated = groupedItems.first(where: { $0.id == currentNotched.id }) {
            self.notchedGameInstance = updated
        } else if notchedGameInstance != nil {
            Task { await self.refreshOrphanedNotchGame() }       // moved to another day: keep the notch's game current
        }
        
        updateStatusString()
    }
    
    // Goal and period alerts for whichever games are passed in (the selected days, or today's slate when browsing elsewhere).
    private func processLiveAlerts(_ games: [ESPNEvent]) {
        for game in games {
            if game.abstractState == "Live", let away = game.awayTeam, let home = game.homeTeam {
                let currentAwayScore = Int(away.score) ?? 0
                let currentHomeScore = Int(home.score) ?? 0
                
                if let previouslyTracked = trackedScores[game.id] {
                    if currentAwayScore > previouslyTracked.away {
                        triggerGoalNotification(for: game, scoringTeam: away.team.safeDisplayName, clock: game.status.displayClock ?? "20:00")
                    }
                    if currentHomeScore > previouslyTracked.home {
                        triggerGoalNotification(for: game, scoringTeam: home.team.safeDisplayName, clock: game.status.displayClock ?? "20:00")
                    }
                }
                trackedScores[game.id] = (currentAwayScore, currentHomeScore)
                
                // A new period means the last one just ended (or overtime / a shootout is starting).
                let currentPeriod = game.status.period ?? 1
                if let previousPeriod = trackedPeriods[game.id], currentPeriod > previousPeriod {
                    triggerPeriodNotification(for: game, endedPeriod: previousPeriod, newPeriod: currentPeriod)
                }
                trackedPeriods[game.id] = currentPeriod
            }
        }
    }
    
    private func selectedWindowIncludesToday() -> Bool {
        let calendar = Calendar.current
        return (-1...1).contains { shift in
            calendar.date(byAdding: .day, value: shift, to: selectedDate).map { calendar.isDateInToday($0) } ?? false
        }
    }
    
    // Browsing another date would otherwise stop all live alerts, so today's slate is watched separately.
    private func monitorTodayForAlerts() async {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd"
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard?dates=\(formatter.string(from: Date()))"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(ESPNResponse.self, from: data) else { return }
        let games = decoded.events ?? []
        todayMonitorHasLive = games.contains { $0.abstractState == "Live" }
        processLiveAlerts(games)
    }
    
    // MARK: Strength and win probability
    private func refreshAuxiliaryData() async {
        let wantedIDs = Set([notchedGameInstance?.id, pinnedGameInstance?.id].compactMap { $0 })
        let favourites = hockeyNowFavouriteTeams()
        for game in rawFetchedGames {
            guard let away = game.awayTeam, let home = game.homeTeam else { continue }
            let involvesFavourite = favourites.contains(away.team.threeLetterAbbreviation) || favourites.contains(home.team.threeLetterAbbreviation)
            if game.abstractState == "Final" {
                let isVisible = localFilteredGames.contains(where: { $0.id == game.id })
                guard wantedIDs.contains(game.id) || involvesFavourite || isVisible else { continue }
                await refreshPostGame(for: game, includeNextGames: wantedIDs.contains(game.id) || involvesFavourite)
                continue
            }
            guard wantedIDs.contains(game.id) || involvesFavourite || (game.abstractState == "Live" && game.powerPlayTeamID != nil) else { continue }
            if game.abstractState == "Live" {
                await refreshStrength(for: game)
                if involvesFavourite { await fetchDetails(for: game.id, silent: true) }     // keeps penalty pop-outs and plays current
            }
            else if game.abstractState == "Preview" { await fetchPregameOdds(for: game.id) }
        }
    }
    
    // The notch can be showing a game that is no longer in the list (you moved to another day). Without this its copy of the
    // game froze at whatever state it had, e.g. still "live" with an empty net after the game ended.
    var notchOrphanLive = false
    func refreshOrphanedNotchGame() async {
        guard let notched = notchedGameInstance else { notchOrphanLive = false; return }
        if rawFetchedGames.contains(where: { $0.id == notched.id }) { notchOrphanLive = false; return }
        if notched.abstractState == "Final", finalOrphanRefreshed.contains(notched.id) { notchOrphanLive = false; return }
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let start = notched.systemCalendarDate ?? Date()
        let formatter = HockeyNowFormatterCache.formatter(format: "yyyyMMdd", zone: eastern.timeZone)
        var days = [start]
        if let next = eastern.date(byAdding: .day, value: 1, to: start) { days.append(next) }
        for day in days {
            guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard?dates=\(formatter.string(from: day))"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let decoded = try? JSONDecoder().decode(ESPNResponse.self, from: data),
                  let fresh = decoded.events?.first(where: { $0.id == notched.id }) else { continue }
            notchedGameInstance = fresh
            notchOrphanLive = fresh.abstractState == "Live"
            if fresh.abstractState == "Final" { finalOrphanRefreshed.insert(fresh.id) }
            return
        }
    }
    private var finalOrphanRefreshed: Set<String> = []

    func refreshStrength(for game: ESPNEvent) async {
        guard let away = game.awayTeam, let home = game.homeTeam else { return }
        if let strength = await NHLStrengthService.shared.strength(espnGameID: game.id, awayAbbr: away.team.threeLetterAbbreviation,
                                                                    homeAbbr: home.team.threeLetterAbbreviation, start: game.systemCalendarDate) {
            if gameStrengths[game.id] != strength { gameStrengths[game.id] = strength }
        }
    }
    
    // ESPN's projected win chance for a game that has not started. Cached, since it barely moves before puck drop.
    func fetchPregameOdds(for gameID: String) async {
        if let fetched = pregameFetchedAt[gameID], Date().timeIntervalSince(fetched) < 1800 { return }
        pregameFetchedAt[gameID] = Date()
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/summary?event=\(gameID)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(ESPNGameSummary.self, from: data)
            if let projected = decoded.predictor?.homeFraction { pregameHomeWin[gameID] = projected }
        } catch { pregameFetchedAt[gameID] = nil }
    }
    
    // Three stars and each team's next game, for a finished game.
    func refreshPostGame(for game: ESPNEvent, includeNextGames: Bool = true) async {
        guard game.abstractState == "Final", let away = game.awayTeam, let home = game.homeTeam else { return }
        let awayAbbr = away.team.threeLetterAbbreviation, homeAbbr = home.team.threeLetterAbbreviation
        if (threeStars[game.id] ?? []).isEmpty {
            let stars = await NHLStrengthService.shared.threeStars(espnGameID: game.id, awayAbbr: awayAbbr, homeAbbr: homeAbbr, start: game.systemCalendarDate)
            if !stars.isEmpty { threeStars[game.id] = stars }
        }
        guard includeNextGames else { return }
        for abbreviation in [awayAbbr, homeAbbr] {
            if let next = await NHLStrengthService.shared.nextGame(for: abbreviation), nextGames[abbreviation] != next {
                nextGames[abbreviation] = next
            }
        }
    }
    
    // Last resort when neither the NHL feed nor ESPN's scoreboard says who is on a power play: ESPN tags many plays with
    // a strength ("Power Play" / "Short Handed") relative to the team that made the play; the newest tagged play wins.
    private func inferredPowerPlayTeamID(for game: ESPNEvent) -> String? {
        guard let away = game.awayTeam, let home = game.homeTeam, let plays = playByPlaySummaries[game.id] else { return nil }
        for play in plays.suffix(30).reversed() {
            guard let text = (play.strength?.text ?? play.strength?.abbreviation)?.lowercased(), !text.isEmpty, let teamID = play.team?.id else { continue }
            if text.contains("power") || text == "pp" { return teamID }
            if text.contains("short") || text == "sh" { return teamID == away.id ? home.id : away.id }
            return nil      // newest tagged play is even strength
        }
        return nil
    }
    
    /// Skaters on the ice for each team. The NHL feed is exact (and the only source for pulled goalies); when it is
    /// unavailable this falls back to ESPN's power-play flag, then to the strength ESPN tags on recent plays.
    func resolvedStrength(for game: ESPNEvent) -> GameStrength? {
        guard game.abstractState == "Live", let home = game.homeTeam else { return nil }
        let ppTeamID = game.powerPlayTeamID ?? inferredPowerPlayTeamID(for: game)
        if let exact = gameStrengths[game.id], !(exact.isRoutine && game.powerPlayTeamID != nil) {
            return exact.isRoutine ? nil : exact
        }
        guard let ppTeamID else { return nil }
        let overtime = (game.status.period ?? 1) == 4 && !game.isPlayoffGame
        return GameStrength.assumed(powerPlayIsHome: ppTeamID == home.id, regularSeasonOvertime: overtime)
    }
    
    private func estimatedPregameHome(for game: ESPNEvent) -> Double? {
        guard let away = game.awayTeam, let home = game.homeTeam else { return nil }
        let entries = standingsGroups.flatMap { $0.entries }
        func entry(for abbreviation: String) -> ComputedStandingEntry? {
            entries.first(where: { $0.teamAbbreviation == abbreviation && $0.gamesPlayed > 0 })
        }
        func pointsPct(_ standing: ComputedStandingEntry) -> Double {
            Double(standing.points) / Double(2 * standing.gamesPlayed)
        }
        func recentPointsPct(_ standing: ComputedStandingEntry) -> Double? {
            let games = standing.last10Wins + standing.last10Losses + standing.last10OTLosses
            guard games > 0 else { return nil }
            return Double(standing.last10Wins * 2 + standing.last10OTLosses) / Double(2 * games)
        }
        guard let h = entry(for: home.team.threeLetterAbbreviation), let a = entry(for: away.team.threeLetterAbbreviation) else { return nil }
        return WinProbabilityModel.pregameHome(
            homePointsPct: pointsPct(h), awayPointsPct: pointsPct(a),
            homeRecentPointsPct: recentPointsPct(h), awayRecentPointsPct: recentPointsPct(a),
            homeGoalDiffPerGame: Double(h.goalDifferential) / Double(h.gamesPlayed),
            awayGoalDiffPerGame: Double(a.goalDifferential) / Double(a.gamesPlayed)
        )
    }
    
    /// Win probability for a live or upcoming game: ESPN's number when it has one, a local estimate otherwise.
    func winProbabilityReading(for game: ESPNEvent) -> WinProbabilityReading? {
        switch game.abstractState {
        case "Live":
            guard let away = game.awayTeam, let home = game.homeTeam else { return nil }
            let pre = pregameHomeWin[game.id] ?? estimatedPregameHome(for: game) ?? 0.53
            let lead = (Int(home.score) ?? 0) - (Int(away.score) ?? 0)
            let period = game.status.period ?? 1
            let estimate: Double
            if period > 3 {
                estimate = lead > 0 ? 0.995 : (lead < 0 ? 0.005 : 0.5 + (pre - 0.5) * 0.4)
            } else {
                let remaining = Double(3 - period) * 1200 + (game.status.clock ?? 1200)
                estimate = WinProbabilityModel.homeWin(lead: lead, regulationSecondsLeft: remaining, pregameHome: pre)
            }
            if let published = winProbabilitySummaries[game.id]?.last {
                let blended = normalizedWinProbability(published) * 0.75 + estimate * 0.25
                return WinProbabilityReading(homeFraction: blended, isEstimate: false, isPregame: false)
            }
            return WinProbabilityReading(homeFraction: estimate, isEstimate: true, isPregame: false)
        case "Preview":
            let estimate = estimatedPregameHome(for: game)
            if let projected = pregameHomeWin[game.id], let estimate {
                return WinProbabilityReading(homeFraction: projected * 0.65 + estimate * 0.35, isEstimate: false, isPregame: true)
            }
            if let projected = pregameHomeWin[game.id] { return WinProbabilityReading(homeFraction: projected, isEstimate: false, isPregame: true) }
            if let estimate { return WinProbabilityReading(homeFraction: estimate, isEstimate: true, isPregame: true) }
            return nil
        default:
            return nil
        }
    }
    

    // Sends a pop-out event to the notch when a followed team (whose profile allows it) is in this game.
    private func announceToNotch(_ game: ESPNEvent, kind: LiveActivityEvent.Kind, title: String, detail: String, team: String = "") {
        guard hockeyNowBool("notch_popouts_enabled", default: true),
              let away = game.awayTeam?.team.threeLetterAbbreviation, let home = game.homeTeam?.team.threeLetterAbbreviation,
              AlertProfiles.followedTeamsAllow(.popouts, away: away, home: home) == true else { return }
        liveActivity.send(LiveActivityEvent(kind: kind, gameID: game.id, title: title, detail: detail, teamAbbreviation: team))
    }
    
    private func scoreLine(_ game: ESPNEvent) -> String {
        guard let away = game.awayTeam, let home = game.homeTeam else { return "" }
        return "\(away.team.threeLetterAbbreviation) \(away.score) - \(home.score) \(home.team.threeLetterAbbreviation)"
    }

    // Period-end, overtime and shootout alerts, for followed teams only.
    private func triggerPeriodNotification(for game: ESPNEvent, endedPeriod: Int, newPeriod: Int) {
        guard let away = game.awayTeam, let home = game.homeTeam else { return }
        let favourites = hockeyNowFavouriteTeams()
        guard favourites.contains(away.team.threeLetterAbbreviation) || favourites.contains(home.team.threeLetterAbbreviation) else { return }
        
        let title: String
        if newPeriod <= 3 {
            let names = ["1st", "2nd", "3rd"]
            title = "End of the \(names[max(0, min(endedPeriod - 1, 2))]) period"
        } else if game.isPlayoffGame {
            title = newPeriod == 4 ? "Overtime!" : "Overtime \(newPeriod - 3)!"
        } else {
            title = newPeriod == 4 ? "Overtime!" : "Shootout!"
        }
        announceToNotch(game, kind: newPeriod > 3 ? .overtime : .periodEnd, title: title, detail: scoreLine(game))
        guard UserDefaults.standard.bool(forKey: "notifications_enabled_toggle"), hockeyNowBool("period_alerts_enabled", default: true),
              AlertProfiles.followedTeamsAllow(.periods, away: away.team.threeLetterAbbreviation, home: home.team.threeLetterAbbreviation) == true else { return }
        NotificationManager.post(title: title, body: scoreLine(game), identifier: "period-\(game.id)-\(newPeriod)", url: URL(string: "https://www.espn.com/nhl/game/_/gameId/\(game.id)"))
    }
    
    private func triggerGoalNotification(for game: ESPNEvent, scoringTeam: String, clock: String) {
        guard let away = game.awayTeam, let home = game.homeTeam else { return }
        let awayAbbr = away.team.threeLetterAbbreviation, homeAbbr = home.team.threeLetterAbbreviation
        let scorerAbbr = scoringTeam == away.team.safeDisplayName ? awayAbbr : homeAbbr
        let line = "\(scoreLine(game)) (Period \(game.status.period ?? 1) @ \(clock))"
        announceToNotch(game, kind: .goal, title: "GOAL \(scorerAbbr)", detail: line, team: scorerAbbr)
        guard UserDefaults.standard.bool(forKey: "notifications_enabled_toggle") else { return }
        if let followedAllow = AlertProfiles.followedTeamsAllow(.goals, away: awayAbbr, home: homeAbbr) {
            guard followedAllow else { return }          // a followed team in this game has goal alerts off
        } else if UserDefaults.standard.bool(forKey: "goal_alerts_favourite_only"), !hockeyNowFavouriteTeams().isEmpty {
            return                                       // "my team only": stay quiet for every other game
        }
        NotificationManager.post(title: "🚨 GOAL scored by \(scoringTeam)!", body: line, identifier: UUID().uuidString,
                                 url: URL(string: "https://www.espn.com/nhl/game/_/gameId/\(game.id)"))
    }
    
    private var notifiedFavoriteTeamPregameIDs: Set<String> = []
    private var notifiedFavoriteTeamPostgameIDs: Set<String> = []
    
    func checkFavoriteTeamNotifications() async {
        guard UserDefaults.standard.bool(forKey: "notifications_enabled_toggle") else { return }
        let favourites = hockeyNowFavouriteTeams()
        guard !favourites.isEmpty else { return }
        
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd"
        let todayParam = formatter.string(from: Date())
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard?dates=\(todayParam)") else { return }
        
        let todaysGames: [ESPNEvent]
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(ESPNResponse.self, from: data)
            todaysGames = decoded.events ?? []
        } catch { return }
        
        for game in todaysGames {
            guard let away = game.awayTeam, let home = game.homeTeam else { continue }
            let isAwayFavorite = favourites.contains(away.team.threeLetterAbbreviation)
            let isHomeFavorite = favourites.contains(home.team.threeLetterAbbreviation) && !isAwayFavorite
            guard isAwayFavorite || isHomeFavorite else { continue }
            
            let favoriteAbbr = isAwayFavorite ? away.team.threeLetterAbbreviation : home.team.threeLetterAbbreviation
            let favoriteTeamName = isAwayFavorite ? away.team.safeDisplayName : home.team.safeDisplayName
            let opponentName = isAwayFavorite ? home.team.safeDisplayName : away.team.safeDisplayName
            
            if game.abstractState == "Preview", !hockeyNowBool("game_day_alerts_enabled", default: true), !notifiedFavoriteTeamPregameIDs.contains(game.id), let gameDate = game.systemCalendarDate {
                let minutesUntilStart = gameDate.timeIntervalSinceNow / 60
                if minutesUntilStart > 0 && minutesUntilStart <= 20 {
                    notifiedFavoriteTeamPregameIDs.insert(game.id)
                    let timeFormatter = DateFormatter(); timeFormatter.dateFormat = hockeyNowTimeFormat(); timeFormatter.timeZone = targetZone
                    let timeString = "\(timeFormatter.string(from: gameDate)) \(targetZone.abbreviation(for: gameDate) ?? "")"
                    let content = UNMutableNotificationContent()
                    content.title = "HockeyNow"
                    content.body = "\(favoriteTeamName) will be playing at \(timeString)."
                    content.sound = hockeyNowNotificationSound()
                    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pregame-\(game.id)", content: content, trigger: nil))
                }
            }
            
            if game.abstractState == "Final", hockeyNowBool("period_alerts_enabled", default: true), !notifiedFavoriteTeamPostgameIDs.contains(game.id),
               AlertProfiles.followedTeamsAllow(.finals, away: away.team.threeLetterAbbreviation, home: home.team.threeLetterAbbreviation) == true {
                notifiedFavoriteTeamPostgameIDs.insert(game.id)
                let favoriteScore = Int(isAwayFavorite ? away.score : home.score) ?? 0
                let opponentScore = Int(isAwayFavorite ? home.score : away.score) ?? 0
                let resultPhrase = favoriteScore > opponentScore ? "won against" : "lost to"
                let overtimeTag = (game.status.period ?? 3) > 3 ? ((game.status.period ?? 3) == 4 || game.isPlayoffGame ? " in OT" : " in a shootout") : ""
                let content = UNMutableNotificationContent()
                content.title = "Final: \(favoriteScore)-\(opponentScore)"
                content.body = "\(favoriteTeamName) \(resultPhrase) \(opponentName)\(overtimeTag)."
                content.sound = hockeyNowNotificationSound()
                content.userInfo = ["url": "https://www.espn.com/nhl/game/_/gameId/\(game.id)"]
                announceToNotch(game, kind: .final, title: content.title, detail: content.body, team: favoriteAbbr)
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "postgame-\(game.id)", content: content, trigger: nil))
            }
        }
    }
    
    private func seasonStartDate(for date: Date) -> Date {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = cal.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 2025
        let month = comps.month ?? 1
        let seasonStartYear = month >= 9 ? year : year - 1
        return cal.date(from: DateComponents(year: seasonStartYear, month: 9, day: 1)) ?? date
    }
    
    private func seasonKey(for date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy"
        return formatter.string(from: seasonStartDate(for: date))
    }
    
    func loadSeasonIfNeeded(for date: Date) async {
        let key = seasonKey(for: date)
        let startDate = seasonStartDate(for: date)
        let endDate = max(date, startDate)
        await loadSeason(key: key, startDate: startDate, endDate: endDate)
    }

    func loadSeason(startingIn seasonStartYear: Int) async {
        var calendar = Calendar.current
        calendar.timeZone = targetZone
        let startDate = calendar.date(from: DateComponents(year: seasonStartYear, month: 9, day: 1)) ?? Date()
        let currentStartYear = Int(seasonKey(for: Date())) ?? seasonStartYear
        let endDate: Date
        if seasonStartYear == currentStartYear {
            endDate = Date()
        } else {
            endDate = calendar.date(from: DateComponents(year: seasonStartYear + 1, month: 8, day: 1)) ?? startDate
        }
        await loadSeason(key: String(seasonStartYear), startDate: startDate, endDate: max(endDate, startDate))
    }

    private func loadSeason(key: String, startDate: Date, endDate: Date) async {
        let isCurrentSeason = key == seasonKey(for: Date())
        // Past seasons never change; the current one is refreshed every few minutes so new results show up.
        if let stored = seasonStore[key], !stored.games.isEmpty,
           !isCurrentSeason || Date().timeIntervalSince(stored.loadedAt) < 600 {
            if cachedSeasonKey != key { seasonGames = stored.games; cachedSeasonKey = key; seasonLoadedAt = stored.loadedAt }
            return
        }
        // Always load the whole window for a season (the current one runs ~2 months ahead) so Standings, My Team and
        // Players all see the same games, including upcoming ones.
        var seasonCalendar = Calendar(identifier: .gregorian)
        seasonCalendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let effectiveEnd: Date
        if isCurrentSeason {
            effectiveEnd = Date().addingTimeInterval(60 * 24 * 3600)
        } else {
            effectiveEnd = seasonCalendar.date(from: DateComponents(year: (Int(key) ?? 0) + 1, month: 8, day: 1)) ?? endDate
        }

        isLoadingSeason = true
        seasonLoadError = nil
        seasonLoadProgress = nil
        defer {
            isLoadingSeason = false
            seasonLoadProgress = nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMM"

        // ESPN limits large yearly responses, so request one month at a time.
        var monthStarts: [Date] = []
        var month = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate)) ?? startDate
        let finalMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: effectiveEnd)) ?? effectiveEnd
        while month <= finalMonth {
            monthStarts.append(month)
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = nextMonth
        }

        var loadedGames: [ESPNEvent] = []
        var receivedValidResponse = false
        seasonLoadProgress = (0, max(monthStarts.count, 1))

        // Months before last month are finished, so once saved they are read from disk instead of downloaded again.
        let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let savedMonthCutoff = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart

        for (index, monthStart) in monthStarts.enumerated() {
            guard !Task.isCancelled else { return }
            let monthParameter = formatter.string(from: monthStart)
            let canSaveMonth = monthStart < savedMonthCutoff
            if canSaveMonth, let savedData = FinalGameStore.loadMonth(key: monthParameter),
               let savedResponse = try? JSONDecoder().decode(ESPNResponse.self, from: savedData) {
                receivedValidResponse = true
                loadedGames.append(contentsOf: savedResponse.events ?? [])
                seasonLoadProgress = (index + 1, max(monthStarts.count, 1))
                continue
            }
            guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard?dates=\(monthParameter)&limit=1000") else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else { continue }
                let decoded = try JSONDecoder().decode(ESPNResponse.self, from: data)
                receivedValidResponse = true
                loadedGames.append(contentsOf: decoded.events ?? [])
                if canSaveMonth, (decoded.events ?? []).allSatisfy({ $0.status.type.state == "post" }) {
                    FinalGameStore.saveMonth(data, key: monthParameter)
                }
            } catch {
                continue
            }
            seasonLoadProgress = (index + 1, max(monthStarts.count, 1))
        }

        let uniqueGames = Dictionary(loadedGames
            .filter { event in
                guard let date = event.systemCalendarDate else { return false }
                return date >= startDate && date <= effectiveEnd
            }
            .map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sortedGames = uniqueGames.values.sorted { ($0.systemCalendarDate ?? .distantPast) < ($1.systemCalendarDate ?? .distantPast) }
        // A failed download must not wipe a season that is already in memory.
        if receivedValidResponse || seasonStore[key] == nil {
            seasonGames = sortedGames
            cachedSeasonKey = receivedValidResponse ? key : nil
        }
        if receivedValidResponse {
            seasonLoadedAt = Date()
            seasonStore[key] = (sortedGames, Date())
            finishedGamesCache = [:]
        }
        seasonLoadError = receivedValidResponse ? nil : "Season data could not be loaded."
        if receivedValidResponse, isCurrentSeason {
            scheduleGameDayNotifications()
            updateStatusString()
        }
    }

    // The games of whichever season `date` falls in (empty until that season has been loaded).
    func gamesInSeason(containing date: Date) -> [ESPNEvent] {
        let key = seasonKey(for: date)
        if let stored = seasonStore[key] { return stored.games }
        return cachedSeasonKey == key ? seasonGames : []
    }
    
    func seasonKeyForCaches(_ date: Date) -> String { seasonKey(for: date) }
    
    func seasonLoadingMessage() -> String {
        guard let progress = seasonLoadProgress else { return "Cutting the ice…" }
        return "Loading season data \(progress.completed) of \(progress.total)…"
    }
    
    func standings(for games: [ESPNEvent], asOf date: Date = Date()) -> [StandingGroup] {
        computedStandings(from: games, asOf: date)
    }

    private func computedStandings(asOf date: Date) -> [StandingGroup] {
        computedStandings(from: gamesInSeason(containing: date), asOf: date)
    }

    private func computedStandings(from games: [ESPNEvent], asOf date: Date) -> [StandingGroup] {
        var tally: [String: ComputedStandingEntry] = [:]
        // Each team's results in the order they were played, for the last-10 record and the streak.
        var resultsByTeam: [String: [(date: Date, result: GameResult)]] = [:]
        
        for event in games {
            guard event.status.type.state == "post", showPreseasonOnly ? event.isPreseasonGame : event.countsTowardStandings,
                  let eventDate = event.systemCalendarDate, eventDate <= date,
                  let away = event.awayTeam, let home = event.homeTeam else { continue }
            
            let awayScore = Int(away.score) ?? 0
            let homeScore = Int(home.score) ?? 0
            guard awayScore != homeScore else { continue }
            let period = event.status.period ?? 3
            let wentToOvertime = period > 3
            // Regular season and preseason: one overtime period, then a shootout. ESPN's score already includes the shootout goal.
            let detail = event.status.type.detail.lowercased()
            let wentToShootout = wentToOvertime && (detail.contains("shootout") || detail.hasSuffix("/so") || (!event.isPlayoffGame && period >= 5))
            
            let awayAbbr = away.team.threeLetterAbbreviation
            let homeAbbr = home.team.threeLetterAbbreviation
            var awayEntry = tally[awayAbbr] ?? ComputedStandingEntry(teamAbbreviation: awayAbbr, teamDisplayName: away.team.safeDisplayName, teamLogo: away.team.logo)
            var homeEntry = tally[homeAbbr] ?? ComputedStandingEntry(teamAbbreviation: homeAbbr, teamDisplayName: home.team.safeDisplayName, teamLogo: home.team.logo)
            
            awayEntry.goalsFor += awayScore
            awayEntry.goalsAgainst += homeScore
            homeEntry.goalsFor += homeScore
            homeEntry.goalsAgainst += awayScore
            
            // Points from this game: 2 for a win, 1 for an overtime or shootout loss.
            let awayWon = awayScore > homeScore
            let winnerPoints = 2, loserPoints = wentToOvertime ? 1 : 0
            let awayPoints = awayWon ? winnerPoints : loserPoints
            let homePoints = awayWon ? loserPoints : winnerPoints
            awayEntry.meetings[homeAbbr, default: []].append(HeadToHeadGame(date: eventDate, hostAbbreviation: homeAbbr, pointsFor: awayPoints, pointsAgainst: homePoints))
            homeEntry.meetings[awayAbbr, default: []].append(HeadToHeadGame(date: eventDate, hostAbbreviation: homeAbbr, pointsFor: homePoints, pointsAgainst: awayPoints))
            
            func recordWin(_ entry: inout ComputedStandingEntry) {
                entry.wins += 1
                if !wentToOvertime { entry.regulationWins += 1 }
                else if !wentToShootout { entry.overtimeWins += 1 }
            }
            if awayWon {
                recordWin(&awayEntry)
                if wentToOvertime { homeEntry.otLosses += 1 } else { homeEntry.losses += 1 }
                resultsByTeam[awayAbbr, default: []].append((eventDate, .win))
                resultsByTeam[homeAbbr, default: []].append((eventDate, wentToOvertime ? .otLoss : .loss))
            } else {
                recordWin(&homeEntry)
                if wentToOvertime { awayEntry.otLosses += 1 } else { awayEntry.losses += 1 }
                resultsByTeam[homeAbbr, default: []].append((eventDate, .win))
                resultsByTeam[awayAbbr, default: []].append((eventDate, wentToOvertime ? .otLoss : .loss))
            }
            
            tally[awayAbbr] = awayEntry
            tally[homeAbbr] = homeEntry
        }
        
        for (abbr, results) in resultsByTeam {
            guard var entry = tally[abbr] else { continue }
            let ordered = results.sorted { $0.date < $1.date }.map(\.result)
            for result in ordered.suffix(10) {
                switch result {
                case .win: entry.last10Wins += 1
                case .loss: entry.last10Losses += 1
                case .otLoss: entry.last10OTLosses += 1
                }
            }
            if let latest = ordered.last {
                entry.streakResult = latest
                entry.streakLength = ordered.reversed().prefix(while: { $0 == latest }).count
            }
            tally[abbr] = entry
        }
        
        var groups: [StandingGroup] = []
        for entry in nhlDivisionOrder {
            let divisionEntries = rankStandings(entry.teams.compactMap { tally[$0] })
            if !divisionEntries.isEmpty {
                groups.append(StandingGroup(title: "\(entry.conference) - \(entry.division)", entries: divisionEntries))
            }
        }
        return groups
    }
    
    func refreshStandings() async {
        isLoadingStandings = true
        await loadSeasonIfNeeded(for: standingsDate)
        self.standingsGroups = computedStandings(asOf: standingsDate)
        isLoadingStandings = false
    }
    
    func gamesForTeamSearch(matching query: String, referenceDate: Date) -> [ESPNEvent] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return seasonGames.filter { event in
            [event.awayTeam, event.homeTeam].contains { competitor in
                guard let competitor else { return false }
                return competitor.team.safeDisplayName.lowercased().contains(trimmed)
                    || competitor.team.threeLetterAbbreviation.lowercased().contains(trimmed)
            }
        }.sorted { ($0.systemCalendarDate ?? .distantPast) > ($1.systemCalendarDate ?? .distantPast) }
    }
    
    func detectLiveGoalModifiers(for gameID: String) -> String {
        guard let plays = scoringSummaries[gameID], let lastPlay = plays.last else { return "" }
        let lower = lastPlay.text.lowercased()
        if lower.contains("power play") || lower.contains("power-play") || lower.contains("(pp)") || lower.contains(" ppg") || lower.hasSuffix("pp") { return " (PP)" }
        if lower.contains("short handed") || lower.contains("short-handed") || lower.contains("(sh)") || lower.contains(" shg") { return " (SH)" }
        if lower.contains("empty net") || lower.contains("empty-net") || lower.contains("(en)") || lower.contains(" eng") { return " (EN)" }
        if lower.contains("own goal") || lower.contains("own-goal") { return " (OWN)" }
        if lower.contains("awarded") { return " (AWD)" }
        return ""
    }
    
    func updateStatusString() {
        guard let targetGame = pinnedGameInstance else {
            // Nothing pinned: show the favourite team's live score while it plays, and its next game otherwise.
            currentStatusString = (hockeyNowBool("smart_menu_bar_text", default: false) ? favouriteTeamStatusText() : nil) ?? "HockeyNow"
            return
        }
        guard let away = targetGame.awayTeam, let home = targetGame.homeTeam else {
            currentStatusString = "HockeyNow"
            return
        }
        
        if targetGame.abstractState == "Preview" {
            currentStatusString = "\(away.team.threeLetterAbbreviation) @ \(home.team.threeLetterAbbreviation)"
        } else {
            currentStatusString = "\(away.team.threeLetterAbbreviation) \(away.score) - \(home.score) \(home.team.threeLetterAbbreviation)"
        }
    }
    
    // "TOR 2 - 1 MTL" while the favourite is playing, "TOR · tonight 7:00 PM" otherwise, nil with no favourite or no game.
    private func favouriteTeamStatusText() -> String? {
        let favourites = hockeyNowFavouriteTeams()
        guard !favourites.isEmpty else { return nil }
        func favouriteIn(_ game: ESPNEvent) -> String? {
            favourites.first { $0 == game.awayTeam?.team.threeLetterAbbreviation || $0 == game.homeTeam?.team.threeLetterAbbreviation }
        }
        
        // Live games come only from the freshly polled scoreboard, so a stale season copy can never show an old score.
        if let live = rawFetchedGames.first(where: { favouriteIn($0) != nil && $0.abstractState == "Live" }),
           let away = live.awayTeam, let home = live.homeTeam {
            return "\(away.team.threeLetterAbbreviation) \(away.score) - \(home.score) \(home.team.threeLetterAbbreviation)"
        }
        
        let cutoff = Date().addingTimeInterval(-30 * 60)
        let candidates = (rawFetchedGames + seasonGames).filter {
            favouriteIn($0) != nil && $0.abstractState == "Preview" && ($0.systemCalendarDate ?? .distantPast) > cutoff
        }
        guard let next = candidates.min(by: { ($0.systemCalendarDate ?? .distantFuture) < ($1.systemCalendarDate ?? .distantFuture) }),
              let date = next.systemCalendarDate, let team = favouriteIn(next) else { return nil }
        return "\(team) · \(hockeyNowDayWord(for: date, zone: targetZone)) \(hockeyNowClockString(for: date, zone: targetZone))"
    }
    
    // MARK: Game-day alerts
    func scheduleGameDayNotifications() {
        let defaults = UserDefaults.standard
        let favourites = hockeyNowFavouriteTeams()
        let enabled = defaults.bool(forKey: "notifications_enabled_toggle") && hockeyNowBool("game_day_alerts_enabled", default: true) && !favourites.isEmpty
        
        var plan: [(id: String, title: String, body: String, fire: Date)] = []
        if enabled {
            let now = Date()
            let calendar = Calendar.current
            let upcoming = seasonGames
                .filter { game in
                    guard game.abstractState == "Preview", let date = game.systemCalendarDate, date > now else { return false }
                    let awayAbbr = game.awayTeam?.team.threeLetterAbbreviation ?? "", homeAbbr = game.homeTeam?.team.threeLetterAbbreviation ?? ""
                    return AlertProfiles.followedTeamsAllow(.gameDay, away: awayAbbr, home: homeAbbr) == true
                }
                .sorted { ($0.systemCalendarDate ?? .distantFuture) < ($1.systemCalendarDate ?? .distantFuture) }
                .prefix(30)   // two alerts per game stays under the system limit of 64 pending notifications
            
            for game in upcoming {
                guard let gameDate = game.systemCalendarDate, let away = game.awayTeam, let home = game.homeTeam else { continue }
                let favourite = favourites.first { $0 == home.team.threeLetterAbbreviation || $0 == away.team.threeLetterAbbreviation } ?? ""
                let favouriteIsHome = home.team.threeLetterAbbreviation == favourite
                let opponent = favouriteIsHome ? away.team.threeLetterAbbreviation : home.team.threeLetterAbbreviation
                let matchup = favouriteIsHome ? "\(favourite) vs \(opponent)" : "\(favourite) @ \(opponent)"
                let timeText = hockeyNowClockString(for: gameDate, zone: targetZone)
                
                // 8:00 AM on game day; if the game starts too soon after that (an early start), alert the evening before.
                var morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: gameDate) ?? gameDate
                if gameDate.timeIntervalSince(morning) < 2 * 3600,
                   let dayBefore = calendar.date(byAdding: .day, value: -1, to: gameDate) {
                    morning = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayBefore) ?? morning
                }
                if morning > now {
                    plan.append(("gameday-\(game.id)", "HockeyNow",
                                 "\(matchup) \(hockeyNowDayWord(for: gameDate, zone: targetZone, now: morning)), \(timeText)", morning))
                }
                let puckDrop = gameDate.addingTimeInterval(-15 * 60)
                if puckDrop > now {
                    plan.append(("puckdrop-\(game.id)", "Puck drop in 15 minutes", "\(matchup) · \(timeText)", puckDrop))
                }
            }
        }
        
        let finalPlan = plan   // an immutable copy, because the completion handler runs off the main actor
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix("gameday-") || $0.hasPrefix("puckdrop-") }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for item in finalPlan {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = hockeyNowNotificationSound()
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }
    
    private var lastFavoriteTeamCheckDate: Date? = nil
    private var seasonLoadedAt: Date?
    private var finalDetailsLoaded = Set<String>()
    
    func startAutomaticPollingLoop() {
        backgroundPollingTask?.cancel()
        backgroundPollingTask = Task {
            while !Task.isCancelled {
                await refreshOrphanedNotchGame()
                let hasLiveGameRightNow = localFilteredGames.contains { $0.abstractState == "Live" } || todayMonitorHasLive || notchOrphanLive
                
                let waitSeconds: Double
                if refreshInterval != .automatic {
                    waitSeconds = Double(refreshInterval.rawValue)
                } else if effectiveLowPowerMode {
                    waitSeconds = hasLiveGameRightNow ? Double.random(in: 25...40) : (15 * 60)
                } else {
                    waitSeconds = hasLiveGameRightNow ? Double.random(in: 8...14) : (5 * 60)
                }
                // Generous tolerance lets macOS batch this wake-up with others, which saves energy.
                try? await Task.sleep(for: .seconds(waitSeconds), tolerance: .seconds(max(1, waitSeconds * 0.15)))
                if Task.isCancelled { break }
                updateStatusString()   // keeps "tonight 7:00" style text correct as the day moves on
                // Top up the game-day alerts once a day, so they keep coming even if the app is never relaunched.
                let today = Calendar.current.startOfDay(for: Date())
                if lastGameDayScheduleDay != today {
                    lastGameDayScheduleDay = today
                    scheduleGameDayNotifications()
                }
                
                let activeGamesOnScreen = localFilteredGames
                let activeCount = activeGamesOnScreen.filter { $0.abstractState == "Live" || $0.abstractState == "Preview" }.count
                
                if !activeGamesOnScreen.isEmpty && activeCount > 0 {
                    await executeFetchPipeline()
                }
                
                if UserDefaults.standard.bool(forKey: "notifications_enabled_toggle"), !selectedWindowIncludesToday() {
                    await monitorTodayForAlerts()
                }
                
                await TransactionWatcher.shared.runIfDue()
                
                let secondsSinceLastFavoriteCheck = lastFavoriteTeamCheckDate.map { Date().timeIntervalSince($0) } ?? .infinity
                if secondsSinceLastFavoriteCheck >= 5 * 60 {
                    lastFavoriteTeamCheckDate = Date()
                    await checkFavoriteTeamNotifications()
                }
            }
        }
    }
    
    private func dateParamString(forShift days: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        
        if let shiftedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            return formatter.string(from: shiftedDate)
        }
        return formatter.string(from: selectedDate)
    }
    
    // Deletes everything saved on disk and forgets what was loaded from it; it is downloaded again when needed.
    func clearSavedGameData() {
        FinalGameStore.clearAll()
        playerBoxscoreCache = [:]
        finalDetailsComplete.removeAll()
        finalDetailsLoaded.removeAll()
        playByPlaySummaries = [:]
        gameLineups = [:]
        hasLoadedPlayerLeaders = false
    }
    
    // MARK: Saved finished games
    private var finalDetailsComplete = Set<String>()

    private func isGameFinal(_ gameID: String) -> Bool {
        (rawFetchedGames.first(where: { $0.id == gameID }) ?? seasonGames.first(where: { $0.id == gameID }))?.abstractState == "Final"
    }

    // MARK: Loading a game's details
    private var detailTasks: [String: Task<Void, Never>] = [:]
    private var detailsFetchedAt: [String: Date] = [:]
    private var detailsLoadedIDs = Set<String>()
    
    private final class ResumeOnce { var done = false }
    // Downloads only; touches no model types, so it is safe to run off the main actor.
    private nonisolated static func downloadScoreboard(dateString: String) async -> Data? {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard?dates=\(dateString)"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else { return nil }
        return data
    }
    
    /// True when opening this game will not have to wait for anything.
    func hasDetails(for gameID: String) -> Bool {
        guard let game = rawFetchedGames.first(where: { $0.id == gameID }) ?? seasonGames.first(where: { $0.id == gameID }) else { return true }
        return game.abstractState == "Preview" || detailsLoadedIDs.contains(gameID)
    }
    
    /// Waits (briefly) for a game's details, joining a load that is already running instead of starting another.
    func ensureDetails(for gameID: String, timeout: TimeInterval = 2.5) async {
        if hasDetails(for: gameID) { return }
        let once = ResumeOnce()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { await self.fetchDetails(for: gameID); if !once.done { once.done = true; continuation.resume() } }
            Task { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); if !once.done { once.done = true; continuation.resume() } }
        }
    }
    
    func fetchDetails(for gameID: String, silent: Bool = false) async {
        if let running = detailTasks[gameID] { await running.value; return }
        // Cards ask for details every time they scroll into view; a game that is already loaded needs no new request.
        if !silent, detailsLoadedIDs.contains(gameID) {
            if isGameFinal(gameID) { return }
            if let last = detailsFetchedAt[gameID], Date().timeIntervalSince(last) < 15 { return }
        }
        let task = Task { await self.performDetailsLoad(gameID, silent: silent) }
        detailTasks[gameID] = task
        await task.value
        detailTasks[gameID] = nil
    }
    
    private func fetchDetailsSilently(for gameID: String) async { await fetchDetails(for: gameID, silent: true) }
    
    private func performDetailsLoad(_ gameID: String, silent: Bool) async {
        // A finished game comes from memory or disk (read off the main thread) instead of the network.
        if isGameFinal(gameID) {
            if finalDetailsComplete.contains(gameID) { detailsLoadedIDs.insert(gameID); return }
            if let saved = FinalGameStore.load(SavedGameDetails.self, kind: "details", id: gameID) { applySavedDetails(saved, gameID: gameID); detailsLoadedIDs.insert(gameID); return }
        }
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/summary?event=\(gameID)") else { return }
        if !silent { loadingSummaries[gameID] = true }
        defer { if !silent { loadingSummaries[gameID] = false } }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        await Task.yield()      // let the UI draw a frame before the (main-actor) decode
        guard let decoded = try? JSONDecoder().decode(ESPNGameSummary.self, from: data) else { return }
        let baselinePlays = decoded.scoringPlays ?? decoded.plays ?? []
        filterAndAssignScoring(baselinePlays, for: gameID)
        injectSOGStatsIfPresent(decoded, for: gameID)
        if let trackingData = decoded.winProbability, !trackingData.isEmpty {
            winProbabilitySummaries[gameID] = normalizedWinProbability(trackingData.map { $0.homeWinPercentage })
        }
        if let projected = decoded.predictor?.homeFraction { pregameHomeWin[gameID] = projected }
        let newPenalties = decoded.penalties ?? []
        announceNewPenalties(newPenalties, gameID: gameID)
        penaltySummaries[gameID] = newPenalties
        storePlayByPlayAndLineups(decoded, for: gameID)
        persistFinalDetailsIfNeeded(summary: decoded, plays: baselinePlays, gameID: gameID)
        detailsLoadedIDs.insert(gameID)
        detailsFetchedAt[gameID] = Date()
        updateStatusString()
    }
    
    // A penalty list that grows during a live game of a followed team becomes a notch pop-out. The first load only records the count.
    private func announceNewPenalties(_ penalties: [ESPNPenaltyItem], gameID: String) {
        defer { seenPenaltyCounts[gameID] = penalties.count }
        guard let previous = seenPenaltyCounts[gameID], penalties.count > previous,
              let game = rawFetchedGames.first(where: { $0.id == gameID }), game.abstractState == "Live",
              let latest = penalties.last else { return }
        announceToNotch(game, kind: .penalty, title: "PENALTY", detail: latest.text)
    }
    
    private func applySavedDetails(_ saved: SavedGameDetails, gameID: String) {
        filterAndAssignScoring(saved.scoringPlays, for: gameID)
        historicalTelemetryCache[gameID] = saved.teamStats
        if let idx = rawFetchedGames.firstIndex(where: { $0.id == gameID }) {
            for (teamID, stats) in saved.teamStats {
                if let compIdx = rawFetchedGames[idx].competitions.first?.competitors.firstIndex(where: { $0.id == teamID }) {
                    rawFetchedGames[idx].competitions[0].competitors[compIdx].statistics = stats
                }
            }
        }
        if !saved.winProbability.isEmpty { winProbabilitySummaries[gameID] = normalizedWinProbability(saved.winProbability) }
        penaltySummaries[gameID] = saved.penalties
        if let plays = saved.playByPlay, !plays.isEmpty { playByPlaySummaries[gameID] = plays }
        if let lineups = saved.lineups, !lineups.isEmpty { gameLineups[gameID] = lineups }
        finalDetailsComplete.insert(gameID)
    }

    private func persistFinalDetailsIfNeeded(summary: ESPNGameSummary, plays: [ESPNPlay], gameID: String) {
        guard isGameFinal(gameID) else { return }
        var stats: [String: [ESPNEvent.ESPNCompetitor.ESPNStatistic]] = [:]
        for boxTeam in summary.boxscore?.teams ?? [] {
            if let teamID = boxTeam.team?.id, let teamStats = boxTeam.statistics, !teamStats.isEmpty { stats[teamID] = teamStats }
        }
        // Don't save a half-published result; it will simply be fetched again next time.
        guard !stats.isEmpty else { return }
        let saved = SavedGameDetails(scoringPlays: plays, teamStats: stats, penalties: summary.penalties ?? [],
                                     winProbability: (summary.winProbability ?? []).map { $0.homeWinPercentage },
                                     playByPlay: summary.plays, lineups: summary.boxscore?.players)
        finalDetailsComplete.insert(gameID)
        FinalGameStore.save(saved, kind: "details", id: gameID)
    }

    // Full play-by-play and the players who dressed (with their ice time so far) when ESPN provides them.
    private func storePlayByPlayAndLineups(_ summary: ESPNGameSummary, for gameID: String) {
        if let plays = summary.plays, !plays.isEmpty { playByPlaySummaries[gameID] = plays }
        if let groups = summary.boxscore?.players, !groups.isEmpty { gameLineups[gameID] = groups }
    }
    
    private func injectSOGStatsIfPresent(_ summary: ESPNGameSummary, for gameID: String) {
        guard let boxTeams = summary.boxscore?.teams else { return }
        
        if self.historicalTelemetryCache[gameID] == nil {
            self.historicalTelemetryCache[gameID] = [:]
        }
        for boxTeam in boxTeams {
            guard let tID = boxTeam.team?.id, let stats = boxTeam.statistics, !stats.isEmpty else { continue }
            self.historicalTelemetryCache[gameID]?[tID] = stats
        }
        
        if let idx = rawFetchedGames.firstIndex(where: { $0.id == gameID }) {
            for boxTeam in boxTeams {
                guard let tID = boxTeam.team?.id, let stats = boxTeam.statistics, !stats.isEmpty else { continue }
                if let compIdx = rawFetchedGames[idx].competitions.first?.competitors.firstIndex(where: { $0.id == tID }) {
                    self.rawFetchedGames[idx].competitions[0].competitors[compIdx].statistics = stats
                }
            }
        }
    }
    
    func applyCachedStats(to event: ESPNEvent) -> ESPNEvent {
        guard let cached = historicalTelemetryCache[event.id], !event.competitions.isEmpty else { return event }
        var updated = event
        for compIdx in updated.competitions[0].competitors.indices {
            let competitorID = updated.competitions[0].competitors[compIdx].id
            if let stats = cached[competitorID] {
                updated.competitions[0].competitors[compIdx].statistics = stats
            }
        }
        return updated
    }
    
    private func filterAndAssignScoring(_ plays: [ESPNPlay], for gameID: String) {
        let rawFiltered = plays.filter { play in
            let text = play.text.lowercased()
            // ESPN's own scoring-play flag is trusted; only an explicit "no goal" style note removes it. (The old plain-substring
            // check dropped real goals whose text merely contained "vis", "minor", "saved"... inside a player's name.)
            let overturned = ["no goal", "no-goal", "disallowed", "overturned", "goal waived", "goal wiped"]
            if play.scoringPlay == true { return !overturned.contains { text.contains($0) } }
            let safetyFails = "\\b(penalty|challenge|vis|saved|misconduct|minor|tripping|slashing|hooking|roughing|holding)\\b|goalkeeper interference|no goal|no-goal|overturned|disallowed"
            if text.range(of: safetyFails, options: .regularExpression) != nil { return false }
            let strictTokens = "\\beng\\b|\\bppg\\b|\\bshg\\b|\\(eng\\)|\\(ppg\\)|\\(shg\\)|\\bgoal\\b|\\bscored\\b|power play|short-handed"
            let verifiedScoringToken = text.range(of: strictTokens, options: .regularExpression) != nil
            return verifiedScoringToken || text.contains("power play") || text.contains("short-handed")
        }
        
        self.scoringSummaries[gameID] = rawFiltered.sorted { (playA, playB) -> Bool in
            if playA.period.number != playB.period.number {
                return playA.period.number < playB.period.number
            }
            let secondsA = parseElapsedSeconds(from: playA.clock.displayValue)
            let secondsB = parseElapsedSeconds(from: playB.clock.displayValue)
            return secondsA < secondsB
        }
    }
    
    private func parseElapsedSeconds(from displayValue: String) -> Double {
        let components = displayValue.components(separatedBy: ":")
        if components.count == 2, let mins = Double(components[0]), let secs = Double(components[1]) {
            return (mins * 60.0) + secs
        }
        return 0.0
    }
    
    func cycleTicker() {
        let filtered = localFilteredGames
        guard !filtered.isEmpty else { return }
        activeTickerIndex = (activeTickerIndex + 1) % filtered.count
        pinnedGameInstance = filtered[activeTickerIndex]
        updateStatusString()
    }
    
    func retryFetch() {
        runCleanFetch()
    }

    deinit {
        taskHolder?.cancel()
        backgroundPollingTask?.cancel()
    }
}
