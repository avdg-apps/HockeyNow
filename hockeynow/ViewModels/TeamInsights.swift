import Foundation
import Combine

// MARK: - Result types
struct FormGame: Identifiable {
    let id: String
    let result: GameResult
    let opponent: String
    let scoreText: String      // "4-2" from the team's point of view
    let wasHome: Bool
}

struct TeamFormSnapshot {
    var lastFive: [FormGame] = []       // oldest first, so the newest result sits at the right-hand end of the strip
    var home = SplitRecord()
    var away = SplitRecord()
    var hasGames: Bool { !lastFive.isEmpty || home.wins + home.losses + home.otLosses + away.wins + away.losses + away.otLosses > 0 }
}

struct GoalieStarter {
    let id: String
    let name: String
    let startsInLastFive: Int
    let gamesConsidered: Int
    var savePercentage: Double?
    var goalsAgainstAverage: Double?
}

struct LineupPlayer: Identifiable {
    let id: String
    let name: String
    let position: String
    let timeOnIce: String
}

// Forwards in lines of three, defence in pairs, and the goalies, ordered by ice time.
struct TeamLineup {
    var forwardLines: [[LineupPlayer]] = []
    var defencePairs: [[LineupPlayer]] = []
    var goalies: [LineupPlayer] = []
    var isEmpty: Bool { forwardLines.isEmpty && defencePairs.isEmpty && goalies.isEmpty }
}

struct PlayoffRaceInfo {
    var inPlayoffSpot: Bool
    var headline: String
    var detail: String
}

struct TeamPlayerSummary {
    var forwards: [SkaterSeasonLine] = []
    var defense: [SkaterSeasonLine] = []
    var goalies: [GoalieSeasonLine] = []
    var isEmpty: Bool { forwards.isEmpty && defense.isEmpty && goalies.isEmpty }
}

// MARK: - Insights computed from games the app has already loaded
extension ESPNNHLFetcher {

    // Finished games for one team that were played before `date`, oldest first.
    // Preseason and regular-season/playoff games are never mixed.
    func finishedGames(for abbreviation: String, before date: Date, preseason: Bool) -> [ESPNEvent] {
        // The team's finished games for the season containing `date`, sorted once and reused; this runs for every card on screen.
        let cacheKey = "\(seasonKeyForCaches(date))|\(abbreviation)|\(preseason)"
        let all: [ESPNEvent]
        if let cached = finishedGamesCache[cacheKey] { all = cached }
        else {
            let built = gamesInSeason(containing: date).filter { game in
                game.status.type.state == "post" && game.isPreseasonGame == preseason && game.systemCalendarDate != nil
                    && (game.awayTeam?.team.threeLetterAbbreviation == abbreviation || game.homeTeam?.team.threeLetterAbbreviation == abbreviation)
            }
            .sorted { ($0.systemCalendarDate ?? .distantPast) < ($1.systemCalendarDate ?? .distantPast) }
            if !built.isEmpty { finishedGamesCache[cacheKey] = built }
            all = built
        }
        return Array(all.prefix { ($0.systemCalendarDate ?? .distantFuture) < date })
    }

    // How a finished game went for one team. Level scores (not a real final) give nil.
    func result(of game: ESPNEvent, for abbreviation: String) -> (result: GameResult, own: Int, other: Int, opponent: String, wasHome: Bool)? {
        guard let away = game.awayTeam, let home = game.homeTeam else { return nil }
        let isHome = home.team.threeLetterAbbreviation == abbreviation
        guard isHome || away.team.threeLetterAbbreviation == abbreviation else { return nil }
        let own = Int((isHome ? home : away).score) ?? 0
        let other = Int((isHome ? away : home).score) ?? 0
        guard own != other else { return nil }
        let overtime = (game.status.period ?? 3) > 3
        let result: GameResult = own > other ? .win : (overtime ? .otLoss : .loss)
        return (result, own, other, (isHome ? away : home).team.threeLetterAbbreviation, isHome)
    }

