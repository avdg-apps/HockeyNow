import Foundation

// MARK: - ESPN Scoreboard API Decoders
struct ESPNResponse: Decodable { let events: [ESPNEvent]? }

struct ESPNEvent: Decodable, Identifiable, Equatable {
    let id: String
    let date: String
    let name: String
    var status: ESPNStatus
    var competitions: [ESPNCompetition]
    let links: [ESPNLink]?
    let season: ESPNSeason?
    
    static func == (lhs: ESPNEvent, rhs: ESPNEvent) -> Bool {
        return lhs.id == rhs.id && lhs.status.displayClock == rhs.status.displayClock && lhs.awayTeam?.score == rhs.awayTeam?.score && lhs.homeTeam?.score == rhs.homeTeam?.score && lhs.awayTeam?.shotsOnGoal == rhs.awayTeam?.shotsOnGoal && lhs.homeTeam?.shotsOnGoal == rhs.homeTeam?.shotsOnGoal
    }
    
    struct ESPNStatus: Decodable {
        let clock: Double?
        let displayClock: String?
        let period: Int?
        let type: StatusType
        struct StatusType: Decodable {
            let name: String
            let detail: String
            let state: String
        }
    }
    struct ESPNCompetition: Decodable {
        var competitors: [ESPNCompetitor]
        let situation: ESPNSituation?
        let venue: ESPNVenue?
    }
    struct ESPNVenue: Decodable {
        let fullName: String?
        let address: ESPNVenueAddress?
        struct ESPNVenueAddress: Decodable { let city: String?; let state: String? }
    }
    struct ESPNSituation: Decodable {
        let teamOnPowerPlay: ESPNSituationTeam?
        let powerPlayTime: Int?
        struct ESPNSituationTeam: Decodable {
            let id: String?
        }
    }
    struct ESPNLink: Decodable { let href: String }
    struct ESPNSeason: Decodable { let type: Int? }
    
    struct ESPNCompetitor: Decodable, Identifiable {
        var id: String { team.id }
        let homeAway: String
        let score: String
        let team: ESPNTeam
        let linescores: [ESPNLinescore]?
        var statistics: [ESPNStatistic]?
        
        struct ESPNTeam: Decodable {
            let id: String
            let abbreviation: String
            let displayName: String?
            let logo: String?
            
            var threeLetterAbbreviation: String {
                let upper = abbreviation.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                switch upper {
                case "SJ": return "SJS"
                case "NJ": return "NJD"
                case "TB": return "TBL"
                case "LA": return "LAK"
                default: return upper
                }
            }
            
            var safeDisplayName: String {
                if let name = displayName, !name.isEmpty { return name }
                switch threeLetterAbbreviation {
                case "ANA": return "Anaheim Ducks"
                case "ARI": return "Arizona Coyotes"
                case "BOS": return "Boston Bruins"
                case "BUF": return "Buffalo Sabres"
                case "CAR": return "Carolina Hurricanes"
                case "CBJ": return "Columbus Blue Jackets"
                case "CGY": return "Calgary Flames"
                case "CHI": return "Chicago Blackhawks"
                case "COL": return "Colorado Avalanche"
                case "DAL": return "Dallas Stars"
                case "DET": return "Detroit Red Wings"
                case "EDM": return "Edmonton Oilers"
                case "FLA": return "Florida Panthers"
                case "LAK": return "Los Angeles Kings"
                case "MIN": return "Minnesota Wild"
                case "MTL": return "Montreal Canadiens"
                case "NJD": return "New Jersey Devils"
                case "NSH": return "Nashville Predators"
                case "NYI": return "New York Islanders"
                case "NYR": return "New York Rangers"
                case "OTT": return "Ottawa Senators"
                case "PHI": return "Philadelphia Flyers"
                case "PIT": return "Pittsburgh Penguins"
                case "SEA": return "Seattle Kraken"
                case "SJS": return "San Jose Sharks"
                case "STL": return "St. Louis Blues"
                case "TBL": return "Tampa Bay Lightning"
                case "TOR": return "Toronto Maple Leafs"
                case "UTA": return "Utah Hockey Club"
                case "VAN": return "Vancouver Canucks"
                case "VGK": return "Vegas Golden Knights"
                case "WPG": return "Winnipeg Jets"
                case "WSH": return "Washington Capitals"
                default: return abbreviation.isEmpty ? "NHL Team" : abbreviation
                }
            }
        }
        struct ESPNLinescore: Decodable {
            let value: Double?
        }
        struct ESPNStatistic: Codable {
            let name: String
            let displayValue: String
            
