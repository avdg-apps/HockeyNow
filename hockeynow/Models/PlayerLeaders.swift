import Foundation

struct SkaterSeasonLine: Identifiable {
    let id: String
    let displayName: String
    var teamAbbreviation: String
    var teamLogo: String?
    let headshotURL: String?
    let position: String
    var gamesPlayed: Int = 0
    var goals: Int = 0
    var assists: Int = 0
    var points: Int { goals + assists }
}

struct GoalieSeasonLine: Identifiable {
    let id: String
    let displayName: String
    var teamAbbreviation: String
    var teamLogo: String?
    let headshotURL: String?
    var gamesPlayed: Int = 0
    var wins: Int = 0
    var losses: Int = 0
    var otLosses: Int = 0
    var shutouts: Int = 0
    var saves: Int = 0
    var shotsAgainst: Int = 0
    var goalsAgainst: Int = 0
    var savePercentage: Double { shotsAgainst > 0 ? Double(saves) / Double(shotsAgainst) : 0 }
    var goalsAgainstAverage: Double { gamesPlayed > 0 ? Double(goalsAgainst) / Double(gamesPlayed) : 0 }
}