    func teamForm(for abbreviation: String, before date: Date, preseason: Bool) -> TeamFormSnapshot {
        var snapshot = TeamFormSnapshot()
        var recent: [FormGame] = []
        for game in finishedGames(for: abbreviation, before: date, preseason: preseason) {
            guard let outcome = result(of: game, for: abbreviation) else { continue }
            if outcome.wasHome { snapshot.home.add(outcome.result) } else { snapshot.away.add(outcome.result) }
            recent.append(FormGame(id: game.id, result: outcome.result, opponent: outcome.opponent,
                                   scoreText: "\(outcome.own)-\(outcome.other)", wasHome: outcome.wasHome))
        }
        snapshot.lastFive = Array(recent.suffix(5))
        return snapshot
    }

    // "TOR won 2 of the last 3 against MTL" (this season's meetings, as far as they have been loaded).
    func headToHeadLine(perspective: String, opponent: String, before date: Date, preseason: Bool) -> String {
        let meetings = finishedGames(for: perspective, before: date, preseason: preseason)
            .filter { $0.awayTeam?.team.threeLetterAbbreviation == opponent || $0.homeTeam?.team.threeLetterAbbreviation == opponent }
            .suffix(3)
        let outcomes = meetings.compactMap { result(of: $0, for: perspective) }
        guard !outcomes.isEmpty else { return "First meeting between \(perspective) and \(opponent) this season" }
        let wins = outcomes.filter { $0.result == .win }.count
        if outcomes.count == 1 {
            let only = outcomes[0]
            return "\(perspective) \(only.result == .win ? "won" : "lost") the last meeting against \(opponent), \(only.own)-\(only.other)"
        }
        return "\(perspective) won \(wins) of the last \(outcomes.count) against \(opponent)"
    }

    // MARK: Goalies
    // The goalie who played the most minutes for a team in one boxscore.
    private func startingGoalie(in groups: [ESPNGameSummary.ESPNBoxscore.ESPNBoxscorePlayerGroup], teamID: String) -> (id: String, name: String)? {
        for group in groups where group.team?.id == teamID {
            var best: (id: String, name: String, toi: Int)?
            for category in group.statistics ?? [] {
                let categoryName = category.name?.lowercased() ?? ""
                guard categoryName.contains("goal") || categoryName.contains("netminder") || categoryName.contains("goaltender") else { continue }
                let columnKeys = (category.keys?.isEmpty == false ? category.keys! : (category.labels ?? []))
                for line in category.athletes ?? [] {
                    guard let athleteID = line.athlete?.id else { continue }
                    var lookup: [String: String] = [:]
                    for (index, key) in columnKeys.enumerated() where index < (line.stats?.count ?? 0) {
                        lookup[key.lowercased()] = line.stats?[index]
                    }
                    let toi = timeOnIceSeconds(lookup)
                    if best == nil || toi > best!.toi {
                        best = (athleteID, line.athlete?.displayName ?? line.athlete?.shortName ?? "Goalie", toi)
                    }
                }
            }
            if let best { return (best.id, best.name) }
        }
        return nil
    }

    // Games whose boxscores are needed to guess a team's starter (its last five finished games).
    func starterGameIDs(for abbreviation: String, before date: Date, preseason: Bool) -> [String] {
        finishedGames(for: abbreviation, before: date, preseason: preseason).suffix(5).map(\.id)
    }

    // Likely starter = the goalie who started most of the team's last five games; a tie goes to the most recent starter.
    func likelyStarter(for abbreviation: String, before date: Date, preseason: Bool) -> GoalieStarter? {
        let games = Array(finishedGames(for: abbreviation, before: date, preseason: preseason).suffix(5).reversed())   // newest first
        var starts: [String: (name: String, count: Int, newestIndex: Int)] = [:]
        var considered = 0
        for (index, game) in games.enumerated() {
            guard let groups = playerBoxscoreCache[game.id], !groups.isEmpty,
                  let teamID = game.competitions.first?.competitors.first(where: { $0.team.threeLetterAbbreviation == abbreviation })?.id,
                  let starter = startingGoalie(in: groups, teamID: teamID) else { continue }
            considered += 1
            var entry = starts[starter.id] ?? (starter.name, 0, index)
            entry.count += 1
            entry.newestIndex = min(entry.newestIndex, index)
            starts[starter.id] = entry
        }
        guard let top = starts.max(by: { lhs, rhs in
            lhs.value.count != rhs.value.count ? lhs.value.count < rhs.value.count : lhs.value.newestIndex > rhs.value.newestIndex
        }) else { return nil }

        let season = goalieLeaders.first { $0.id == top.key }
        return GoalieStarter(id: top.key, name: top.value.name, startsInLastFive: top.value.count, gamesConsidered: considered,
                             savePercentage: (season?.shotsAgainst ?? 0) > 0 ? season?.savePercentage : nil,
                             goalsAgainstAverage: (season?.gamesPlayed ?? 0) > 0 ? season?.goalsAgainstAverage : nil)
    }