            enum CodingKeys: String, CodingKey { case name, displayValue, abbreviation, value }
            
            // Written back out in the simple form (name + displayValue) so saved games reload identically.
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
                try container.encode(displayValue, forKey: .displayValue)
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                func firstAvailableString(_ keys: CodingKeys...) -> String {
                    for key in keys {
                        if let value = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil {
                            return value
                        }
                    }
                    return ""
                }
                name = firstAvailableString(.name, .abbreviation)
                displayValue = firstAvailableString(.displayValue, .value)
            }
        }
        
        var shotsOnGoal: String {
            let shotKeys: Set<String> = ["shotstotal", "shots", "totalshots", "shotsongoal"]
            return statistics?.first(where: { shotKeys.contains($0.name.lowercased()) })?.displayValue ?? "0"
        }
    }
    
    var awayTeam: ESPNCompetitor? { competitions.first?.competitors.first(where: { $0.homeAway == "away" }) }
    var homeTeam: ESPNCompetitor? { competitions.first?.competitors.first(where: { $0.homeAway == "home" }) }
    var venueDisplayText: String? {
        guard let venue = competitions.first?.venue else { return nil }
        let cityState = [venue.address?.city, venue.address?.state].compactMap { $0 }.joined(separator: ", ")
        switch (venue.fullName, cityState.isEmpty) {
        case (let name?, false): return "\(name) — \(cityState)"
        case (let name?, true): return name
        case (nil, false): return cityState
        case (nil, true): return nil
        }
    }
    
    var powerPlayTeamID: String? {
        return competitions.first?.situation?.teamOnPowerPlay?.id
    }
    
    var isPlayoffGame: Bool {
        return season?.type == 3
    }

    // ESPN season types: 1 = preseason, 2 = regular season, 3 = playoffs.
    // If a response ever omits the type, September games are treated as preseason.
    private var isSeptemberGame: Bool {
        guard let date = systemCalendarDate else { return false }
        return Calendar(identifier: .gregorian).component(.month, from: date) == 9
    }

    var isPreseasonGame: Bool {
        if let type = season?.type { return type == 1 }
        return isSeptemberGame
    }

    var countsTowardStandings: Bool {
        if let type = season?.type { return type == 2 }
        return !isSeptemberGame
    }
    
    var abstractState: String {
        switch status.type.state {
        case "in": return "Live"
        case "post": return "Final"
        default: return "Preview"
        }
    }
    
    var systemCalendarDate: Date? {
        HockeyNowFormatterCache.formatter(format: "yyyy-MM-dd'T'HH:mm'Z'", zone: TimeZone(secondsFromGMT: 0)!).date(from: date)
    }
}

struct ESPNGameSummary: Decodable {
    let scoringPlays: [ESPNPlay]?
    let plays: [ESPNPlay]?
    let penalties: [ESPNPenaltyItem]?
    let boxscore: ESPNBoxscore?
    let winProbability: [ESPNWinProbability]?
    let predictor: ESPNPredictor?
    
