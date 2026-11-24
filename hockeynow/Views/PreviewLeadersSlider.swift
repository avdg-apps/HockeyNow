import SwiftUI

struct PreviewLeadersSlider: View {
    let away: ESPNEvent.ESPNCompetitor
    let home: ESPNEvent.ESPNCompetitor
    @ObservedObject var fetcher: ESPNNHLFetcher

    private struct LeaderCard: Identifiable {
        let id: String
        let category: String
        let teamAbbreviation: String
        let teamLogo: String?
        let name: String
        let headshotURL: String?
        let value: String
        let unit: String
        let detail: String
        var numericValue: Double = 0
        var highlight: Color? = nil
    }

    private var cards: [LeaderCard] {
        let teams = [away, home]
        var result: [LeaderCard] = []

        for team in teams {
            let abbr = team.team.threeLetterAbbreviation
            if let player = fetcher.skaterLeaders
                .filter({ $0.teamAbbreviation == abbr && $0.goals > 0 })
                .max(by: { ($0.goals, $0.points) < ($1.goals, $1.points) }) {
                result.append(LeaderCard(id: "goals-\(abbr)", category: "TOP SCORER", teamAbbreviation: abbr, teamLogo: team.team.logo,
                                         name: player.displayName, headshotURL: player.headshotURL,
                                         value: "\(player.goals)", unit: player.goals == 1 ? "GOAL" : "GOALS", detail: "\(player.gamesPlayed) GP", numericValue: Double(player.goals)))
            }
        }
        for team in teams {
            let abbr = team.team.threeLetterAbbreviation
            if let player = fetcher.skaterLeaders
                .filter({ $0.teamAbbreviation == abbr && $0.assists > 0 })
                .max(by: { ($0.assists, $0.points) < ($1.assists, $1.points) }) {
                result.append(LeaderCard(id: "assists-\(abbr)", category: "ASSIST LEADER", teamAbbreviation: abbr, teamLogo: team.team.logo,
                                         name: player.displayName, headshotURL: player.headshotURL,
                                         value: "\(player.assists)", unit: player.assists == 1 ? "ASSIST" : "ASSISTS", detail: "\(player.points) PTS", numericValue: Double(player.assists)))
            }
        }
        for team in teams {
            let abbr = team.team.threeLetterAbbreviation
            if let goalie = fetcher.goalieLeaders
                .filter({ $0.teamAbbreviation == abbr && $0.wins > 0 })
                .max(by: { ($0.wins, $0.savePercentage) < ($1.wins, $1.savePercentage) }) {
                result.append(LeaderCard(id: "wins-\(abbr)", category: "WIN LEADER", teamAbbreviation: abbr, teamLogo: team.team.logo,
                                         name: goalie.displayName, headshotURL: goalie.headshotURL,
                                         value: "\(goalie.wins)", unit: goalie.wins == 1 ? "WIN" : "WINS", detail: savePercentText(goalie.savePercentage) + " SV%", numericValue: Double(goalie.wins)))
            }
        }
        let awayAbbr = away.team.threeLetterAbbreviation
        let homeAbbr = home.team.threeLetterAbbreviation
        for category in ["TOP SCORER", "ASSIST LEADER", "WIN LEADER"] {
            guard let awayIndex = result.firstIndex(where: { $0.category == category && $0.teamAbbreviation == awayAbbr }),
                  let homeIndex = result.firstIndex(where: { $0.category == category && $0.teamAbbreviation == homeAbbr }),
                  result[awayIndex].numericValue != result[homeIndex].numericValue else { continue }
            if result[awayIndex].numericValue > result[homeIndex].numericValue {
                result[awayIndex].highlight = getGameTeamColor(abbreviation: awayAbbr, isHome: false, opponent: homeAbbr)
            } else {
                result[homeIndex].highlight = getGameTeamColor(abbreviation: homeAbbr, isHome: true, opponent: awayAbbr)
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOP PERFORMERS")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.secondary)

            if !fetcher.hasLoadedPlayerLeaders || fetcher.isLoadingPlayerStats || cards.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cards) { card in
                            cardView(card)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task { fetcher.loadPlayerLeadersIfNeeded() }
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack(spacing: 8) {
            if fetcher.isLoadingPlayerStats || !fetcher.hasLoadedPlayerLeaders {
                ProgressView().controlSize(.small)
                if let progress = fetcher.playerStatsLoadProgress {
                    Text("Loading season leaders \(progress.0)/\(progress.1)")
                } else {
                    Text("Loading season leaders…")
                }
            } else {
                Text("No season stats yet")
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, minHeight: 90)
    }

    private func cardView(_ card: LeaderCard) -> some View {
        VStack(spacing: 5) {
            Text(card.category)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.amber)

            ZStack(alignment: .bottomTrailing) {
                PlayerHeadshotView(headshotURLString: card.headshotURL, initials: initials(for: card.name), size: 46)
                TeamLogoView(logoURLString: card.teamLogo, teamAbbreviation: card.teamAbbreviation, size: 16)
                    .offset(x: 5, y: 3)
            }

            Text(card.name)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(card.value)
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                Text(card.unit)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
            }
            .foregroundColor(.amber)

            Text(card.detail)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 108)
        .background(card.highlight.map { $0.opacity(0.24) } ?? Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(card.highlight?.opacity(0.55) ?? Color.clear, lineWidth: 1)
        )
    }

    private func initials(for name: String) -> String {
        String(name.split(separator: " ").compactMap { $0.first }.prefix(2)).uppercased()
    }

    private func savePercentText(_ value: Double) -> String {
        let text = String(format: "%.3f", value)
        return text.hasPrefix("0") ? String(text.dropFirst()) : text
    }
}