    // Downloads (or reads from disk) any boxscores that are not in memory yet.
    func ensureBoxscores(forGameIDs ids: [String]) async {
        let missing = ids.filter { playerBoxscoreCache[$0] == nil }
        guard !missing.isEmpty else { return }
        var index = 0
        while index < missing.count {
            let chunk = Array(missing[index..<min(index + 8, missing.count)])
            await withTaskGroup(of: (String, [ESPNGameSummary.ESPNBoxscore.ESPNBoxscorePlayerGroup]?).self) { group in
                for gameID in chunk {
                    group.addTask { (gameID, await Self.fetchPlayerBoxscoreGroups(for: gameID)) }
                }
                for await (gameID, groups) in group {
                    if let groups, !groups.isEmpty { self.playerBoxscoreCache[gameID] = groups }
                }
            }
            index += chunk.count
        }
        objectWillChange.send()
    }

    // MARK: My Team players
    // Goalies, forwards and defence for one team, totalled from its finished games.
    func teamPlayerSummary(for abbreviation: String, finalGames: [ESPNEvent]) async -> TeamPlayerSummary {
        await ensureBoxscores(forGameIDs: finalGames.map(\.id))

        var skaters: [String: SkaterSeasonLine] = [:]
        var goalies: [String: GoalieSeasonLine] = [:]

        for game in finalGames {
            guard let groups = playerBoxscoreCache[game.id], !groups.isEmpty,
                  let competitors = game.competitions.first?.competitors,
                  let team = competitors.first(where: { $0.team.threeLetterAbbreviation == abbreviation }),
                  let opponent = competitors.first(where: { $0.id != team.id }),
                  let teamScore = Int(team.score), let opponentScore = Int(opponent.score) else { continue }
            let wentToOvertime = (game.status.period ?? 3) > 3
            var goalieLines: [(id: String, toi: Int, shotsAgainst: Int, hadDecision: Bool)] = []

            for group in groups where group.team?.id == team.id {
                for category in group.statistics ?? [] {
                    let columnKeys = (category.keys?.isEmpty == false ? category.keys! : (category.labels ?? []))
                    let categoryName = category.name?.lowercased() ?? ""
                    let isGoalieGroup = categoryName.contains("goal") || categoryName.contains("netminder") || categoryName.contains("goaltender")

                    for line in category.athletes ?? [] {
                        guard let athleteID = line.athlete?.id, let values = line.stats, !values.isEmpty else { continue }
                        var lookup: [String: String] = [:]
                        for (column, key) in columnKeys.enumerated() where column < values.count { lookup[key.lowercased()] = values[column] }
                        let name = line.athlete?.displayName ?? line.athlete?.shortName ?? "Unknown Player"

                        if isGoalieGroup {
                            var entry = goalies[athleteID] ?? GoalieSeasonLine(id: athleteID, displayName: name, teamAbbreviation: abbreviation,
                                                                                teamLogo: team.team.logo, headshotURL: line.athlete?.headshot?.href)
                            entry.gamesPlayed += max(statInt(lookup, "gamesplayed", "games", "gp"), 1)
                            entry.saves += statInt(lookup, "saves", "sv")
                            let shotsAgainst = statInt(lookup, "shotsagainst", "shots against", "sa")
                            entry.shotsAgainst += shotsAgainst
                            entry.goalsAgainst += statInt(lookup, "goalsagainst", "goals against", "ga")
                            entry.shutouts += statInt(lookup, "shutouts", "so")
                            var hadDecision = false
                            switch (lookup["decision"] ?? lookup["result"] ?? "").lowercased() {
                            case "w", "win": entry.wins += 1; hadDecision = true
                            case "l", "loss": entry.losses += 1; hadDecision = true
                            case "otl", "ol", "sol": entry.otLosses += 1; hadDecision = true
                            default: break
                            }
                            goalies[athleteID] = entry
                            goalieLines.append((athleteID, timeOnIceSeconds(lookup), shotsAgainst, hadDecision))
                        } else {
                            var entry = skaters[athleteID] ?? SkaterSeasonLine(id: athleteID, displayName: name, teamAbbreviation: abbreviation,
                                                                               teamLogo: team.team.logo, headshotURL: line.athlete?.headshot?.href,
                                                                               position: line.athlete?.position?.abbreviation ?? "")
                            entry.gamesPlayed += 1
                            entry.goals += statInt(lookup, "goals")
                            entry.assists += statInt(lookup, "assists")
                            skaters[athleteID] = entry
                        }
                    }
                }
            }

            if !goalieLines.contains(where: { $0.hadDecision }),
               let primary = goalieLines.max(by: { ($0.toi, $0.shotsAgainst) < ($1.toi, $1.shotsAgainst) }),
               var entry = goalies[primary.id] {
                if teamScore > opponentScore { entry.wins += 1 }
                else if wentToOvertime { entry.otLosses += 1 }
                else { entry.losses += 1 }
                goalies[primary.id] = entry
            }
        }

        func better(_ a: SkaterSeasonLine, _ b: SkaterSeasonLine) -> Bool {
            a.points != b.points ? a.points > b.points : (a.goals != b.goals ? a.goals > b.goals : a.displayName < b.displayName)
        }
        let forwardPositions: Set<String> = ["C", "LW", "RW", "L", "R", "W", "F"]
        let all = Array(skaters.values)
        return TeamPlayerSummary(
            forwards: Array(all.filter { forwardPositions.contains($0.position.uppercased()) }.sorted(by: better).prefix(3)),
            defense: Array(all.filter { $0.position.uppercased() == "D" }.sorted(by: better).prefix(3)),
            goalies: Array(goalies.values.sorted { $0.gamesPlayed != $1.gamesPlayed ? $0.gamesPlayed > $1.gamesPlayed : $0.wins > $1.wins }.prefix(2))
        )
    }

