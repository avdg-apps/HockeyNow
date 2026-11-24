//
//  ComputedStandingEntry.swift
//  hockeynow
//
//  Created by Declan Goh on 13/10/2026.
//


import Foundation

// MARK: - Standings Model (computed from actual game results, so it can reflect any chosen date)
struct ComputedStandingEntry: Identifiable {
    var id: String { teamAbbreviation }
    let teamAbbreviation: String
    let teamDisplayName: String
    let teamLogo: String?
    var wins: Int = 0                // W: every win, however it came
    var regulationWins: Int = 0      // RW: won inside 60 minutes
    var overtimeWins: Int = 0        // won in overtime but not a shootout (ROW = RW + this)
    var losses: Int = 0
    var otLosses: Int = 0
    var gamesPlayed: Int { wins + losses + otLosses }
    var regulationOvertimeWins: Int { regulationWins + overtimeWins }     // ROW
    // This team's games against each opponent, used for the head-to-head tiebreaker.
    var meetings: [String: [HeadToHeadGame]] = [:]
    var points: Int { wins * 2 + otLosses }
    var goalsFor: Int = 0
    var goalsAgainst: Int = 0
    var goalDifferential: Int { goalsFor - goalsAgainst }
    // "+12", "-3", "0"
    var goalDifferentialText: String { goalDifferential > 0 ? "+\(goalDifferential)" : "\(goalDifferential)" }
    // Filled in from the games already loaded: the record over the last 10 games, and the current streak.
    var last10Wins: Int = 0
    var last10Losses: Int = 0
    var last10OTLosses: Int = 0
    var streakResult: GameResult? = nil
    var streakLength: Int = 0

    var last10Text: String { "\(last10Wins)-\(last10Losses)-\(last10OTLosses)" }
    // "W3", "L2", "OT1"
    var streakText: String {
        guard let streakResult, streakLength > 0 else { return "—" }
        return "\(streakResult.shortLabel)\(streakLength)"
    }
}

// One game between two clubs, from the point of view of the team whose entry holds it.
struct HeadToHeadGame {
    let date: Date
    let hostAbbreviation: String
    let pointsFor: Int
    let pointsAgainst: Int
}

// MARK: - A single game result from one team's point of view
enum GameResult: String {
    case win, loss, otLoss
    var shortLabel: String {
        switch self {
        case .win: return "W"
        case .loss: return "L"
        case .otLoss: return "OT"
        }
    }
}

// W / L / OTL record split, used for home and away records.
struct SplitRecord {
    var wins = 0
    var losses = 0
    var otLosses = 0
    var text: String { "\(wins)-\(losses)-\(otLosses)" }
    mutating func add(_ result: GameResult) {
        switch result {
        case .win: wins += 1
        case .loss: losses += 1
        case .otLoss: otLosses += 1
        }
    }
}

struct StandingGroup: Identifiable {
    var id: String { title }
    let title: String
    let entries: [ComputedStandingEntry]
    // How many entries at the top of this group hold wild card spots (Wild Card view only).
    var wildCardSlots: Int = 0
}

enum StandingsViewMode: String, CaseIterable, Identifiable {
    case division = "Division"
    case wildCard = "Wild Card"
    case conference = "Conference"
    case league = "League"
    var id: String { rawValue }
}

// MARK: - NHL tiebreakers
// Clubs level on points are separated by, in order:
//   1. fewer games played   2. regulation wins (RW)   3. regulation + overtime wins (ROW)   4. total wins (W)
//   5. points in games among the tied clubs (odd game removed)   6. goal differential   7. goals for
// Steps 1-4 are plain numbers on each club; step 5 only matters for clubs still level after them, so ranking is done on
// groups rather than with a pairwise comparator.
func rankStandings(_ entries: [ComputedStandingEntry]) -> [ComputedStandingEntry] {
    let byPoints = entries.sorted { $0.points > $1.points }
    var result: [ComputedStandingEntry] = []
    var index = 0
    while index < byPoints.count {
        var end = index + 1
        while end < byPoints.count, byPoints[end].points == byPoints[index].points { end += 1 }
        result.append(contentsOf: breakPointsTie(Array(byPoints[index..<end])))
        index = end
    }
    return result
}

fileprivate func tiebreakKey(_ e: ComputedStandingEntry) -> [Int] {
    [-e.gamesPlayed, e.regulationWins, e.regulationOvertimeWins, e.wins]
}

private func breakPointsTie(_ group: [ComputedStandingEntry]) -> [ComputedStandingEntry] {
    guard group.count > 1 else { return group }
    // Steps 1-4.
    let ordered = group.sorted { lhs, rhs in
        let a = tiebreakKey(lhs), b = tiebreakKey(rhs)
        if a != b { return a.lexicographicallyPrecedes(b) == false }
        return lhs.teamAbbreviation < rhs.teamAbbreviation
    }
    var result: [ComputedStandingEntry] = []
    var index = 0
    while index < ordered.count {
        var end = index + 1
        while end < ordered.count, tiebreakKey(ordered[end]) == tiebreakKey(ordered[index]) { end += 1 }
        let level = Array(ordered[index..<end])
        if level.count == 1 { result.append(level[0]) }
        else {
            // Steps 5-7 for clubs still level.
            let share = headToHeadShare(level)
            result.append(contentsOf: level.sorted { lhs, rhs in
                let l = share[lhs.teamAbbreviation] ?? 0, r = share[rhs.teamAbbreviation] ?? 0
                if abs(l - r) > 0.000_001 { return l > r }
                if lhs.goalDifferential != rhs.goalDifferential { return lhs.goalDifferential > rhs.goalDifferential }
                if lhs.goalsFor != rhs.goalsFor { return lhs.goalsFor > rhs.goalsFor }
                return lhs.teamAbbreviation < rhs.teamAbbreviation
            })
        }
        index = end
    }
    return result
}

