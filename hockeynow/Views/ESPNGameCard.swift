import SwiftUI

struct ESPNGameCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var detailTab: GameDetailTab = .goals
    let game: ESPNEvent; let currentLanguage: AppLanguage; @ObservedObject var fetcher: ESPNNHLFetcher
    let isOpen: Bool; let toggleClick: () -> Void
    var showDate: Bool = false
    @AppStorage("favorite_team_abbreviation") private var favouriteTeamAbbreviation = ""
    @AppStorage("app_theme") private var storedTheme = AppTheme.system.rawValue

    private var favouriteTeamIsHome: Bool {
        guard !favouriteTeamAbbreviation.isEmpty else { return false }
        return liveGameData.homeTeam?.team.threeLetterAbbreviation == favouriteTeamAbbreviation
            && liveGameData.awayTeam?.team.threeLetterAbbreviation != favouriteTeamAbbreviation
    }

    private var involvesFavouriteTeam: Bool {
        guard !favouriteTeamAbbreviation.isEmpty else { return false }
        return liveGameData.awayTeam?.team.threeLetterAbbreviation == favouriteTeamAbbreviation
            || liveGameData.homeTeam?.team.threeLetterAbbreviation == favouriteTeamAbbreviation
    }

    private var isPinnedToTicker: Bool { fetcher.pinnedGameInstance?.id == game.id }
    private var isNotchedHUD: Bool { fetcher.notchedGameInstance?.id == game.id }
    private var liveGameData: ESPNEvent { fetcher.applyCachedStats(to: fetcher.rawFetchedGames.first(where: { $0.id == game.id }) ?? game) }

    private var linescoreTotals: (away: [Int], home: [Int]) {
        guard let awayID = liveGameData.awayTeam?.id, let homeID = liveGameData.homeTeam?.id else { return ([0,0,0], [0,0,0]) }
        let currentPeriodParam = liveGameData.status.period ?? 1
        let arraySize = max(3, currentPeriodParam)
        var awayP = Array(repeating: 0, count: arraySize); var homeP = Array(repeating: 0, count: arraySize)

        guard let plays = fetcher.scoringSummaries[game.id], !plays.isEmpty else {
            return (awayP, homeP)
        }

        for play in plays {
            let pIdx = play.period.number - 1
            if pIdx >= 0 && pIdx < arraySize {
                if let teamID = play.team?.id {
                    if teamID == awayID { awayP[pIdx] += 1 } else if teamID == homeID { homeP[pIdx] += 1 }
                } else {
                    let txt = play.text.lowercased()
                    if txt.contains(awayID.lowercased()) || txt.contains(liveGameData.awayTeam?.team.threeLetterAbbreviation.lowercased() ?? "") { awayP[pIdx] += 1 }
                    else { homeP[pIdx] += 1 }
                }
            }
        }
        return (awayP, homeP)
    }

    private func parseTeamStat(stats: [ESPNEvent.ESPNCompetitor.ESPNStatistic]?, teamID: String, gameID: String, name: String) -> String {
        var runningStats = stats

        if (runningStats == nil || runningStats!.isEmpty), let fallbackCache = fetcher.historicalTelemetryCache[gameID], let cachedStats = fallbackCache[teamID] {
            runningStats = cachedStats
        }

        guard let validStats = runningStats else { return "-" }

        if name == "faceoffsWonPercent" {
            if let directPercent = validStats.first(where: { $0.name == "faceoffPercent" || $0.name == "faceoffsWonPercent" })?.displayValue {
                return directPercent
            }
            if let won = validStats.first(where: { $0.name == "faceoffsWon" })?.displayValue,
               let total = validStats.first(where: { $0.name == "faceoffs" || $0.name == "totalFaceoffs" })?.displayValue,
               let wD = Double(won), let tD = Double(total), tD > 0 {
                return String(format: "%.1f", (wD / tD) * 100.0)
            }
        }

        if name == "shotsTotal" {
            let shotKeys: Set<String> = ["shotstotal", "shots", "totalshots", "shotsongoal"]
            if let match = validStats.first(where: { shotKeys.contains($0.name.lowercased()) })?.displayValue {
                return match
            }
        }

        return validStats.first(where: { $0.name == name || $0.name.lowercased() == name.lowercased() })?.displayValue ?? "-"
    }

    var body: some View {
        let activeAway = liveGameData.awayTeam
        let activeHome = liveGameData.homeTeam

        VStack(spacing: 0) {
            Button(action: toggleClick) {
                VStack(spacing: 12) {
                    if liveGameData.abstractState == "Live" || liveGameData.abstractState == "Final" {
                        HStack(spacing: 0) {
                            Spacer()
                            HStack(spacing: 12) {
                                let goalsMatrix = linescoreTotals
                                ForEach(0..<goalsMatrix.away.count, id: \.self) { pNum in
                                    VStack(spacing: 2) {
                                        Text({
                                            let period = pNum + 1
                                            if period <= 3 { return "P\(period)" }
                                            if period == 4 { return "OT" }
                                            return liveGameData.isPlayoffGame ? "\(period - 3)OT" : (period == 5 ? "SO" : "OT")
                                        }()).font(.system(size: 8, weight: .black, design: .monospaced)).foregroundColor(.secondary.opacity(0.8))
                                        Text("\(goalsMatrix.away[pNum])–\(goalsMatrix.home[pNum])").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.primary)
                                    }
                                }
                            }
                        }.padding(.horizontal, 4)
                    }

                    HStack(spacing: 0) {
                        if let away = activeAway {
                            HStack(spacing: 8) {
                                TeamLogoView(logoURLString: away.team.logo, teamAbbreviation: away.team.threeLetterAbbreviation, size: 28)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(away.team.threeLetterAbbreviation).font(.system(size: 20, weight: .black, design: .monospaced)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                    Text(away.team.safeDisplayName).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.75).truncationMode(.tail)
                                }.frame(maxWidth: 92, alignment: .leading)
                                if liveGameData.abstractState == "Live" && liveGameData.powerPlayTeamID == away.id {
                                    Text("PP").font(.system(size: 9, weight: .black, design: .monospaced)).padding(.horizontal, 4).padding(.vertical, 2).background(Color.amber).foregroundColor(.black).cornerRadius(3)
                                }
                                Spacer()
                                HStack(spacing: 14) {
                                    if liveGameData.abstractState == "Live" || liveGameData.abstractState == "Final" {
                                        let cachedAwaySOG = parseTeamStat(stats: away.statistics, teamID: away.id, gameID: game.id, name: "shotsTotal")
                                        Text(cachedAwaySOG != "-" ? "\(cachedAwaySOG) SOG" : "\(away.shotsOnGoal) SOG").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.primary.opacity(0.8)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                    }
                                    Text(away.score.isEmpty ? "0" : away.score).font(.system(size: 26, weight: .black, design: .monospaced)).fixedSize().layoutPriority(1)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text({
                            if liveGameData.status.type.state == "in" {
                                let period = liveGameData.status.period ?? 1
                                if period > 4 { return liveGameData.isPlayoffGame ? "LIVE/\(period - 3)OT" : "LIVE/SO" }
                                return period >= 4 ? "LIVE/OT" : "LIVE"
                            } else {
                                if liveGameData.status.type.detail.uppercased().contains("OT") { return "FINAL/OT" }
                                if liveGameData.status.type.detail.uppercased().contains("SO") || liveGameData.status.type.detail.uppercased().contains("SHOOTOUT") { return "FINAL/SO" }
                                return liveGameData.abstractState == "Final" ? "FINAL" : "PREV"
                            }
                        }())
                        .font(.system(size: 10, weight: .black, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 4).background(liveGameData.abstractState == "Live" ? Color.red : Color.primary.opacity(0.12)).foregroundColor(liveGameData.abstractState == "Live" ? .white : .primary.opacity(0.8)).cornerRadius(4).frame(width: 85, alignment: .center)

                        if let home = activeHome {
                            HStack(spacing: 0) {
                                HStack(spacing: 14) {
                                    Text(home.score.isEmpty ? "0" : home.score).font(.system(size: 26, weight: .black, design: .monospaced)).fixedSize().layoutPriority(1)
                                    if liveGameData.abstractState == "Live" || liveGameData.abstractState == "Final" {
                                        let cachedHomeSOG = parseTeamStat(stats: home.statistics, teamID: home.id, gameID: game.id, name: "shotsTotal")
                                        Text(cachedHomeSOG != "-" ? "\(cachedHomeSOG) SOG" : "\(home.shotsOnGoal) SOG").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.primary.opacity(0.8)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                    }
                                }
                                Spacer()
                                if liveGameData.abstractState == "Live" && liveGameData.powerPlayTeamID == home.id {
                                    Text("PP").font(.system(size: 9, weight: .black, design: .monospaced)).padding(.horizontal, 4).padding(.vertical, 2).background(Color.amber).foregroundColor(.black).cornerRadius(3).padding(.trailing, 4)
                                }

                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(home.team.threeLetterAbbreviation).font(.system(size: 20, weight: .black, design: .monospaced)).multilineTextAlignment(.trailing).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                    Text(home.team.safeDisplayName).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.secondary).multilineTextAlignment(.trailing).lineLimit(1).minimumScaleFactor(0.75).truncationMode(.tail)
                                }
                                .frame(maxWidth: 92, alignment: .trailing)
                                .padding(.trailing, 8)

                                TeamLogoView(logoURLString: home.team.logo, teamAbbreviation: home.team.threeLetterAbbreviation, size: 28)
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    HStack {
                        Spacer()
                        Text(getConvertedTime(isoString: liveGameData.date, detailText: liveGameData.status.type.detail)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(liveGameData.abstractState == "Live" ? .red : .secondary)
                        Spacer()
                    }

                    if liveGameData.abstractState == "Live", let strength = fetcher.resolvedStrength(for: liveGameData),
                       let badge = strength.badgeText(awayAbbr: activeAway?.team.threeLetterAbbreviation ?? "AWY", homeAbbr: activeHome?.team.threeLetterAbbreviation ?? "HOM") {
                        Text(badge.uppercased())
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.amber)).foregroundColor(.black)
                    }

                    if let venueText = liveGameData.venueDisplayText {
                        HStack {
                            Spacer()
                            Image(systemName: "mappin.and.ellipse").font(.system(size: 9))
                            Text(venueText).font(.system(size: 10, design: .monospaced))
                            Spacer()
                        }.foregroundColor(.secondary)
                    }
                }.padding(.vertical, 14).padding(.horizontal, 16).background(Color.primary.opacity(isOpen ? 0.06 : 0.02))
            }.buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Button(action: { fetcher.pinnedGameInstance = isPinnedToTicker ? nil : liveGameData; fetcher.updateStatusString() }) {
                            HStack(spacing: 5) {
                                Image(systemName: isPinnedToTicker ? "checkmark.square.fill" : "square").foregroundColor(isPinnedToTicker ? .blue : .secondary)
                                Text("Menu Pin").font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                        }.buttonStyle(.plain)
                        Button(action: {
                            withAnimation(.spring()) {
                                fetcher.notchedGameInstance = isNotchedHUD ? nil : liveGameData
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: isNotchedHUD ? "checkmark.square.fill" : "square").foregroundColor(isNotchedHUD ? .blue : .secondary)
                                Text("Notch Pin").font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        Button(action: { DetachableTickerWindowManager.shared.spawnTickerWindow(for: liveGameData, fetcher: fetcher) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "macwindow.on.rectangle")
                                Text("Overlay HUD").font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.blue)
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, 18).padding(.top, 4)

                    Color.white.opacity(0.12).frame(height: 1).padding(.horizontal, 18)

                    if liveGameData.abstractState == "Live" || liveGameData.abstractState == "Final" {
                        GameStatBarsView(game: liveGameData, fetcher: fetcher)
                            .padding(.horizontal, 18)

                        Color.white.opacity(0.12).frame(height: 1).padding(.horizontal, 18)
                    }

                    if liveGameData.abstractState == "Preview", let previewAway = activeAway, let previewHome = activeHome {
                        WinProbabilityBarView(game: liveGameData, fetcher: fetcher)
                            .padding(.horizontal, 18)
                        PreviewInsightsView(game: liveGameData, fetcher: fetcher)
                            .padding(.horizontal, 18)
                        Color.white.opacity(0.12).frame(height: 1).padding(.horizontal, 18)
                        PreviewLeadersSlider(away: previewAway, home: previewHome, fetcher: fetcher)
                            .padding(.horizontal, 18)
                    } else {
                    VStack(spacing: 12) {
                        let totalPeriodsParam = liveGameData.status.period ?? 3
                        ForEach(1...max(3, totalPeriodsParam), id: \.self) { pNum in
                            PeriodTimelineView(
                                periodNumber: pNum, currentClockString: liveGameData.status.displayClock ?? "20:00", currentClockValue: liveGameData.status.clock,
                                plays: fetcher.scoringSummaries[liveGameData.id] ?? [], awayAbbr: activeAway?.team.threeLetterAbbreviation ?? "AWY", homeAbbr: activeHome?.team.threeLetterAbbreviation ?? "HOM",
                                awayID: activeAway?.id ?? "1", homeID: activeHome?.id ?? "2", abstractGameState: liveGameData.abstractState, currentPeriodLive: totalPeriodsParam, isPlayoff: liveGameData.isPlayoffGame
                            )
                        }
                    }.padding(.horizontal, 18)

                    if liveGameData.abstractState == "Live" {
                        Color.white.opacity(0.12).frame(height: 1).padding(.horizontal, 18)
                        WinProbabilityBarView(game: liveGameData, fetcher: fetcher)
                            .padding(.horizontal, 18)
                    }

                    if let odds = fetcher.winProbabilitySummaries[liveGameData.id], !odds.isEmpty {
                        Color.white.opacity(0.12).frame(height: 1).padding(.horizontal, 18)
                        InteractiveWinProbabilityChart(homeWinOdds: odds)
                            .padding(.horizontal, 18)
                    }

                    Color.white.opacity(0.12).frame(height: 1).padding(.horizontal, 18)

                    if liveGameData.abstractState != "Final" && detailTab == .postGame {
                        Color.clear.onAppear { detailTab = .goals }.frame(height: 0)
                    }
                    Picker("", selection: $detailTab) {
                        ForEach(GameDetailTab.allCases.filter { $0 != .postGame || liveGameData.abstractState == "Final" }) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 18)

                    if detailTab == .postGame, liveGameData.abstractState == "Final",
                       let away = activeAway, let home = activeHome {
                        PostGameSummary(
                            stars: fetcher.threeStars[liveGameData.id] ?? [],
                            nextGames: [(away.team.threeLetterAbbreviation, fetcher.nextGames[away.team.threeLetterAbbreviation]),
                                        (home.team.threeLetterAbbreviation, fetcher.nextGames[home.team.threeLetterAbbreviation])],
                            zone: fetcher.targetZone,
                            prominent: true
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                    } else if detailTab == .playByPlay {
                        PlayByPlayView(game: liveGameData, fetcher: fetcher)
                    } else if detailTab == .shots {
                        ShotMapView(game: liveGameData)
                    } else if detailTab == .lines {
                        GameLinesView(game: liveGameData, fetcher: fetcher)
                            .padding(.horizontal, 18)
                    } else if fetcher.loadingSummaries[liveGameData.id] == true && fetcher.scoringSummaries[liveGameData.id] == nil {
                        HStack { Spacer(); ProgressView().controlSize(.small); Text(currentLanguage.localize("loadingSummary")).font(.system(size: 12, design: .monospaced)); Spacer() }.padding(.vertical, 20)
                    } else {
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let plays = fetcher.scoringSummaries[liveGameData.id], !plays.isEmpty {
                                    ForEach(plays) { play in

                                        AdaptivePlayRow(
                                            play: play,
                                            awayAbbr: activeAway?.team.threeLetterAbbreviation ?? "AWY",
                                            homeAbbr: activeHome?.team.threeLetterAbbreviation ?? "HOM",
                                            awayID: activeAway?.id ?? "1",
                                            homeID: activeHome?.id ?? "2",
                                            fetcherManager: fetcher,
                                            gameID: game.id
                                        )
                                        .padding(.horizontal, 18)
                                    }
                                } else {
                                    HStack { Spacer(); Text(currentLanguage.localize("noPlays")).font(.system(size: 12, design: .monospaced)); Spacer() }.padding(.vertical, 20)
                                }
                            }
                        }.frame(maxHeight: 140)
                    }
                    }
                }
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.03))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }.background(Color.primary.opacity(0.01)).cornerRadius(8)
        .modifier(FavouriteGameHighlight(
            isFavourite: involvesFavouriteTeam,
            color: getReadableFavouriteTeamColor(abbreviation: favouriteTeamAbbreviation, theme: AppTheme(rawValue: storedTheme) ?? .system, colorScheme: colorScheme),
            onRight: favouriteTeamIsHome
        ))
        .onAppear {
            if liveGameData.abstractState != "Preview" {
                Task {
                    await fetcher.fetchDetails(for: liveGameData.id)
                    if liveGameData.abstractState == "Live" {
                        await fetcher.refreshStrength(for: liveGameData)
                    } else if liveGameData.abstractState == "Final" {
                        await fetcher.refreshPostGame(for: liveGameData)
                    }
                }
            } else {
                Task { await fetcher.fetchPregameOdds(for: liveGameData.id) }
            }
        }
    }

    func getConvertedTime(isoString: String, detailText: String) -> String {
        let actualString = detailText.isEmpty ? "00:00" : detailText
        guard let parsedDate = liveGameData.systemCalendarDate else { return actualString }
        let outgoingFormatter = HockeyNowFormatterCache.formatter(format: hockeyNowTimeFormat(), zone: fetcher.targetZone)
        let timePart = "\(outgoingFormatter.string(from: parsedDate)) \(fetcher.targetZone.abbreviation(for: parsedDate) ?? "")"
        guard showDate else { return timePart }
        let dateFormatter = DateFormatter(); dateFormatter.dateFormat = "MMM d, yyyy"; dateFormatter.timeZone = fetcher.targetZone
        return "\(dateFormatter.string(from: parsedDate))  •  \(timePart)"
    }
}