    // MARK: Lines
    // ESPN has no published line combinations, so lines are built from the players who dressed, ordered by ice time:
    // the top three forwards by ice time are line one, the top two defencemen are the first pair, and so on.
    func lineup(from groups: [ESPNGameSummary.ESPNBoxscore.ESPNBoxscorePlayerGroup], teamID: String) -> TeamLineup? {
        let forwardPositions: Set<String> = ["C", "LW", "RW", "L", "R", "W", "F"]
        var forwards: [(LineupPlayer, Int)] = []
        var defence: [(LineupPlayer, Int)] = []
        var goalies: [(LineupPlayer, Int)] = []

        for group in groups where group.team?.id == teamID {
            for category in group.statistics ?? [] {
                let categoryName = category.name?.lowercased() ?? ""
                let isGoalieGroup = categoryName.contains("goal") || categoryName.contains("netminder") || categoryName.contains("goaltender")
                let columnKeys = (category.keys?.isEmpty == false ? category.keys! : (category.labels ?? []))
                for line in category.athletes ?? [] {
                    guard let athleteID = line.athlete?.id else { continue }
                    var lookup: [String: String] = [:]
                    for (index, key) in columnKeys.enumerated() where index < (line.stats?.count ?? 0) {
                        lookup[key.lowercased()] = line.stats?[index]
                    }
                    let seconds = timeOnIceSeconds(lookup)
                    let position = (line.athlete?.position?.abbreviation ?? "").uppercased()
                    let player = LineupPlayer(id: athleteID, name: line.athlete?.displayName ?? line.athlete?.shortName ?? "Unknown",
                                              position: isGoalieGroup ? "G" : position,
                                              timeOnIce: seconds > 0 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "")
                    if isGoalieGroup { goalies.append((player, seconds)) }
                    else if position == "D" { defence.append((player, seconds)) }
                    else if forwardPositions.contains(position) || position.isEmpty { forwards.append((player, seconds)) }
                }
            }
        }

        func ordered(_ list: [(LineupPlayer, Int)]) -> [LineupPlayer] { list.sorted { $0.1 > $1.1 }.map(\.0) }
        func chunk(_ list: [LineupPlayer], size: Int, maxGroups: Int) -> [[LineupPlayer]] {
            var result: [[LineupPlayer]] = []
            var index = 0
            while index < list.count, result.count < maxGroups {
                result.append(Array(list[index..<min(index + size, list.count)]))
                index += size
            }
            return result
        }
        let lineup = TeamLineup(forwardLines: chunk(ordered(forwards), size: 3, maxGroups: 4),
                                defencePairs: chunk(ordered(defence), size: 2, maxGroups: 3),
                                goalies: ordered(goalies))
        return lineup.isEmpty ? nil : lineup
    }

