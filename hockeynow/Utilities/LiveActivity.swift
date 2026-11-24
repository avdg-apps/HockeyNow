import Foundation

struct LiveActivityEvent: Identifiable, Equatable {
    enum Kind: String { case goal, penalty, periodEnd, overtime, final }
    let id = UUID()
    let kind: Kind
    let gameID: String
    let title: String
    let detail: String
    let teamAbbreviation: String

    var symbol: String {
        switch kind {
        case .goal: return "light.beacon.max.fill"
        case .penalty: return "exclamationmark.triangle.fill"
        case .periodEnd: return "timer"
        case .overtime: return "bolt.fill"
        case .final: return "flag.checkered"
        }
    }

    var gameURL: URL? { URL(string: "https://www.espn.com/nhl/game/_/gameId/\(gameID)") }
}
