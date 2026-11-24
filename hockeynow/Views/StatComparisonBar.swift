import SwiftUI
import AppKit

// MARK: - Model
struct StatBarModel: Identifiable {
    let id: String
    let title: String
    let awayText: String
    let homeText: String
    var awaySub: String? = nil
    var homeSub: String? = nil
    let awayShare: Double        // 0...1, the away team's portion of the bar
}

// MARK: - Bar shape (slanted inner ends, like the ESPN face-off bar)
struct SlantedBarShape: Shape {
    var leftIsSlanted: Bool
    var rightIsSlanted: Bool
    static func slant(for height: CGFloat) -> CGFloat { max(height * 1.2, 4) }

    func path(in rect: CGRect) -> Path {
        let s = min(Self.slant(for: rect.height), rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: leftIsSlanted ? rect.minX + s : rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rightIsSlanted ? rect.maxX - s : rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct SlantedSplitBar: View {
    let awayShare: Double
    let awayColor: Color
    let homeColor: Color
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let slant = SlantedBarShape.slant(for: height)
            let gap: CGFloat = 3
            let share = CGFloat(min(max(awayShare, 0.05), 0.95))
            let awayMid = share * (width - gap)                 // visible length of the away bar, measured mid-height
            let awayWidth = awayMid + slant / 2
            let homeX = awayWidth - slant + gap
            ZStack(alignment: .topLeading) {
                SlantedBarShape(leftIsSlanted: false, rightIsSlanted: true)
                    .fill(awayColor)
                    .frame(width: max(awayWidth, 0), height: height)
                SlantedBarShape(leftIsSlanted: true, rightIsSlanted: false)
                    .fill(homeColor)
                    .frame(width: max(width - homeX, 0), height: height)
                    .offset(x: homeX)
            }
            .animation(.easeInOut(duration: 0.4), value: awayShare)
        }
        .frame(height: height)
    }
}

// MARK: - Row: big numbers either side, title between, bar beneath, counts under that
struct StatComparisonBar: View {
    let model: StatBarModel
    let awayColor: Color
    let homeColor: Color
    var compact = false
    var onDark = false

    // Slightly lifted on the black notch so dark team colours stay visible, but kept calm so the goals stay the focus.
    private func tuned(_ color: Color) -> Color {
        guard onDark else { return color.opacity(0.9) }
        let base = NSColor(color)
        return Color(nsColor: base.blended(withFraction: 0.3, of: .white) ?? base).opacity(0.85)
    }