    // The lineup for a game: the real one when the game has started, otherwise the team's last finished game.
    func gameLineup(for game: ESPNEvent, teamAbbreviation: String) -> (lineup: TeamLineup, isActual: Bool)? {
        guard let teamID = game.competitions.first?.competitors.first(where: { $0.team.threeLetterAbbreviation == teamAbbreviation })?.id else { return nil }
        if game.abstractState != "Preview", let groups = gameLineups[game.id], let actual = lineup(from: groups, teamID: teamID) {
            return (actual, true)
        }
        let date = game.systemCalendarDate ?? Date()
        guard let last = finishedGames(for: teamAbbreviation, before: date, preseason: game.isPreseasonGame).last,
              let lastTeamID = last.competitions.first?.competitors.first(where: { $0.team.threeLetterAbbreviation == teamAbbreviation })?.id,
              let groups = playerBoxscoreCache[last.id] ?? gameLineups[last.id],
              let likely = lineup(from: groups, teamID: lastTeamID) else { return nil }
        return (likely, false)
    }

    // MARK: Playoff race
    // Divisional format: the top three in each division, then the two best remaining teams in the conference.
    func playoffRace(for abbreviation: String) -> PlayoffRaceInfo? {
        guard !showPreseasonOnly, !abbreviation.isEmpty,
              let myDivision = nhlDivisionOrder.first(where: { $0.teams.contains(abbreviation) }) else { return nil }
        let entries = standings(for: gamesInSeason(containing: Date())).flatMap(\.entries)
        guard entries.count >= 16, let me = entries.first(where: { $0.teamAbbreviation == abbreviation }) else { return nil }

        func better(_ a: ComputedStandingEntry, _ b: ComputedStandingEntry) -> Bool {
            if a.points != b.points { return a.points > b.points }
            return a.wins != b.wins ? a.wins > b.wins : a.gamesPlayed < b.gamesPlayed
        }
        let conferenceTeams = Set(nhlDivisionOrder.filter { $0.conference == myDivision.conference }.flatMap(\.teams))
        let conferenceEntries = entries.filter { conferenceTeams.contains($0.teamAbbreviation) }
        var qualified = Set<String>()
        for division in nhlDivisionOrder where division.conference == myDivision.conference {
            let top = conferenceEntries.filter { division.teams.contains($0.teamAbbreviation) }.sorted(by: better).prefix(3)
            top.forEach { qualified.insert($0.teamAbbreviation) }
        }
        let leftovers = conferenceEntries.filter { !qualified.contains($0.teamAbbreviation) }.sorted(by: better)
        let wildCards = Array(leftovers.prefix(2))
        wildCards.forEach { qualified.insert($0.teamAbbreviation) }
        let chasers = Array(leftovers.dropFirst(2))
        guard let lastWildCard = wildCards.last, let firstOut = chasers.first else { return nil }

        let gamesLeft = max(82 - me.gamesPlayed, 0)
        if qualified.contains(abbreviation) {
            let lead = me.points - firstOut.points
            let chaserBest = firstOut.points + 2 * max(82 - firstOut.gamesPlayed, 0)
            let magic = chaserBest - me.points + 1
            let detail = magic <= 0 ? "Playoff spot clinched" : "Magic number \(magic) · \(gamesLeft) games left"
            return PlayoffRaceInfo(inPlayoffSpot: true,
                                   headline: "In a playoff spot · \(lead >= 0 ? "+" : "")\(lead) pts on the first team out",
                                   detail: detail)
        }
        let behind = lastWildCard.points - me.points
        let inHand = lastWildCard.gamesPlayed - me.gamesPlayed
        let handText = inHand > 0 ? "\(inHand) game\(inHand == 1 ? "" : "s") in hand" : (inHand < 0 ? "\(-inHand) game\(inHand == -1 ? "" : "s") fewer in hand" : "same games played")
        return PlayoffRaceInfo(inPlayoffSpot: false,
                               headline: "\(max(behind, 0)) pts behind the last wild card",
                               detail: "\(handText) · \(gamesLeft) games left")
    }
}