    // ESPN spells the key "winprobability"; both spellings are accepted. Each section is decoded on its own so one
    // oddly shaped section can no longer throw away the whole game summary.
    enum CodingKeys: String, CodingKey { case scoringPlays, plays, penalties, boxscore, winprobability, winProbability, predictor }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scoringPlays = (try? c.decodeIfPresent([ESPNPlay].self, forKey: .scoringPlays)) ?? nil
        plays = (try? c.decodeIfPresent([ESPNPlay].self, forKey: .plays)) ?? nil
        penalties = (try? c.decodeIfPresent([ESPNPenaltyItem].self, forKey: .penalties)) ?? nil
        boxscore = (try? c.decodeIfPresent(ESPNBoxscore.self, forKey: .boxscore)) ?? nil
        let lower = (try? c.decodeIfPresent([ESPNWinProbability].self, forKey: .winprobability)) ?? nil
        let camel = (try? c.decodeIfPresent([ESPNWinProbability].self, forKey: .winProbability)) ?? nil
        winProbability = lower ?? camel
        predictor = (try? c.decodeIfPresent(ESPNPredictor.self, forKey: .predictor)) ?? nil
    }
    
    // Pre-game "Matchup Predictor": each team's projected chance of winning, as text ("58.2") or a number.
    struct ESPNPredictor: Decodable {
        let homeTeam: ESPNPredictorTeam?
        let awayTeam: ESPNPredictorTeam?
        struct ESPNPredictorTeam: Decodable {
            let gameProjection: Double?
            enum CodingKeys: String, CodingKey { case gameProjection }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let d = try? c.decodeIfPresent(Double.self, forKey: .gameProjection) { gameProjection = d }
                else if let s = try? c.decodeIfPresent(String.self, forKey: .gameProjection) { gameProjection = Double(s) }
                else { gameProjection = nil }
            }
        }
        var homeFraction: Double? {
            if let h = homeTeam?.gameProjection { return normalizedWinProbability(h) }
            if let a = awayTeam?.gameProjection { return 1 - normalizedWinProbability(a) }
            return nil
        }
    }
    
    struct ESPNBoxscore: Codable {
        let teams: [ESPNBoxscoreTeam]?
        let players: [ESPNBoxscorePlayerGroup]?
        struct ESPNBoxscoreTeam: Codable {
            let team: ESPNBoxscoreTeamDetail?
            let statistics: [ESPNEvent.ESPNCompetitor.ESPNStatistic]?
            struct ESPNBoxscoreTeamDetail: Codable {
                let id: String?
                
                enum CodingKeys: String, CodingKey { case id }
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    if let stringID = try? container.decodeIfPresent(String.self, forKey: .id) {
                        id = stringID
                    } else if let intID = try? container.decodeIfPresent(Int.self, forKey: .id) {
                        id = String(intID)
                    } else {
                        id = nil
                    }
                }
            }
        }
        
        // ESPN returns one stat row per athlete.
        struct ESPNBoxscorePlayerGroup: Codable {
            let team: ESPNBoxscoreTeam.ESPNBoxscoreTeamDetail?
            let statistics: [ESPNPlayerStatCategory]?
        }
        struct ESPNPlayerStatCategory: Codable {
            let name: String?
            let keys: [String]?
            let labels: [String]?
            let athletes: [ESPNAthleteStatLine]?
        }
        struct ESPNAthleteStatLine: Codable {
            let athlete: ESPNBoxscoreAthlete?
            let stats: [String]?
        }
        struct ESPNBoxscoreAthlete: Codable {
            let id: String?
            let displayName: String?
            let shortName: String?
            let headshot: ESPNAthleteHeadshot?
            let position: ESPNAthletePosition?
            
            enum CodingKeys: String, CodingKey { case id, displayName, shortName, headshot, position }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let stringID = try? container.decodeIfPresent(String.self, forKey: .id) {
                    id = stringID
                } else if let intID = try? container.decodeIfPresent(Int.self, forKey: .id) {
                    id = String(intID)
                } else {
                    id = nil
                }
                displayName = try? container.decodeIfPresent(String.self, forKey: .displayName)
                shortName = try? container.decodeIfPresent(String.self, forKey: .shortName)
                headshot = try? container.decodeIfPresent(ESPNAthleteHeadshot.self, forKey: .headshot)
                position = try? container.decodeIfPresent(ESPNAthletePosition.self, forKey: .position)
            }
        }
        struct ESPNAthleteHeadshot: Codable { let href: String? }
        struct ESPNAthletePosition: Codable { let abbreviation: String? }
    }
    
    struct ESPNWinProbability: Decodable {
        let homeWinPercentage: Double
        let playId: String?
        enum CodingKeys: String, CodingKey { case homeWinPercentage, playId }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let d = try? c.decode(Double.self, forKey: .homeWinPercentage) { homeWinPercentage = d }
            else if let s = try? c.decode(String.self, forKey: .homeWinPercentage), let d = Double(s) { homeWinPercentage = d }
            else { throw DecodingError.dataCorruptedError(forKey: .homeWinPercentage, in: c, debugDescription: "no probability") }
            playId = try? c.decodeIfPresent(String.self, forKey: .playId)
        }
    }
}

struct ESPNPlay: Codable, Identifiable {
    var id: String {
        if let seq = sequenceNumber { return seq }
        return "\(clock.displayValue)-\(period.number)-\(text.hashValue)"
    }
    let sequenceNumber: String?
    let text: String
    let period: ESPNPeriod
    let clock: ESPNClock
    let scoringPlay: Bool?
    let team: ESPNPlayTeam?
    let type: ESPNPlayType?
    let strength: ESPNPlayStrength?
    
    struct ESPNPeriod: Codable { let number: Int }
    struct ESPNClock: Codable {
        let displayValue: String
        let value: Double?
    }
    struct ESPNPlayTeam: Codable { let id: String }
    struct ESPNPlayType: Codable { let text: String?; let abbreviation: String? }
    struct ESPNPlayStrength: Codable {
        let text: String?
        let abbreviation: String?
    }
}

struct ESPNPenaltyItem: Codable, Identifiable {
    var id: String { text }
    let text: String
}
