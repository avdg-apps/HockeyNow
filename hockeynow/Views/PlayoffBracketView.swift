import SwiftUI

struct PlayoffBracketView: View {
    @ObservedObject var fetcher: ESPNNHLFetcher
    @AppStorage("favorite_team_abbreviation") private var favouriteTeamAbbreviation = ""
    @State private var selectedSeasonStartYear: Int
    @State private var openedSeries: PlayoffSeries?

    private let cardWidth: CGFloat = 176
    private let cardHeight: CGFloat = 62
    private let slotHeight: CGFloat = 74

    init(fetcher: ESPNNHLFetcher) {
        self.fetcher = fetcher
        _selectedSeasonStartYear = State(initialValue: Self.currentSeasonStartYear)
    }

    private static var currentSeasonStartYear: Int {
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        return Calendar.current.component(.month, from: now) >= 9 ? year : year - 1
    }

    private var seasonName: String { "\(selectedSeasonStartYear)/\(String(selectedSeasonStartYear + 1).suffix(2))" }
    private var isFutureSeason: Bool { selectedSeasonStartYear > Self.currentSeasonStartYear }

    private var bracket: PlayoffBracket {
        guard !isFutureSeason else { return .empty }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let start = calendar.date(from: DateComponents(year: selectedSeasonStartYear, month: 9, day: 1)),
              let end = calendar.date(from: DateComponents(year: selectedSeasonStartYear + 1, month: 9, day: 1)) else { return .empty }
        let games = fetcher.seasonGames.filter {
            guard let date = $0.systemCalendarDate else { return false }
            return date >= start && date < end
        }
        return PlayoffBracket.build(from: games)
    }

    var body: some View {
        let bracket = self.bracket
        VStack(alignment: .leading, spacing: 10) {
            header(started: bracket.hasStarted)

            if fetcher.isLoadingSeason && !isFutureSeason && !bracket.hasStarted {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading \(seasonName)…").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    HStack(alignment: .top, spacing: 18) {
                        roundColumn(title: "ROUND 1", rounds: 1, east: bracket.eastern.roundOne, west: bracket.western.roundOne)
                        roundColumn(title: "ROUND 2", rounds: 2, east: bracket.eastern.roundTwo, west: bracket.western.roundTwo)
                        roundColumn(title: "CONFERENCE FINALS", rounds: 3, east: [bracket.eastern.final], west: [bracket.western.final])
                        finalColumn(bracket.cupFinal)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.03))
        .task(id: selectedSeasonStartYear) {
            guard !isFutureSeason else { return }
            await fetcher.loadSeason(startingIn: selectedSeasonStartYear)
        }
    }

