import Foundation

// MARK: - On-ice strength
// How many skaters each team has on the ice and whether each goalie is in net.
// Source of truth is the NHL's own `situationCode`: four digits, [away goalie][away skaters][home skaters][home goalie].
// e.g. 1551 = 5 on 5, both goalies in. 1451 = away 4 skaters, home 5 (home power play). 0651 = away pulled its goalie.
nonisolated struct GameStrength: Equatable {
    let awaySkaters: Int
    let homeSkaters: Int
    let awayGoalieIn: Bool
    let homeGoalieIn: Bool

    init(awaySkaters: Int, homeSkaters: Int, awayGoalieIn: Bool = true, homeGoalieIn: Bool = true) {
        self.awaySkaters = awaySkaters
        self.homeSkaters = homeSkaters
        self.awayGoalieIn = awayGoalieIn
        self.homeGoalieIn = homeGoalieIn
    }

    init?(situationCode: String) {
        let digits = situationCode.compactMap { $0.wholeNumberValue }
        guard digits.count == 4 else { return nil }
        awayGoalieIn = digits[0] > 0
        awaySkaters = digits[1]
        homeSkaters = digits[2]
        homeGoalieIn = digits[3] > 0
    }

    enum Side { case away, home }

    var awayEmptyNet: Bool { !awayGoalieIn }
    var homeEmptyNet: Bool { !homeGoalieIn }
    var hasEmptyNet: Bool { awayEmptyNet || homeEmptyNet }
    /// Plain 5 on 5 with both goalies in: nothing worth showing.
    var isRoutine: Bool { awaySkaters == 5 && homeSkaters == 5 && !hasEmptyNet }

    /// The team that pulled its goalie (nil if neither did).
    var emptyNetSide: Side? { awayEmptyNet ? .away : (homeEmptyNet ? .home : nil) }

    /// The team on a real power play. A pulled goalie adds an extra attacker but is not a power play,
    /// so that extra skater is set aside before the two teams are compared.
    var powerPlaySide: Side? {
        let awayBase = awaySkaters - (awayEmptyNet ? 1 : 0)
        let homeBase = homeSkaters - (homeEmptyNet ? 1 : 0)
        if awayBase > homeBase { return .away }
        if homeBase > awayBase { return .home }
        return nil
    }

    /// Always "<away skaters> on <home skaters>": 5 on 4 (away power play), 4 on 5 (home power play),
    /// 6 on 5 (away goalie pulled), 4 on 6 (home goalie pulled while shorthanded-against), 3 on 6, 3 on 3 ...
    var onText: String { "\(awaySkaters) on \(homeSkaters)" }

    /// Badge text for the notch / cards, or nil when it is ordinary 5 on 5.
    func badgeText(awayAbbr: String, homeAbbr: String) -> String? {
        guard !isRoutine else { return nil }
        func abbr(_ side: Side) -> String { side == .away ? awayAbbr : homeAbbr }
        var parts = [onText]
        if let pp = powerPlaySide { parts.append("\(abbr(pp)) PP") }
        if let en = emptyNetSide { parts.append(powerPlaySide == en ? "EN" : "\(abbr(en)) EN") }
        return parts.joined(separator: " · ")
    }

    /// Fallback when only "which team is on the power play" is known: assume a single minor penalty
    /// (regular-season overtime is 3 on 3, so a power play there is 4 on 3).
    static func assumed(powerPlayIsHome: Bool, regularSeasonOvertime: Bool) -> GameStrength {
        let base = regularSeasonOvertime ? 3 : 5
        return GameStrength(awaySkaters: powerPlayIsHome ? base - 1 : base,
                            homeSkaters: powerPlayIsHome ? base : base - 1)
    }
}
