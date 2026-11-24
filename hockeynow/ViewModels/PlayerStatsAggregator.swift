import Foundation

// MARK: - Player Leaderboard Aggregation
extension ESPNNHLFetcher {
    func refreshPlayerLeaders() async {
        let requestToken = UUID()
        playerLeadersRefreshToken = requestToken
        isLoadingPlayerStats = true
        
        await loadSeasonIfNeeded(for: playersDate)
        guard playerLeadersRefreshToken == requestToken else { return }
        
        let completedGameIDs = gamesInSeason(containing: playersDate).filter { game in
            guard game.status.type.state == "post", showPreseasonOnly ? game.isPreseasonGame : !game.isPreseasonGame, let eventDate = game.systemCalendarDate else { return false }
            return eventDate <= playersDate
        }.map { $0.id }
        
        let missingIDs = completedGameIDs.filter { playerBoxscoreCache[$0] == nil }

        if missingIDs.isEmpty {
            publishTally(for: completedGameIDs, requestToken: requestToken)
        } else {
            playerStatsLoadProgress = (0, missingIDs.count)
            var completedCount = 0
            let concurrencyLimit = 10
            var index = 0
            var chunkNumber = 0
            while index < missingIDs.count {
                guard playerLeadersRefreshToken == requestToken else { return }
                let chunkEnd = min(index + concurrencyLimit, missingIDs.count)
                let chunk = Array(missingIDs[index..<chunkEnd])
                await withTaskGroup(of: (String, [ESPNGameSummary.ESPNBoxscore.ESPNBoxscorePlayerGroup]?).self) { group in
                    for gameID in chunk {
                        group.addTask { (gameID, await Self.fetchPlayerBoxscoreGroups(for: gameID)) }
                    }
                    for await (gameID, groups) in group {
                        self.playerBoxscoreCache[gameID] = groups ?? []
                        completedCount += 1
                    }
                }
                // Update progress once per batch (not per game) so the app isn't redrawn dozens of times a second.
                self.playerStatsLoadProgress = (completedCount, missingIDs.count)
                index = chunkEnd
                chunkNumber += 1
                guard playerLeadersRefreshToken == requestToken else { return }
                if chunkNumber % 5 == 0 {
                    publishTally(for: completedGameIDs.filter { playerBoxscoreCache[$0] != nil }, requestToken: requestToken)
                }
            }
            guard playerLeadersRefreshToken == requestToken else { return }
            publishTally(for: completedGameIDs.filter { playerBoxscoreCache[$0] != nil }, requestToken: requestToken)
        }
        
        guard playerLeadersRefreshToken == requestToken else { return }
        isLoadingPlayerStats = false
        playerStatsLoadProgress = nil
        hasLoadedPlayerLeaders = !gamesInSeason(containing: playersDate).isEmpty
    }
    