// Share of the available points each club earned in games among the tied clubs. When two clubs have met an uneven number
// of times, the first game in the city with the extra game is left out.
private func headToHeadShare(_ clubs: [ComputedStandingEntry]) -> [String: Double] {
    let names = Set(clubs.map(\.teamAbbreviation))
    var earned: [String: Int] = [:], available: [String: Int] = [:]
    for club in clubs {
        for rival in clubs where rival.teamAbbreviation > club.teamAbbreviation {
            var games = (club.meetings[rival.teamAbbreviation] ?? []).sorted { $0.date < $1.date }
            guard names.contains(rival.teamAbbreviation), !games.isEmpty else { continue }
            if games.count % 2 == 1 {
                let atClub = games.filter { $0.hostAbbreviation == club.teamAbbreviation }.count
                let atRival = games.count - atClub
                let extraCity = atClub > atRival ? club.teamAbbreviation : rival.teamAbbreviation
                if let odd = games.firstIndex(where: { $0.hostAbbreviation == extraCity }) { games.remove(at: odd) }
            }
            for game in games {
                earned[club.teamAbbreviation, default: 0] += game.pointsFor
                earned[rival.teamAbbreviation, default: 0] += game.pointsAgainst
                available[club.teamAbbreviation, default: 0] += game.pointsFor + game.pointsAgainst
                available[rival.teamAbbreviation, default: 0] += game.pointsFor + game.pointsAgainst
            }
        }
    }
    var share: [String: Double] = [:]
    for club in clubs {
        let total = available[club.teamAbbreviation] ?? 0
        share[club.teamAbbreviation] = total > 0 ? Double(earned[club.teamAbbreviation] ?? 0) / Double(total) : 0
    }
    return share
}

// Rebuilds the division standings into the layout the user picked.
func standingGroups(for mode: StandingsViewMode, from divisionGroups: [StandingGroup]) -> [StandingGroup] {
    let allEntries = divisionGroups.flatMap(\.entries)

    switch mode {
    case .division:
        return divisionGroups

    case .league:
        return allEntries.isEmpty ? [] : [StandingGroup(title: "NHL", entries: rankStandings(allEntries))]

    case .conference:
        return ["Eastern", "Western"].compactMap { conference in
            let teams = Set(nhlDivisionOrder.filter { $0.conference == conference }.flatMap(\.teams))
            let entries = rankStandings(allEntries.filter { teams.contains($0.teamAbbreviation) })
            return entries.isEmpty ? nil : StandingGroup(title: "\(conference) Conference", entries: entries)
        }

    case .wildCard:
        // Each conference: the top 3 in every division, then everyone else ranked together for the two wild card spots.
        var result: [StandingGroup] = []
        for conference in ["Eastern", "Western"] {
            var wildCardPool: [ComputedStandingEntry] = []
            for division in nhlDivisionOrder where division.conference == conference {
                let ranked = divisionGroups.first { $0.title == "\(conference) - \(division.division)" }?.entries ?? []
                if !ranked.isEmpty {
                    result.append(StandingGroup(title: "\(conference) - \(division.division) (Top 3)", entries: Array(ranked.prefix(3))))
                }
                wildCardPool.append(contentsOf: ranked.dropFirst(3))
            }
            if !wildCardPool.isEmpty {
                result.append(StandingGroup(title: "\(conference) - Wild Card", entries: rankStandings(wildCardPool), wildCardSlots: 2))
            }
        }
        return result
    }
}

let nhlDivisionOrder: [(conference: String, division: String, teams: [String])] = [
    ("Eastern", "Atlantic", ["BOS", "BUF", "DET", "FLA", "MTL", "OTT", "TBL", "TOR"]),
    ("Eastern", "Metropolitan", ["CAR", "CBJ", "NJD", "NYI", "NYR", "PHI", "PIT", "WSH"]),
    ("Western", "Central", ["CHI", "COL", "DAL", "MIN", "NSH", "STL", "UTA", "WPG"]),
    ("Western", "Pacific", ["ANA", "CGY", "EDM", "LAK", "SEA", "SJS", "VAN", "VGK"])
]

// "1", "2", "T3": only clubs level on every tiebreaker share a rank, which is now very rare.
func standingRankLabel(at index: Int, in entries: [ComputedStandingEntry]) -> String {
    guard entries.indices.contains(index) else { return "" }
    let entry = entries[index]
    func level(_ other: ComputedStandingEntry) -> Bool {
        other.points == entry.points && tiebreakKey(other) == tiebreakKey(entry)
            && other.goalDifferential == entry.goalDifferential && other.goalsFor == entry.goalsFor
            && other.meetings[entry.teamAbbreviation]?.reduce(0, { $0 + $1.pointsFor }) == entry.meetings[other.teamAbbreviation]?.reduce(0, { $0 + $1.pointsAgainst })
    }
    let tiedCount = entries.filter(level).count
    guard tiedCount > 1, let first = entries.firstIndex(where: level) else { return "\(index + 1)" }
    return "T\(first + 1)"
}