    // Same monospaced type as the rest of the app, kept small so the rows read as supporting detail.
    var body: some View {
        VStack(spacing: compact ? 3 : 4) {
            ZStack {
                HStack {
                    Text(model.awayText)
                    Spacer(minLength: 4)
                    Text(model.homeText)
                }
                .font(.system(size: compact ? 11 : 13, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                Text(model.title.uppercased())
                    .font(.system(size: compact ? 7 : 8, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            SlantedSplitBar(awayShare: model.awayShare, awayColor: tuned(awayColor), homeColor: tuned(homeColor), height: compact ? 3 : 4)
            if !compact, model.awaySub != nil || model.homeSub != nil {
                HStack {
                    Text(model.awaySub ?? "")
                    Spacer(minLength: 4)
                    Text(model.homeSub ?? "")
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - The four game-stat bars + win probability, built from a game's statistics
struct GameStatBarsView: View {
    let game: ESPNEvent
    @ObservedObject var fetcher: ESPNNHLFetcher
    var compact = false
    var onDark = false

    var body: some View {
        if let away = game.awayTeam, let home = game.homeTeam {
            let awayAbbr = away.team.threeLetterAbbreviation, homeAbbr = home.team.threeLetterAbbreviation
            let awayColor = getGameTeamColor(abbreviation: awayAbbr, isHome: false, opponent: homeAbbr)
            let homeColor = getGameTeamColor(abbreviation: homeAbbr, isHome: true, opponent: awayAbbr)
            let bars = fetcher.statBars(for: game)
            VStack(spacing: compact ? 8 : 10) {
                ForEach(bars) { StatComparisonBar(model: $0, awayColor: awayColor, homeColor: homeColor, compact: compact, onDark: onDark) }
            }
        }
    }
}

struct WinProbabilityBarView: View {
    let game: ESPNEvent
    @ObservedObject var fetcher: ESPNNHLFetcher
    var compact = false
    var onDark = false

    var body: some View {
        if let away = game.awayTeam, let home = game.homeTeam, let reading = fetcher.winProbabilityReading(for: game) {
            let awayAbbr = away.team.threeLetterAbbreviation, homeAbbr = home.team.threeLetterAbbreviation
            let homePct = Int((reading.homeFraction * 100).rounded())
            let title = (reading.isPregame ? "Pre-game win %" : "Win probability") + (reading.isEstimate ? " · est." : "")
            StatComparisonBar(
                model: StatBarModel(id: "winprob", title: title, awayText: "\(100 - homePct)%", homeText: "\(homePct)%",
                                    awaySub: awayAbbr, homeSub: homeAbbr, awayShare: 1 - reading.homeFraction),
                awayColor: getGameTeamColor(abbreviation: awayAbbr, isHome: false, opponent: homeAbbr),
                homeColor: getGameTeamColor(abbreviation: homeAbbr, isHome: true, opponent: awayAbbr),
                compact: compact, onDark: onDark)
        }
    }
}

// MARK: - Reading stats
extension ESPNNHLFetcher {
    private func normalizedStatName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func stats(for game: ESPNEvent, teamID: String?) -> [ESPNEvent.ESPNCompetitor.ESPNStatistic] {
        guard let teamID else { return [] }
        let direct = game.competitions.first?.competitors.first(where: { $0.id == teamID })?.statistics ?? []
        if !direct.isEmpty { return direct }
        return historicalTelemetryCache[game.id]?[teamID] ?? []
    }

    private func number(_ stats: [ESPNEvent.ESPNCompetitor.ESPNStatistic], _ keys: [String]) -> Double? {
        let wanted = Set(keys.map(normalizedStatName))
        for stat in stats where wanted.contains(normalizedStatName(stat.name)) {
            let cleaned = stat.displayValue.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            if let value = Double(cleaned) { return value }
        }
        return nil
    }

    // "1/3" style values (goals / opportunities).
    private func fraction(_ stats: [ESPNEvent.ESPNCompetitor.ESPNStatistic], _ keys: [String]) -> (Double, Double)? {
        let wanted = Set(keys.map(normalizedStatName))
        for stat in stats where wanted.contains(normalizedStatName(stat.name)) {
            let parts = stat.displayValue.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) { return (a, b) }
        }
        return nil
    }

    private func share(_ away: Double, _ home: Double) -> Double { away + home > 0 ? away / (away + home) : 0.5 }
    private func whole(_ value: Double) -> String { String(Int(value.rounded())) }

    func statBars(for game: ESPNEvent) -> [StatBarModel] {
        let a = stats(for: game, teamID: game.awayTeam?.id), h = stats(for: game, teamID: game.homeTeam?.id)
        var bars: [StatBarModel] = []

        // Face-offs: percentage big, "won/total" underneath.
        let awayWon = number(a, ["faceoffsWon", "faceoffWon"]), homeWon = number(h, ["faceoffsWon", "faceoffWon"])
        if let aw = awayWon, let hw = homeWon, aw + hw > 0 {
            let total = aw + hw
            bars.append(StatBarModel(id: "faceoffs", title: "Face-off %",
                                     awayText: String(format: "%.1f%%", aw / total * 100), homeText: String(format: "%.1f%%", hw / total * 100),
                                     awaySub: "\(whole(aw))/\(whole(total))", homeSub: "\(whole(hw))/\(whole(total))", awayShare: aw / total))
        } else if let ap = number(a, ["faceoffPercent", "faceoffsWonPercent"]) ?? number(h, ["faceoffPercent", "faceoffsWonPercent"]).map({ 100 - $0 }) {
            let hp = number(h, ["faceoffPercent", "faceoffsWonPercent"]) ?? (100 - ap)
            bars.append(StatBarModel(id: "faceoffs", title: "Face-off %", awayText: String(format: "%.1f%%", ap), homeText: String(format: "%.1f%%", hp), awayShare: ap / 100))
        }

        // Power plays: goals/opportunities big; the bar shows who has had more chances.
        let agoals = number(a, ["powerPlayGoals"]), hgoals = number(h, ["powerPlayGoals"])
        var aopp = number(a, ["powerPlayOpportunities", "powerPlays"]), hopp = number(h, ["powerPlayOpportunities", "powerPlays"])
        var ag = agoals, hg = hgoals
        if let af = fraction(a, ["powerPlay"]), let hf = fraction(h, ["powerPlay"]) { ag = af.0; aopp = af.1; hg = hf.0; hopp = hf.1 }
        if ag != nil || hg != nil || aopp != nil {
            let awayText = aopp != nil ? "\(whole(ag ?? 0))/\(whole(aopp ?? 0))" : whole(ag ?? 0)
            let homeText = hopp != nil ? "\(whole(hg ?? 0))/\(whole(hopp ?? 0))" : whole(hg ?? 0)
            let barShare = (aopp ?? 0) + (hopp ?? 0) > 0 ? share(aopp ?? 0, hopp ?? 0) : share(ag ?? 0, hg ?? 0)
            bars.append(StatBarModel(id: "powerplays", title: "Power plays", awayText: awayText, homeText: homeText, awayShare: barShare))
        }

        if let ah = number(a, ["hits"]), let hh = number(h, ["hits"]) {
            bars.append(StatBarModel(id: "hits", title: "Hits", awayText: whole(ah), homeText: whole(hh), awayShare: share(ah, hh)))
        }
        if let ab = number(a, ["blockedShots", "blocks"]), let hb = number(h, ["blockedShots", "blocks"]) {
            bars.append(StatBarModel(id: "blocks", title: "Blocked shots", awayText: whole(ab), homeText: whole(hb), awayShare: share(ab, hb)))
        }
        return bars
    }
}
