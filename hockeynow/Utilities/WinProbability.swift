import Foundation

func normalizedWinProbability(_ series: [Double]) -> [Double] {
    guard let maxValue = series.max() else { return series }
    return maxValue > 1.0 ? series.map { $0 / 100.0 } : series
}

func normalizedWinProbability(_ value: Double) -> Double { value > 1.0 ? value / 100.0 : value }

enum WinProbabilityModel {
    private static func poisson(mean: Double, upTo n: Int) -> [Double] {
        var out = [Double](repeating: 0, count: n + 1)
        out[0] = exp(-mean)
        if n >= 1 { for k in 1...n { out[k] = out[k - 1] * mean / Double(k) } }
        return out
    }

    static func homeWin(lead: Int, regulationSecondsLeft: Double, pregameHome: Double) -> Double {
        let minutes = max(regulationSecondsLeft, 0) / 60.0
        let tilt = 0.8 * (pregameHome - 0.5)
        let muHome = 0.055 * minutes * exp(tilt)
        let muAway = 0.055 * minutes * exp(-tilt)
        let n = 18
        let ph = poisson(mean: muHome, upTo: n), pa = poisson(mean: muAway, upTo: n)
        var win = 0.0, tie = 0.0
        for i in 0...n { for j in 0...n {
            let net = lead + i - j, p = ph[i] * pa[j]
            if net > 0 { win += p } else if net == 0 { tie += p }
        } }
        let overtimeEdge = 0.5 + (pregameHome - 0.5) * 0.4
        return min(max(win + tie * overtimeEdge, 0.005), 0.995)
    }

    static func pregameHome(
        homePointsPct: Double,
        awayPointsPct: Double,
        homeRecentPointsPct: Double? = nil,
        awayRecentPointsPct: Double? = nil,
        homeGoalDiffPerGame: Double? = nil,
        awayGoalDiffPerGame: Double? = nil
    ) -> Double {
        let homeSeason = min(max(homePointsPct, 0.05), 0.95)
        let awaySeason = min(max(awayPointsPct, 0.05), 0.95)
        let seasonLogOdds = log(homeSeason / (1 - homeSeason)) - log(awaySeason / (1 - awaySeason))
        let recentEdge = ((homeRecentPointsPct ?? homeSeason) - (awayRecentPointsPct ?? awaySeason)) * 0.35
        let goalDiffEdge = ((homeGoalDiffPerGame ?? 0) - (awayGoalDiffPerGame ?? 0)) * 0.025
        let combinedLogOdds = seasonLogOdds * 0.65 + recentEdge + goalDiffEdge
        let ratingChance = 1 / (1 + exp(-combinedLogOdds))
        return min(max(ratingChance + 0.03, 0.05), 0.95)
    }
}

struct WinProbabilityReading {
    let homeFraction: Double
    let isEstimate: Bool
    let isPregame: Bool
}
