import SwiftUI

enum GameDetailTab: String, CaseIterable, Identifiable {
    case goals = "Goals", playByPlay = "Play-by-play", shots = "Shots", lines = "Lines", postGame = "Post-game"
    var id: String { rawValue }
}

struct PlayByPlayView: View {
    let game: ESPNEvent
    @ObservedObject var fetcher: ESPNNHLFetcher

    var body: some View {
        let plays = fetcher.playByPlaySummaries[game.id] ?? []
        let awayID = game.awayTeam?.id ?? "", homeID = game.homeTeam?.id ?? ""
        let awayAbbr = game.awayTeam?.team.threeLetterAbbreviation ?? "", homeAbbr = game.homeTeam?.team.threeLetterAbbreviation ?? ""

        if plays.isEmpty {
            Text(fetcher.loadingSummaries[game.id] == true ? "Loading…" : "ESPN has no play-by-play for this game.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 20)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(plays.reversed().prefix(250).enumerated()), id: \.offset) { _, play in
                        let isGoal = play.scoringPlay == true
                        HStack(alignment: .top, spacing: 6) {
                            Text("P\(play.period.number) \(play.clock.displayValue)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                                .frame(width: 62, alignment: .leading)
                            if let teamID = play.team?.id {
                                let abbreviation = teamID == awayID ? awayAbbr : (teamID == homeID ? homeAbbr : "")
                                if !abbreviation.isEmpty {
                                    Text(abbreviation)
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(getGameTeamColor(abbreviation: abbreviation, isHome: teamID == homeID,
                                                                     opponent: teamID == homeID ? awayAbbr : homeAbbr))
                                        .foregroundColor(.white)
                                        .cornerRadius(3)
                                }
                            }
                            Text(play.text)
                                .font(.system(size: 10, weight: isGoal ? .bold : .regular, design: .monospaced))
                                .foregroundColor(isGoal ? .amber : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
            .frame(maxHeight: 160)
        }
    }
}

struct GameLinesView: View {
    let game: ESPNEvent
    @ObservedObject var fetcher: ESPNNHLFetcher

    var body: some View {
        if let away = game.awayTeam, let home = game.homeTeam {
            let awayLineup = fetcher.gameLineup(for: game, teamAbbreviation: away.team.threeLetterAbbreviation)
            let homeLineup = fetcher.gameLineup(for: game, teamAbbreviation: home.team.threeLetterAbbreviation)
            let isActual = (awayLineup?.isActual ?? false) || (homeLineup?.isActual ?? false)

            VStack(alignment: .leading, spacing: 8) {
                Text(isActual ? "LINES · BY ICE TIME" : "LIKELY LINEUP · BASED ON LAST GAME")
                    .font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(.secondary)
                if awayLineup == nil && homeLineup == nil {
                    Text("No lineup available yet")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        column(abbreviation: away.team.threeLetterAbbreviation, lineup: awayLineup?.lineup)
                        column(abbreviation: home.team.threeLetterAbbreviation, lineup: homeLineup?.lineup)
                    }
                }
            }
        }
    }

    private func lastName(_ full: String) -> String { full.split(separator: " ").last.map(String.init) ?? full }

    private func column(abbreviation: String, lineup: TeamLineup?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(abbreviation).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(.amber)
            if let lineup {
                ForEach(Array(lineup.forwardLines.enumerated()), id: \.offset) { index, line in
                    row(label: "L\(index + 1)", names: line.map { lastName($0.name) })
                }
                ForEach(Array(lineup.defencePairs.enumerated()), id: \.offset) { index, pair in
                    row(label: "D\(index + 1)", names: pair.map { lastName($0.name) })
                }
                if !lineup.goalies.isEmpty {
                    row(label: "G", names: lineup.goalies.prefix(2).map { lastName($0.name) })
                }
            } else {
                Text("Not known yet").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func row(label: String, names: [String]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.secondary).frame(width: 18, alignment: .leading)
            Text(names.joined(separator: " · "))
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
