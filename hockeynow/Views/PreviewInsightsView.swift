import SwiftUI

// MARK: - Pre-game insights
// Under each preview: each team's last five results as dots, its home and away record, the recent head-to-head,
// and the goalies most likely to start. Everything is worked out from games the app has already loaded.
struct PreviewInsightsView: View {
    let game: ESPNEvent
    @ObservedObject var fetcher: ESPNNHLFetcher
    @AppStorage("favorite_team_abbreviation") private var favouriteTeamAbbreviation = ""

    private var gameDate: Date { game.systemCalendarDate ?? Date() }

    var body: some View {
        if let away = game.awayTeam, let home = game.homeTeam {
            let awayAbbr = away.team.threeLetterAbbreviation
            let homeAbbr = home.team.threeLetterAbbreviation
            let preseason = game.isPreseasonGame
            let awayForm = fetcher.teamForm(for: awayAbbr, before: gameDate, preseason: preseason)
            let homeForm = fetcher.teamForm(for: homeAbbr, before: gameDate, preseason: preseason)
            // Written from the favourite team's side when it is playing, otherwise from the home team's.
            let perspective = awayAbbr == favouriteTeamAbbreviation ? awayAbbr : homeAbbr
            let opponent = perspective == awayAbbr ? homeAbbr : awayAbbr

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("TEAM FORM")
                HStack(alignment: .top, spacing: 10) {
                    formColumn(abbreviation: awayAbbr, logo: away.team.logo, form: awayForm)
                    formColumn(abbreviation: homeAbbr, logo: home.team.logo, form: homeForm)
                }

                if awayForm.hasGames || homeForm.hasGames || !fetcher.seasonGames.isEmpty {
                    Text(fetcher.headToHeadLine(perspective: perspective, opponent: opponent, before: gameDate, preseason: preseason))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                sectionTitle("LIKELY STARTERS")
                HStack(alignment: .top, spacing: 10) {
                    goalieColumn(abbreviation: awayAbbr, preseason: preseason)
                    goalieColumn(abbreviation: homeAbbr, preseason: preseason)
                }

                GameLinesView(game: game, fetcher: fetcher)
            }
            // Fetches (or reads from disk) the boxscores needed to see who started each team's recent games.
            .task(id: game.id) {
                let ids = fetcher.starterGameIDs(for: awayAbbr, before: gameDate, preseason: preseason)
                    + fetcher.starterGameIDs(for: homeAbbr, before: gameDate, preseason: preseason)
                await fetcher.ensureBoxscores(forGameIDs: ids)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(.secondary)
    }

    private func formColumn(abbreviation: String, logo: String?, form: TeamFormSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TeamLogoView(logoURLString: logo, teamAbbreviation: abbreviation, size: 16)
                Text(abbreviation).font(.system(size: 11, weight: .black, design: .monospaced))
            }
            if form.lastFive.isEmpty {
                Text("No games yet").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
            } else {
                HStack(spacing: 5) {
                    ForEach(form.lastFive) { item in
                        Circle()
                            .fill(color(for: item.result))
                            .frame(width: 11, height: 11)
                            .overlay(Text(item.result.shortLabel.prefix(1)).font(.system(size: 6, weight: .black)).foregroundColor(.white))
                            .help("\(item.result.shortLabel) \(item.scoreText) \(item.wasHome ? "vs" : "@") \(item.opponent)")
                    }
                }
            }
            Text("HOME \(form.home.text)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
            Text("AWAY \(form.away.text)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func goalieColumn(abbreviation: String, preseason: Bool) -> some View {
        let starter = fetcher.likelyStarter(for: abbreviation, before: gameDate, preseason: preseason)
        VStack(alignment: .leading, spacing: 3) {
            Text(abbreviation).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.amber)
            if let starter {
                Text(starter.name).font(.system(size: 11, weight: .bold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.75)
                if let sv = starter.savePercentage, let gaa = starter.goalsAgainstAverage {
                    Text("\(savePercentText(sv)) SV% · \(String(format: "%.2f", gaa)) GAA")
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                }
                Text("Started \(starter.startsInLastFive) of last \(starter.gamesConsidered)")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
            } else {
                Text("Not known yet").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func color(for result: GameResult) -> Color {
        switch result {
        case .win: return .green
        case .loss: return .red
        case .otLoss: return .orange
        }
    }

    private func savePercentText(_ value: Double) -> String {
        let text = String(format: "%.3f", value)
        return text.hasPrefix("0") ? String(text.dropFirst()) : text
    }
}
