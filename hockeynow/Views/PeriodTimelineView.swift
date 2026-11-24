import SwiftUI

struct PeriodTimelineView: View {
    let periodNumber: Int
    let currentClockString: String
    let currentClockValue: Double?
    let plays: [ESPNPlay]
    let awayAbbr: String
    let homeAbbr: String
    let awayID: String
    let homeID: String
    let abstractGameState: String
    let currentPeriodLive: Int
    var compactMode: Bool = false
    let isPlayoff: Bool

    private var timelineProgress: CGFloat {
        guard abstractGameState != "Preview" else { return 0.0 }
        if periodNumber < currentPeriodLive || abstractGameState == "Final" {
            return 1.0
        } else if periodNumber == currentPeriodLive && abstractGameState == "Live" {
            let totalSeconds: Double = 1200.0
            let remaining = currentClockValue ?? 0.0
            let elapsed = max(0.0, totalSeconds - remaining)
            return CGFloat(elapsed / totalSeconds)
        }
        return 0.0
    }

    var body: some View {
        let isShootoutRow = !isPlayoff && periodNumber == 5

        return HStack(spacing: 10) {
            Text({
                if periodNumber <= 3 { return "P\(periodNumber)" }
                if periodNumber == 4 { return "OT" }
                if isPlayoff { return "\(periodNumber - 3)OT" }
                else { return periodNumber == 5 ? "SO" : "OT" }
            }())
            .font(.system(size: compactMode ? 10 : 11, weight: .black, design: .monospaced))
            .foregroundColor(.primary.opacity(0.85))
            .frame(width: 24, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                        .frame(height: compactMode ? 4 : 6)

                    if !isShootoutRow {
                        Capsule()
                            .fill((abstractGameState == "Live" && periodNumber == currentPeriodLive) ? Color.amber : Color.blue)
                            .frame(width: geo.size.width * timelineProgress, height: compactMode ? 4 : 6)
                    }

                    let periodPlays = plays.filter { $0.period.number == periodNumber }

                    ForEach(Array(periodPlays.enumerated()), id: \.element.id) { index, play in
                        let goalPosition: CGFloat = {
                            if isShootoutRow {
                                let totalGoals = CGFloat(periodPlays.count)
                                if totalGoals > 1 {
                                    let cushion = geo.size.width * 0.1
                                    let availableWidth = geo.size.width * 0.8
                                    return cushion + (availableWidth * (CGFloat(index) / (totalGoals - 1)))
                                } else { return geo.size.width / 2 }
                            } else {
                                return parseGoalCoordinates(displayValue: play.clock.displayValue, width: geo.size.width)
                            }
                        }()

                        Circle()
                            .fill(getScoringTeamColor(for: play))
                            .frame(width: compactMode ? 8 : 10, height: compactMode ? 8 : 10)
                            .overlay(Circle().stroke(Color.black, lineWidth: 1))
                            .offset(x: goalPosition - (compactMode ? 4 : 5))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: compactMode ? 8 : 12)

            if isShootoutRow {
                Text("—")
                    .font(.system(size: compactMode ? 9 : 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 42, alignment: .trailing)
            } else if abstractGameState == "Live" && periodNumber == currentPeriodLive {
                Text(currentClockString)
                    .font(.system(size: compactMode ? 9 : 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                    .frame(width: 42, alignment: .trailing)
            } else {
                Text((periodNumber < currentPeriodLive || abstractGameState == "Final") ? "0:00" : "20:00")
                    .font(.system(size: compactMode ? 9 : 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }

    private func parseGoalCoordinates(displayValue: String, width: CGFloat) -> CGFloat {
        let totalSeconds = 1200.0
        let components = displayValue.components(separatedBy: ":")
        if components.count == 2, let mins = Double(components[0]), let secs = Double(components[1]) {
            let elapsed = (mins * 60.0) + secs
            let percentage = elapsed / totalSeconds
            return width * CGFloat(percentage)
        }
        return 0.0
    }

    private func getScoringTeamColor(for play: ESPNPlay) -> Color {
        let awayColor = getGameTeamColor(abbreviation: awayAbbr, isHome: false, opponent: homeAbbr)
        let homeColor = getGameTeamColor(abbreviation: homeAbbr, isHome: true, opponent: awayAbbr)
        if let teamID = play.team?.id {
            if teamID == awayID { return awayColor }
            if teamID == homeID { return homeColor }
        }
        let txt = play.text.lowercased()
        if txt.contains(awayID.lowercased()) || txt.contains(awayAbbr.lowercased()) { return awayColor }
        return homeColor
    }
}