    private func publishTally(for gameIDs: [String], requestToken: UUID) {
        var skaterTally: [String: SkaterSeasonLine] = [:]
        var goalieTally: [String: GoalieSeasonLine] = [:]
        let gamesByID = Dictionary(gamesInSeason(containing: playersDate).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        
        for gameID in gameIDs {
            guard let groups = playerBoxscoreCache[gameID], !groups.isEmpty else { continue }
            let sourceGame = gamesByID[gameID]
            
            for group in groups {
                let teamID = group.team?.id
                let teamCompetitor = sourceGame?.competitions.first?.competitors.first(where: { $0.id == teamID })
                let teamAbbr = teamCompetitor?.team.threeLetterAbbreviation ?? ""
                let teamLogo = teamCompetitor?.team.logo
                // ESPN's boxscore has no W / L / OTL column, so goalie decisions are derived from the final score.
                let opponentCompetitor = sourceGame?.competitions.first?.competitors.first(where: { $0.id != teamID })
                let teamScore = Int(teamCompetitor?.score ?? "")
                let opponentScore = Int(opponentCompetitor?.score ?? "")
                let statusDetail = sourceGame?.status.type.detail.uppercased() ?? ""
                let wentToOvertime = (sourceGame?.status.period ?? 3) > 3 || statusDetail.contains("OT") || statusDetail.contains("/SO")
                var teamGoalieLines: [(id: String, toi: Int, shotsAgainst: Int, providedDecision: Bool, providedShutout: Bool)] = []
                
                for category in group.statistics ?? [] {
                    let columnKeys = (category.keys?.isEmpty == false ? category.keys! : (category.labels ?? []))
                    let categoryName = category.name?.lowercased() ?? ""
                    let isGoalieGroup = categoryName.contains("goal") || categoryName.contains("netminder") || categoryName.contains("goaltender")
                    
                    for line in category.athletes ?? [] {
                        guard let athleteID = line.athlete?.id, let values = line.stats, !values.isEmpty else { continue }
                        var lookup: [String: String] = [:]
                        for (colIndex, key) in columnKeys.enumerated() where colIndex < values.count {
                            lookup[key.lowercased()] = values[colIndex]
                        }
                        let name = line.athlete?.displayName ?? line.athlete?.shortName ?? "Unknown Player"
                        
                        if isGoalieGroup {
                            var entry = goalieTally[athleteID] ?? GoalieSeasonLine(id: athleteID, displayName: name, teamAbbreviation: teamAbbr, teamLogo: teamLogo, headshotURL: line.athlete?.headshot?.href)
                            if !teamAbbr.isEmpty { entry.teamAbbreviation = teamAbbr; entry.teamLogo = teamLogo }
                            let appearances = max(statInt(lookup, "gamesplayed", "games", "gp"), 1)
                            entry.gamesPlayed += appearances
                            entry.saves += statInt(lookup, "saves", "sv")
                            let shotsAgainstValue = statInt(lookup, "shotsagainst", "shots against", "sa")
                            entry.shotsAgainst += shotsAgainstValue
                            entry.goalsAgainst += statInt(lookup, "goalsagainst", "goals against", "ga")
                            let suppliedShutouts = statInt(lookup, "shutouts", "so")
                            entry.shutouts += suppliedShutouts
                            let suppliedWins = statInt(lookup, "wins", "w")
                            let suppliedLosses = statInt(lookup, "losses", "l")
                            let suppliedOTLosses = statInt(lookup, "overtimeLosses", "otl", "ol")
                            entry.wins += suppliedWins
                            entry.losses += suppliedLosses
                            entry.otLosses += suppliedOTLosses
                            var providedDecision = (suppliedWins + suppliedLosses + suppliedOTLosses) > 0
                            switch (lookup["decision"] ?? lookup["result"] ?? "").lowercased() {
                            case "w", "win": entry.wins += 1; providedDecision = true
                            case "l", "loss": entry.losses += 1; providedDecision = true
                            case "otl", "ol", "sol": entry.otLosses += 1; providedDecision = true
                            default: break
                            }
                            goalieTally[athleteID] = entry
                            teamGoalieLines.append((athleteID, timeOnIceSeconds(lookup), shotsAgainstValue, providedDecision, suppliedShutouts > 0))
                        } else {
                            var entry = skaterTally[athleteID] ?? SkaterSeasonLine(id: athleteID, displayName: name, teamAbbreviation: teamAbbr, teamLogo: teamLogo, headshotURL: line.athlete?.headshot?.href, position: line.athlete?.position?.abbreviation ?? "")
                            if !teamAbbr.isEmpty { entry.teamAbbreviation = teamAbbr; entry.teamLogo = teamLogo }
                            entry.gamesPlayed += 1
                            entry.goals += statInt(lookup, "goals")
                            entry.assists += statInt(lookup, "assists")
                            skaterTally[athleteID] = entry
                        }
                    }
                }

                // The goalie with the most ice time takes the decision for his team.
                if let primary = teamGoalieLines.filter({ !$0.providedDecision }).max(by: { ($0.toi, $0.shotsAgainst) < ($1.toi, $1.shotsAgainst) }),
                   let teamScore, let opponentScore, var entry = goalieTally[primary.id] {
                    if teamScore > opponentScore {
                        entry.wins += 1
                    } else if teamScore < opponentScore {
                        if wentToOvertime { entry.otLosses += 1 } else { entry.losses += 1 }
                    }
                    goalieTally[primary.id] = entry
                }
                // A shutout counts only when one goalie played the whole game and the opponent never scored.
                if teamGoalieLines.count == 1, let only = teamGoalieLines.first, !only.providedShutout,
                   let opponentScore, opponentScore == 0, var entry = goalieTally[only.id] {
                    entry.shutouts += 1
                    goalieTally[only.id] = entry
                }
            }
        }
        
        guard playerLeadersRefreshToken == requestToken else { return }
        self.skaterLeaders = skaterTally.values.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            return $0.goals > $1.goals
        }
        self.goalieLeaders = goalieTally.values.sorted {
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            return $0.savePercentage > $1.savePercentage
        }
    }
    
    func loadPlayerLeadersIfNeeded() {
        guard !hasLoadedPlayerLeaders && !isLoadingPlayerStats else { return }
        Task { await refreshPlayerLeaders() }
    }
    
    // Finished games are read from disk when they have been saved before, and saved after the first download.
    nonisolated static func fetchPlayerBoxscoreGroups(for gameID: String) async -> [ESPNGameSummary.ESPNBoxscore.ESPNBoxscorePlayerGroup]? {
        typealias Groups = [ESPNGameSummary.ESPNBoxscore.ESPNBoxscorePlayerGroup]
        if let saved = FinalGameStore.load(Groups.self, kind: "boxscore", id: gameID), !saved.isEmpty { return saved }
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/summary?event=\(gameID)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(ESPNGameSummary.self, from: data)
            if let groups = decoded.boxscore?.players, !groups.isEmpty {
                FinalGameStore.save(groups, kind: "boxscore", id: gameID)
            }
            return decoded.boxscore?.players
        } catch {
            return nil
        }
    }
}

func statInt(_ lookup: [String: String], _ keys: String...) -> Int {
    for key in keys {
        guard let raw = lookup[key] else { continue }
        let cleaned = raw.replacingOccurrences(of: "%", with: "")
        if let intVal = Int(cleaned) { return intVal }
        if let dblVal = Double(cleaned) { return Int(dblVal) }
    }
    return 0
}

// "MM:SS" (or plain minutes) -> seconds, for working out which goalie played most of a game.
func timeOnIceSeconds(_ lookup: [String: String]) -> Int {
    guard let raw = lookup["timeonice"] ?? lookup["toi"] ?? lookup["time on ice"] else { return 0 }
    let parts = raw.split(separator: ":").compactMap { Int($0) }
    switch parts.count {
    case 2: return parts[0] * 60 + parts[1]
    case 1: return parts[0] * 60
    default: return 0
    }
}
