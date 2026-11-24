import Foundation

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
    var isRoutine: Bool { awaySkaters == 5 && homeSkaters == 5 && !hasEmptyNet }

    var emptyNetSide: Side? { awayEmptyNet ? .away : (homeEmptyNet ? .home : nil) }

    var powerPlaySide: Side? {
        let awayBase = awaySkaters - (awayEmptyNet ? 1 : 0)
        let homeBase = homeSkaters - (homeEmptyNet ? 1 : 0)
        if awayBase > homeBase { return .away }
        if homeBase > awayBase { return .home }
        return nil
    }

    var onText: String { "\(awaySkaters) on \(homeSkaters)" }

    func badgeText(awayAbbr: String, homeAbbr: String) -> String? {
        guard !isRoutine else { return nil }
        func abbr(_ side: Side) -> String { side == .away ? awayAbbr : homeAbbr }
        var parts = [onText]
        if let pp = powerPlaySide { parts.append("\(abbr(pp)) PP") }
        if let en = emptyNetSide { parts.append(powerPlaySide == en ? "EN" : "\(abbr(en)) EN") }
        return parts.joined(separator: " · ")
    }

    static func assumed(powerPlayIsHome: Bool, regularSeasonOvertime: Bool) -> GameStrength {
        let base = regularSeasonOvertime ? 3 : 5
        return GameStrength(awaySkaters: powerPlayIsHome ? base - 1 : base,
                            homeSkaters: powerPlayIsHome ? base : base - 1)
    }
}
