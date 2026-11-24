import SwiftUI
import AppKit
import Combine

final class NotchState: ObservableObject {
    @Published var isExpanded = false
    @Published var banner: LiveActivityEvent?
}

struct StrengthTag: Identifiable {
    let text: String
    let fill: Color
    let ink: Color
    var id: String { text }
}

struct InteractiveNotchRootView: View {
    let away: ESPNEvent.ESPNCompetitor; let home: ESPNEvent.ESPNCompetitor; let game: ESPNEvent
    @ObservedObject var fetcher: ESPNNHLFetcher
    let notchWidth: CGFloat
    let collapsedWidth: CGFloat
    let hardwareNotchWidth: CGFloat
    let collapsedHeight: CGFloat
    let expandedHeight: CGFloat
    @ObservedObject var state: NotchState
    @State private var bodyMounted = false
    @State private var contentVisible = false
    private var isExpanded: Bool { state.isExpanded }
    private var liveGameData: ESPNEvent {
        let newest = fetcher.rawFetchedGames.first(where: { $0.id == game.id })
            ?? (fetcher.notchedGameInstance?.id == game.id ? fetcher.notchedGameInstance : nil) ?? game
        return fetcher.applyCachedStats(to: newest)
    }

    var body: some View {
        let activeAway = liveGameData.awayTeam ?? away
        let activeHome = liveGameData.homeTeam ?? home
        let isPeeking = !isExpanded && state.banner != nil
        let shapeWidth = isExpanded ? notchWidth : (isPeeking ? min(notchWidth, max(collapsedWidth, 400)) : collapsedWidth)
        let shapeHeight = isExpanded ? expandedHeight : (isPeeking ? collapsedHeight + 38 : collapsedHeight)
        let radius: CGFloat = isExpanded ? 26 : (isPeeking ? 18 : 10)

        return ZStack(alignment: .top) {
            NotchCornerShape(radius: radius).fill(Color.black)
                .frame(width: shapeWidth, height: shapeHeight)

            if isExpanded || bodyMounted {
                VStack(spacing: 0) {
                    Color.clear.frame(height: collapsedHeight)
                    expandedBody(away: activeAway, home: activeHome)
                        .frame(width: notchWidth, height: expandedHeight - collapsedHeight, alignment: .top)
                }
                .frame(width: notchWidth, height: expandedHeight, alignment: .top)
                .mask(alignment: .top) {
                    NotchCornerShape(radius: radius).frame(width: shapeWidth, height: shapeHeight)
                }
                .scaleEffect(isExpanded ? 1 : 0.94, anchor: .top)
                .opacity(contentVisible ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .transition(.identity)
            }

            header(away: activeAway, home: activeHome)
                .frame(width: shapeWidth, height: collapsedHeight)

            if let banner = state.banner {
                liveBanner(banner)
                    .padding(.top, collapsedHeight + 4)
                    .transition(.opacity)
            }
        }
        .frame(width: notchWidth, height: expandedHeight, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isExpanded)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: state.banner)
        .environment(\.colorScheme, .dark)
        .onReceive(state.$isExpanded) { expanded in
            if expanded {
                bodyMounted = true
                withAnimation(.easeOut(duration: 0.22).delay(0.12)) { contentVisible = true }
            } else {
                withAnimation(.easeIn(duration: 0.1)) { contentVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if !state.isExpanded { bodyMounted = false } }
            }
        }
        .task(id: liveGameData.abstractState) {
            switch liveGameData.abstractState {
            case "Final": await fetcher.refreshPostGame(for: liveGameData)
            case "Live": await fetcher.refreshStrength(for: liveGameData)
            case "Preview": await fetcher.fetchPregameOdds(for: liveGameData.id)
            default: break
            }
        }
    }