    private func header(started: Bool) -> some View {
        HStack {
            Text("PLAYOFFS").font(.system(size: 11, weight: .black, design: .monospaced)).foregroundColor(.secondary)
            Spacer()
            Menu {
                ForEach((2016...(Self.currentSeasonStartYear + 1)).reversed(), id: \.self) { year in
                    Button { selectedSeasonStartYear = year } label: {
                        Text("\(year)/\(String(year + 1).suffix(2))")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(seasonName)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .overlay(alignment: .bottom) {
            if !started {
                Text(isFutureSeason || selectedSeasonStartYear == Self.currentSeasonStartYear ? "Matchups appear once the playoffs begin" : "No playoff games found")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                    .offset(y: 16)
            }
        }
        .padding(.bottom, started ? 0 : 14)
    }

    private func roundColumn(title: String, rounds: Int, east: [PlayoffSeries?], west: [PlayoffSeries?]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.amber)
            conferenceBlock(name: "EASTERN", slots: east, round: rounds)
            conferenceBlock(name: "WESTERN", slots: west, round: rounds)
        }
        .frame(width: cardWidth, alignment: .leading)
    }

    private func conferenceBlock(name: String, slots: [PlayoffSeries?], round: Int) -> some View {
        let height = slotHeight * CGFloat(1 << (round - 1))
        let expected = 4 >> (round - 1)
        let padded = (slots + Array(repeating: nil, count: max(expected - slots.count, 0))).prefix(expected)
        return VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(padded.enumerated()), id: \.offset) { _, series in
                    seriesCard(series).frame(width: cardWidth, height: height)
                }
            }
        }
    }

    private func finalColumn(_ series: PlayoffSeries?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STANLEY CUP FINAL").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.amber)
            VStack(spacing: 8) {
                Image(systemName: "trophy.fill").font(.system(size: 22)).foregroundColor(.amber)
                seriesCard(series).frame(width: cardWidth, height: cardHeight + 10)
                if let winner = series?.winnerAbbreviation, let series {
                    let name = series.top.abbreviation == winner ? series.top.name : series.bottom.name
                    Text("\(name) win the Cup")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.amber)
                        .multilineTextAlignment(.center)
                        .frame(width: cardWidth)
                }
            }
            .frame(height: slotHeight * 8 + 30, alignment: .center)
        }
        .frame(width: cardWidth, alignment: .leading)
    }

    @ViewBuilder
    private func seriesCard(_ series: PlayoffSeries?) -> some View {
        VStack(spacing: 0) {
            if let series {
                teamRow(series.top, series: series)
                Divider().opacity(0.4)
                teamRow(series.bottom, series: series)
                footer(for: series)
            } else {
                tbdRow
                Divider().opacity(0.4)
                tbdRow
                Text("TBD").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity).padding(.vertical, 2)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor(for: series), style: StrokeStyle(lineWidth: 1, dash: series == nil ? [3, 3] : []))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { if let series, !series.games.isEmpty { openedSeries = series } }
        .popover(isPresented: Binding(
            get: { openedSeries?.id == series?.id && series != nil },
            set: { if !$0 { openedSeries = nil } }
        ), arrowEdge: .trailing) {
            if let series { seriesDetail(series) }
        }
        .help(series == nil ? "" : "Click for every game in this series")
    }

    private func seriesDetail(_ series: PlayoffSeries) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(series.top.name) vs \(series.bottom.name)")
                .font(.system(size: 12, weight: .black, design: .monospaced))
            ForEach(Array(series.games.enumerated()), id: \.element.id) { index, game in
                HStack(spacing: 8) {
                    Text("G\(index + 1)").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(.amber).frame(width: 22, alignment: .leading)
                    Text(Self.gameDateFormatter.string(from: game.date))
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary).frame(width: 52, alignment: .leading)
                    if game.isFinal {
                        let awayWon = game.awayScore > game.homeScore
                        Text("\(game.awayAbbreviation) \(game.awayScore)").font(.system(size: 11, weight: awayWon ? .black : .regular, design: .monospaced))
                        Text("@").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                        Text("\(game.homeAbbreviation) \(game.homeScore)").font(.system(size: 11, weight: awayWon ? .regular : .black, design: .monospaced))
                        if game.wentToOvertime { Text("OT").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.orange) }
                    } else {
                        Text("\(game.awayAbbreviation) @ \(game.homeAbbreviation) · not played")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 240, alignment: .leading)
    }

    private static let gameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private func borderColor(for series: PlayoffSeries?) -> Color {
        guard let series else { return Color.primary.opacity(0.18) }
        return series.involves(favouriteTeamAbbreviation) ? Color.amber.opacity(0.8) : Color.primary.opacity(0.12)
    }

    private var tbdRow: some View {
        HStack(spacing: 6) {
            Circle().stroke(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 16, height: 16)
            Text("TBD").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }

    private func teamRow(_ side: PlayoffSeries.Side, series: PlayoffSeries) -> some View {
        let isWinner = series.winnerAbbreviation == side.abbreviation
        let isLoser = series.isComplete && !isWinner
        return HStack(spacing: 6) {
            TeamLogoView(logoURLString: side.logo, teamAbbreviation: side.abbreviation, size: 16)
            Text(side.abbreviation)
                .font(.system(size: 11, weight: isWinner ? .black : .semibold, design: .monospaced))
            if isWinner { Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundColor(.green) }
            Spacer()
            Text("\(side.wins)").font(.system(size: 13, weight: .black, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(isWinner
                    ? getGameTeamColor(abbreviation: side.abbreviation, isHome: side.abbreviation == series.top.abbreviation,
                                       opponent: side.abbreviation == series.top.abbreviation ? series.bottom.abbreviation : series.top.abbreviation).opacity(0.28)
                    : Color.clear)
        .opacity(isLoser ? 0.45 : 1)
    }

    private func footer(for series: PlayoffSeries) -> some View {
        let text: String
        if let winner = series.winnerAbbreviation {
            let winnerWins = series.top.abbreviation == winner ? series.top.wins : series.bottom.wins
            let loserWins = series.top.abbreviation == winner ? series.bottom.wins : series.top.wins
            text = "\(winner) won \(winnerWins)-\(loserWins) · \(series.gamesPlayed) GP"
        } else if series.top.wins == series.bottom.wins {
            text = "Tied \(series.top.wins)-\(series.bottom.wins) · \(series.gamesPlayed) GP"
        } else {
            let leader = series.top.wins > series.bottom.wins ? series.top : series.bottom
            let other = series.top.wins > series.bottom.wins ? series.bottom : series.top
            text = "\(leader.abbreviation) leads \(leader.wins)-\(other.wins) · \(series.gamesPlayed) GP"
        }
        return Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 2)
            .background(Color.primary.opacity(0.05))
    }
}
