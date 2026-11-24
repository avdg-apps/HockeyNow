import Foundation

struct SeriesGame: Identifiable {
    let id: String
    let date: Date
    let awayAbbreviation: String
    let homeAbbreviation: String
    let awayScore: Int
    let homeScore: Int
    let isFinal: Bool
    let wentToOvertime: Bool
}

struct PlayoffSeries: Identifiable {
    struct Side {
        let abbreviation: String
        let name: String
        let logo: String?
        var wins = 0
    }

    let id: String
    var top: Side
    var bottom: Side
    var gamesPlayed = 0
    var games: [SeriesGame] = []
    var round = 1
    var startDate = Date.distantFuture

    var isComplete: Bool { top.wins >= 4 || bottom.wins >= 4 }
    var winnerAbbreviation: String? {
        top.wins >= 4 ? top.abbreviation : (bottom.wins >= 4 ? bottom.abbreviation : nil)
    }
    func involves(_ abbreviation: String) -> Bool { top.abbreviation == abbreviation || bottom.abbreviation == abbreviation }
}

struct PlayoffBracket {
    struct ConferenceSide {
        var roundOne: [PlayoffSeries?] = Array(repeating: nil, count: 4)
        var roundTwo: [PlayoffSeries?] = Array(repeating: nil, count: 2)
        var final: PlayoffSeries? = nil
    }
    var eastern = ConferenceSide()
    var western = ConferenceSide()
    var cupFinal: PlayoffSeries? = nil
    var hasStarted = false

    static let empty = PlayoffBracket()

    static func build(from games: [ESPNEvent]) -> PlayoffBracket {
        let validTeams = Set(nhlDivisionOrder.flatMap(\.teams))
        var seriesByKey: [String: PlayoffSeries] = [:]

        let playoffGames = games
            .filter { $0.isPlayoffGame }
            .compactMap { game -> (ESPNEvent, Date)? in
                guard let date = game.systemCalendarDate else { return nil }
                return (game, date)
            }
            .sorted { $0.1 < $1.1 }

        for (game, date) in playoffGames {
            guard let away = game.awayTeam, let home = game.homeTeam else { continue }
            let awayAbbr = away.team.threeLetterAbbreviation
            let homeAbbr = home.team.threeLetterAbbreviation
            guard validTeams.contains(awayAbbr), validTeams.contains(homeAbbr) else { continue }
            let key = [awayAbbr, homeAbbr].sorted().joined(separator: "-")

            var series = seriesByKey[key] ?? PlayoffSeries(
                id: key,
                top: .init(abbreviation: homeAbbr, name: home.team.safeDisplayName, logo: home.team.logo),
                bottom: .init(abbreviation: awayAbbr, name: away.team.safeDisplayName, logo: away.team.logo),
                startDate: date)

            let listedAwayScore = Int(away.score) ?? 0
            let listedHomeScore = Int(home.score) ?? 0
            series.games.append(SeriesGame(id: game.id, date: date, awayAbbreviation: awayAbbr, homeAbbreviation: homeAbbr,
                                           awayScore: listedAwayScore, homeScore: listedHomeScore,
                                           isFinal: game.status.type.state == "post", wentToOvertime: (game.status.period ?? 3) > 3))
            if game.status.type.state == "post" {
                let awayScore = Int(away.score) ?? 0
                let homeScore = Int(home.score) ?? 0
                if awayScore != homeScore {
                    let homeWon = homeScore > awayScore
                    let winner = homeWon ? homeAbbr : awayAbbr
                    if series.top.abbreviation == winner { series.top.wins += 1 } else { series.bottom.wins += 1 }
                    series.gamesPlayed += 1
                }
            }
            seriesByKey[key] = series
        }

        var bracket = PlayoffBracket()
        guard !seriesByKey.isEmpty else { return bracket }
        bracket.hasStarted = true

        var seriesPerTeam: [String: [PlayoffSeries]] = [:]
        for series in seriesByKey.values {
            seriesPerTeam[series.top.abbreviation, default: []].append(series)
            seriesPerTeam[series.bottom.abbreviation, default: []].append(series)
        }
        for key in seriesPerTeam.keys { seriesPerTeam[key]?.sort { $0.startDate < $1.startDate } }
        for (key, var series) in seriesByKey {
            let topIndex = seriesPerTeam[series.top.abbreviation]?.firstIndex { $0.id == key } ?? 0
            let bottomIndex = seriesPerTeam[series.bottom.abbreviation]?.firstIndex { $0.id == key } ?? 0
            series.round = min(max(topIndex, bottomIndex) + 1, 4)
            seriesByKey[key] = series
        }

        func conference(of series: PlayoffSeries) -> String? {
            nhlDivisionOrder.first { $0.teams.contains(series.top.abbreviation) }?.conference
        }

        let all = seriesByKey.values.sorted { $0.startDate < $1.startDate }
        bracket.cupFinal = all.first { $0.round == 4 }

        for name in ["Eastern", "Western"] {
            let mine = all.filter { $0.round < 4 && conference(of: $0) == name }
            var side = ConferenceSide()
            var used = Set<String>()

            side.final = mine.first { $0.round == 3 }
            if let final = side.final { used.insert(final.id) }

            func feeders(of parent: PlayoffSeries?, round: Int) -> [PlayoffSeries?] {
                let pool = mine.filter { $0.round == round && !used.contains($0.id) }
                var picked: [PlayoffSeries?] = []
                if let parent {
                    for abbreviation in [parent.top.abbreviation, parent.bottom.abbreviation] {
                        if let match = pool.first(where: { $0.involves(abbreviation) && !used.contains($0.id) }) {
                            used.insert(match.id)
                            picked.append(match)
                        } else {
                            picked.append(nil)
                        }
                    }
                } else {
                    picked = [nil, nil]
                }
                return picked
            }

            var roundTwo: [PlayoffSeries?] = feeders(of: side.final, round: 2)
            var roundOne: [PlayoffSeries?] = []
            for series in roundTwo { roundOne.append(contentsOf: feeders(of: series, round: 1)) }

            func fill(_ slots: inout [PlayoffSeries?], round: Int) {
                for series in mine where series.round == round && !used.contains(series.id) {
                    if let free = slots.firstIndex(where: { $0 == nil }) {
                        slots[free] = series
                        used.insert(series.id)
                    }
                }
            }
            fill(&roundTwo, round: 2)
            if roundOne.count == 4 {
                for (index, series) in roundTwo.enumerated() {
                    guard let series, roundOne[index * 2] == nil, roundOne[index * 2 + 1] == nil else { continue }
                    let extra = feeders(of: series, round: 1)
                    roundOne[index * 2] = extra[0]
                    roundOne[index * 2 + 1] = extra[1]
                }
            }
            fill(&roundOne, round: 1)

            side.roundTwo = roundTwo
            side.roundOne = roundOne
            if name == "Eastern" { bracket.eastern = side } else { bracket.western = side }
        }
        return bracket
    }
}