    private func liveBanner(_ event: LiveActivityEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: event.symbol).font(.system(size: 11, weight: .black)).foregroundColor(.black)
            Text(event.title).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundColor(.black).lineLimit(1)
            Text(event.detail).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.black.opacity(0.75)).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(event.kind == .penalty ? Color.orange : Color.amber))
        .frame(maxWidth: notchWidth - 60)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    private func header(away: ESPNEvent.ESPNCompetitor, home: ESPNEvent.ESPNCompetitor) -> some View {
        let isLive = liveGameData.abstractState == "Live"
        let showsSOG = liveGameData.abstractState != "Preview"
        let strength = isLive ? fetcher.resolvedStrength(for: liveGameData) : nil
        func tags(for side: GameStrength.Side, teamID: String) -> [StrengthTag] {
            guard isLive else { return [] }
            var result: [StrengthTag] = []
            if let strength {
                if strength.emptyNetSide == side { result.append(StrengthTag(text: "EN", fill: .red, ink: .white)) }
                if strength.powerPlaySide == side { result.append(StrengthTag(text: "PP", fill: .amber, ink: .black)) }
                else if strength.powerPlaySide != nil, isExpanded { result.append(StrengthTag(text: "PK", fill: Color.white.opacity(0.22), ink: .white)) }
            } else if liveGameData.powerPlayTeamID == teamID {
                result.append(StrengthTag(text: "PP", fill: .amber, ink: .black))
            }
            return isExpanded ? result : []
        }
        let awayTags = tags(for: .away, teamID: away.id), homeTags = tags(for: .home, teamID: home.id)
        let strengthNow = isLive ? fetcher.resolvedStrength(for: liveGameData) : nil
        let awayHot = strengthNow?.powerPlaySide == .away || (strengthNow == nil && isLive && liveGameData.powerPlayTeamID == away.id)
        let homeHot = strengthNow?.powerPlaySide == .home || (strengthNow == nil && isLive && liveGameData.powerPlayTeamID == home.id)
        let sidePadding: CGFloat = isExpanded ? 18 : 8
        return HStack(spacing: 0) {
            HStack(alignment: .center, spacing: isExpanded ? 8 : 6) {
                TeamLogoView(logoURLString: away.team.logo, teamAbbreviation: away.team.threeLetterAbbreviation, size: 16)
                    .frame(width: isExpanded ? 16 : 0).opacity(isExpanded ? 1 : 0).clipped()
                Text(away.team.threeLetterAbbreviation).font(.system(size: 15, weight: .black, design: .monospaced)).foregroundColor(awayHot ? .amber : .white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                sogSlot(for: away, alignment: .leading, show: isExpanded && showsSOG)
                Text(away.score.isEmpty ? "0" : away.score).font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.amber)
                ForEach(awayTags) { tag in strengthTag(tag.text, fill: tag.fill, ink: tag.ink) }
            }
            .padding(.leading, sidePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: hardwareNotchWidth + 8, height: 1)
            HStack(alignment: .center, spacing: isExpanded ? 8 : 6) {
                ForEach(homeTags) { tag in strengthTag(tag.text, fill: tag.fill, ink: tag.ink) }
                Text(home.score.isEmpty ? "0" : home.score).font(.system(size: 16, weight: .black, design: .monospaced)).foregroundColor(.amber)
                sogSlot(for: home, alignment: .trailing, show: isExpanded && showsSOG)
                Text(home.team.threeLetterAbbreviation).font(.system(size: 15, weight: .black, design: .monospaced)).foregroundColor(homeHot ? .amber : .white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                TeamLogoView(logoURLString: home.team.logo, teamAbbreviation: home.team.threeLetterAbbreviation, size: 16)
                    .frame(width: isExpanded ? 16 : 0).opacity(isExpanded ? 1 : 0).clipped()
            }
            .padding(.trailing, sidePadding)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    private func strengthTag(_ text: String, fill: Color, ink: Color) -> some View {
        Text(text).font(.system(size: 8, weight: .black, design: .monospaced)).padding(.horizontal, 3).padding(.vertical, 1)
            .background(fill).foregroundColor(ink).cornerRadius(2)
    }

    private func sogSlot(for team: ESPNEvent.ESPNCompetitor, alignment: Alignment, show: Bool) -> some View {
        sogLabel(for: team)
            .frame(width: show ? 42 : 0, alignment: alignment)
            .clipped()
            .opacity(show && contentVisible ? 1 : 0)
            .padding(alignment == .leading ? .trailing : .leading, show ? 0 : -6)
    }

    private func sogLabel(for team: ESPNEvent.ESPNCompetitor) -> some View {
        let shotKeys: Set<String> = ["shotstotal", "shots", "totalshots", "shotsongoal"]
        func shots(in stats: [ESPNEvent.ESPNCompetitor.ESPNStatistic]?) -> String? {
            guard let stats, !stats.isEmpty else { return nil }
            return stats.first(where: { shotKeys.contains($0.name.lowercased()) })?.displayValue
        }
        let value = shots(in: team.statistics) ?? shots(in: fetcher.historicalTelemetryCache[liveGameData.id]?[team.id])
            ?? (team.shotsOnGoal.isEmpty ? "0" : team.shotsOnGoal)
        return Text("\(value) SOG")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.72))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func expandedBody(away: ESPNEvent.ESPNCompetitor, home: ESPNEvent.ESPNCompetitor) -> some View {
        if liveGameData.abstractState == "Preview" {
            previewBody(away: away, home: home)
        } else {
            gameBody(away: away, home: home)
        }
    }

    private func gameBody(away: ESPNEvent.ESPNCompetitor, home: ESPNEvent.ESPNCompetitor) -> some View {
        let isLive = liveGameData.abstractState == "Live"
        let awayAbbr = away.team.threeLetterAbbreviation, homeAbbr = home.team.threeLetterAbbreviation
        let periods = max(3, liveGameData.status.period ?? 1)
        let plays = fetcher.scoringSummaries[liveGameData.id] ?? []
        return HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                statusRow(awayAbbr: awayAbbr, homeAbbr: homeAbbr)
                VStack(spacing: 5) {
                    ForEach(1...periods, id: \.self) { pNum in
                        PeriodTimelineView(
                            periodNumber: pNum, currentClockString: liveGameData.status.displayClock ?? "20:00", currentClockValue: liveGameData.status.clock, plays: plays,
                            awayAbbr: awayAbbr, homeAbbr: homeAbbr, awayID: away.id, homeID: home.id,
                            abstractGameState: liveGameData.abstractState, currentPeriodLive: liveGameData.status.period ?? 1, compactMode: true, isPlayoff: liveGameData.isPlayoffGame
                        )
                    }
                }
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        if plays.isEmpty {
                            Text("No scoring events logged.").font(.system(size: 11, design: .monospaced)).whiteOpacityFallback()
                                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 12)
                        } else {
                            ForEach(plays) { play in
                                AdaptivePlayRow(play: play, awayAbbr: awayAbbr, homeAbbr: homeAbbr, awayID: away.id, homeID: home.id,
                                                fetcherManager: fetcher, gameID: game.id)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.05)).cornerRadius(6)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    if isLive { WinProbabilityBarView(game: liveGameData, fetcher: fetcher, compact: true, onDark: true) }
                    GameStatBarsView(game: liveGameData, fetcher: fetcher, compact: true, onDark: true)
                    if isLive {
                        LatestPlaysFeed(plays: fetcher.playByPlaySummaries[liveGameData.id] ?? [], awayID: away.id, homeID: home.id,
                                        awayColor: getGameTeamColor(abbreviation: awayAbbr, isHome: false, opponent: homeAbbr),
                                        homeColor: getGameTeamColor(abbreviation: homeAbbr, isHome: true, opponent: awayAbbr),
                                        title: "Latest plays")
                            .padding(.top, 2)
                    } else {
                        PostGameSummary(stars: fetcher.threeStars[liveGameData.id] ?? [],
                                        nextGames: [(awayAbbr, fetcher.nextGames[awayAbbr]), (homeAbbr, fetcher.nextGames[homeAbbr])],
                                        zone: fetcher.targetZone)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(width: (notchWidth - 40 - 16) * 0.44, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 30)
    }

    private func previewBody(away: ESPNEvent.ESPNCompetitor, home: ESPNEvent.ESPNCompetitor) -> some View {
        VStack(spacing: 10) {
            statusRow(awayAbbr: away.team.threeLetterAbbreviation, homeAbbr: home.team.threeLetterAbbreviation)
            WinProbabilityBarView(game: liveGameData, fetcher: fetcher, compact: true, onDark: true)
                .frame(maxWidth: 360)
            PreviewLeadersSlider(away: away, home: home, fetcher: fetcher)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 28)
    }

    private func statusRow(awayAbbr: String, homeAbbr: String) -> some View {
        let isLive = liveGameData.abstractState == "Live"
        let badge = isLive ? fetcher.resolvedStrength(for: liveGameData)?.badgeText(awayAbbr: awayAbbr, homeAbbr: homeAbbr) : nil
        return HStack(spacing: 8) {
            Text(getCompactTimeLabel(for: liveGameData))
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(isLive ? Color.red : Color.white.opacity(0.14)))
                .foregroundColor(.white)
            if let badge {
                Text(badge.uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Color.amber)).foregroundColor(.black)
                    .transition(.scale.combined(with: .opacity))
            }
            if liveGameData.abstractState == "Preview", let start = liveGameData.systemCalendarDate {
                Text("in \(hockeyNowCountdownText(until: start))").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.3), value: badge)
    }

    private func getCompactTimeLabel(for event: ESPNEvent) -> String {
        let modifier = fetcher.detectLiveGoalModifiers(for: event.id)
        if event.abstractState == "Live" {
            let clock = event.status.displayClock ?? "20:00"; let period = event.status.period ?? 1
            let detail = event.status.type.detail.lowercased()
            if detail.contains("intermission") || detail.contains("end of") {
                let names = ["1st", "2nd", "3rd"]
                let ended = names.indices.contains(period - 1) ? names[period - 1] : "period \(period)"
                return "INT (\(ended))"
            }
            let periodLabel = period <= 3 ? "P\(period)" : (period == 4 ? "OT" : (event.isPlayoffGame ? "\(period - 3)OT" : "SO"))
            return "\(periodLabel)  \(clock)\(modifier)"
        } else if event.abstractState == "Final" { return "FINAL\(modifier)" }
        else {
            guard let parsedDate = event.systemCalendarDate else { return "PREV" }
            let outgoingFormatter = HockeyNowFormatterCache.formatter(format: hockeyNowTimeFormat(), zone: fetcher.targetZone)
            return "\(outgoingFormatter.string(from: parsedDate)) \(fetcher.targetZone.abbreviation(for: parsedDate) ?? "")"
        }
    }
}

struct PostGameSummary: View {
    let stars: [ThreeStar]
    let nextGames: [(abbr: String, info: NextGameInfo?)]
    let zone: TimeZone
    var prominent = false

    private struct NextRow: Identifiable { let abbr: String; let info: NextGameInfo; var id: String { abbr } }
    private var upcoming: [NextRow] {
        nextGames.compactMap { entry in entry.info.map { NextRow(abbr: entry.abbr, info: $0) } }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: prominent ? 11 : 7, weight: .bold, design: .monospaced)).tracking(0.7).foregroundColor(.secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 16 : 9) {
            if !stars.isEmpty {
                VStack(alignment: .leading, spacing: prominent ? 10 : 4) {
                    heading("THREE STARS")
                    ForEach(stars) { star in
                        HStack(spacing: prominent ? 10 : 5) {
                            Text("★\(star.id)")
                                .font(.system(size: prominent ? 17 : 8, weight: .black, design: .monospaced))
                                .foregroundColor(.amber).frame(width: prominent ? 38 : nil, alignment: .leading)
                            PlayerHeadshotView(headshotURLString: star.headshot,
                                               initials: String(star.name.split(separator: " ").compactMap { $0.first }.prefix(2)).uppercased(),
                                               size: prominent ? 38 : 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(star.name)
                                    .font(.system(size: prominent ? 15 : 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.primary).lineLimit(1)
                                if prominent {
                                    Text("\(star.team) · \(star.position)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                                }
                            }
                            if !prominent {
                                Text("\(star.team) \(star.position)").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(star.line)
                                .font(.system(size: prominent ? 13 : 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(prominent ? .primary : .secondary)
                        }
                        .padding(.horizontal, prominent ? 12 : 0).padding(.vertical, prominent ? 9 : 0)
                        .background(prominent ? Color.primary.opacity(0.045) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: prominent ? 10 : 4) {
                    heading("NEXT GAME")
                    ForEach(upcoming) { row in
                        let info = row.info
                        HStack(spacing: prominent ? 10 : 5) {
                            Text(row.abbr).font(.system(size: prominent ? 14 : 9, weight: .bold, design: .monospaced)).foregroundColor(.primary)
                            Text("\(info.isHome ? "vs" : "@") \(info.opponent)")
                                .font(.system(size: prominent ? 14 : 9, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(hockeyNowDayWord(for: info.start, zone: zone))
                                    .font(.system(size: prominent ? 12 : 8, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
                                Text(hockeyNowClockString(for: info.start, zone: zone))
                                    .font(.system(size: prominent ? 14 : 8, weight: .bold, design: .monospaced)).foregroundColor(.primary)
                            }
                        }
                        .padding(.horizontal, prominent ? 12 : 0).padding(.vertical, prominent ? 10 : 0)
                        .background(prominent ? Color.primary.opacity(0.045) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            if stars.isEmpty && upcoming.isEmpty {
                Text("Three stars and next fixtures aren’t available yet.")
                    .font(.system(size: prominent ? 12 : 9, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(prominent ? 16 : 0)
        .background(prominent ? Color.primary.opacity(0.025) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.3), value: stars)
        .animation(.easeInOut(duration: 0.3), value: upcoming.map(\.id))
    }
}

struct LatestPlaysFeed: View {
    let plays: [ESPNPlay]
    let awayID: String
    let homeID: String
    let awayColor: Color
    let homeColor: Color
    let title: String

    private var latest: [ESPNPlay] {
        Array(plays.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(5).reversed())
    }

    private func dotColor(for play: ESPNPlay) -> Color {
        guard let id = play.team?.id else { return .white.opacity(0.25) }
        return id == awayID ? awayColor : (id == homeID ? homeColor : .white.opacity(0.25))
    }

    var body: some View {
        let items = latest
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(0.6)
                    .foregroundColor(.secondary)
                ForEach(Array(items.enumerated()), id: \.element.id) { index, play in
                    HStack(spacing: 5) {
                        Circle().fill(dotColor(for: play)).frame(width: 4, height: 4)
                        Text("\(play.period.number <= 3 ? "P\(play.period.number)" : "OT") \(play.clock.displayValue)")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(play.text)
                            .font(.system(size: 9, weight: index == 0 ? .semibold : .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(max(0.35, 0.95 - Double(index) * 0.15)))
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: items.map { $0.id })
        }
    }
}

extension View {
    func whiteOpacityFallback() -> some View { self.foregroundColor(.white.opacity(0.4)) }
}

struct NotchCornerShape: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(radius, rect.width / 2, rect.height))
        let e = min(r * 1.25, rect.width / 2, rect.height)
        let k = e * 0.28

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - e))
        path.addCurve(to: CGPoint(x: rect.maxX - e, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.maxY - k),
                      control2: CGPoint(x: rect.maxX - k, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + e, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - e),
                      control1: CGPoint(x: rect.minX + k, y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.maxY - k))
        path.closeSubpath()
        return path
    }
}
