import SwiftUI

// MARK: - Row Layout
struct AdaptivePlayRow: View {
    let play: ESPNPlay; let awayAbbr: String; let homeAbbr: String; let awayID: String; let homeID: String
    let fetcherManager: ESPNNHLFetcher
    let gameID: String
    var body: some View {
        let rawText = play.text
        let shotType = detectShotType(from: rawText)
        let goalType = detectGoalType(
            from: rawText,
            typeText: play.type?.text,
            typeAbbreviation: play.type?.abbreviation,
            strengthText: play.strength?.text,
            strengthAbbreviation: play.strength?.abbreviation
        )
        let goalDetails = parseGoalDetails(from: rawText)
        let scorerInfo = parseScorer(from: rawText)
        let seasonGoals = scorerInfo.goals ?? seasonGoalTotal(forScorer: scorerInfo.name)
        let formattedGoalDescription: String = {
            guard !scorerInfo.name.isEmpty else { return parseGoalProfile(from: rawText) }
            if let seasonGoals { return "\(scorerInfo.name) (\(seasonGoals))" }
            return scorerInfo.name
        }()
        
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 6) {
                Text("P\(play.period.number) - \(play.clock.displayValue)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedGoalDescription)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                    Text(goalDetails.assists.isEmpty ? "Unassisted" : "Assisted by \(goalDetails.assists)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .lineLimit(2)
                Spacer()
                // Opens the ESPN game page, where the goal replays and highlights are.
                if let gamecast = URL(string: "https://www.espn.com/nhl/game/_/gameId/\(gameID)") {
                    Link(destination: gamecast) {
                        Image(systemName: "play.rectangle").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    .help("Open this game on ESPN")
                }
            }
            
            HStack(spacing: 5) {

                Text("\(scoringTeamAbbreviation) GOAL")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(getGameTeamColor(abbreviation: scoringTeamAbbreviation, isHome: scoringTeamAbbreviation == homeAbbr,
                                                 opponent: scoringTeamAbbreviation == homeAbbr ? awayAbbr : homeAbbr))
                    .cornerRadius(4)
                
                if !shotType.isEmpty {
                    Text(shotType.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.35))
                        .cornerRadius(4)
                }
                
                if !goalType.isEmpty {
                    Text(goalType)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // ESPN writes scoring plays as "Connor McDavid (24) Wrist Shot, assisted by ...", where the bracketed number is the
    // scorer's season goal count at that moment. Take the name before it, and the number itself.
    private func parseScorer(from source: String) -> (name: String, goals: Int?) {
        var cleaned = source.replacingOccurrences(of: "Goal scored by ", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "Scored by ", with: "", options: .caseInsensitive)
        if let range = cleaned.range(of: "\\(\\d+\\)", options: .regularExpression) {
            let name = cleaned[..<range.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " ,-–").union(.whitespacesAndNewlines))
            let digits = cleaned[range].filter(\.isNumber)
            if !name.isEmpty { return (name, Int(digits)) }
        }
        // No bracketed number: fall back to everything before the first comma / shot description / assist.
        var name = cleaned
        for marker in [" assisted by ", " assists: ", " assist: ", ","] {
            if let r = name.range(of: marker, options: .caseInsensitive) { name = String(name[..<r.lowerBound]) }
        }
        for shot in ["Bat Shot", "Slap Shot", "Wrist Shot", "Snap Shot", "Wrap-around", "Tip-In", "Backhand", "Deflected", "Penalty Shot", "Lacrosse", "Michigan"] {
            name = name.replacingOccurrences(of: shot, with: "", options: .caseInsensitive)
        }
        return (name.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }

    // Fallback when the play text carries no number: the goal total from the loaded leaderboard.
    private func seasonGoalTotal(forScorer name: String) -> Int? {
        guard !name.isEmpty else { return nil }
        let abbr = scoringTeamAbbreviation
        let match = fetcherManager.skaterLeaders.first { $0.displayName == name && $0.teamAbbreviation == abbr }
            ?? fetcherManager.skaterLeaders.first { $0.displayName == name }
        return match?.goals
    }

    private var scoringTeamAbbreviation: String {
        if let teamID = play.team?.id {
            if teamID == awayID { return awayAbbr }
            if teamID == homeID { return homeAbbr }
        }
        let txt = play.text.lowercased()
        if txt.contains(awayID.lowercased()) || txt.contains(awayAbbr.lowercased()) { return awayAbbr }
        return homeAbbr
    }
    
    func detectShotType(from text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("batted") || lower.contains("bat shot") { return "Bat Shot" }
        if lower.contains("slap") { return "Slap Shot" }
        if lower.contains("lacrosse") || lower.contains ("lacrosse shot") || lower.contains ("lacrosse-style shot") {return "Lacrosse"}
        if lower.contains("michigan") {return "Michigan"}
        if lower.contains("wrist") { return "Wrist Shot" }
        if lower.contains("snap") { return "Snap Shot" }
        if lower.contains("wrap") { return "Wrap-around" }
        if lower.contains("tip") { return "Tip-In" }
        if lower.contains("backhand") { return "Backhand" }
        if lower.contains("deflect") { return "Deflected" }
        if lower.contains("penalty") { return "Penalty Shot" }
        return ""
    }
    
    func detectGoalType(
        from text: String,
        typeText: String? = nil,
        typeAbbreviation: String? = nil,
        strengthText: String? = nil,
        strengthAbbreviation: String? = nil
    ) -> String {
        let lower = [text, typeText ?? "", typeAbbreviation ?? "", strengthText ?? "", strengthAbbreviation ?? ""]
            .joined(separator: " ")
            .lowercased()
        
        func anchoredMatch(_ pattern: String) -> Bool {
            lower.range(of: pattern, options: .regularExpression) != nil
        }
        
        if anchoredMatch("\\(pp\\)") || anchoredMatch("\\bppg\\b") || anchoredMatch("\\bpp\\b") || lower.contains("power play") || lower.contains("power-play") {
            return "PPG"
        }
        if anchoredMatch("\\(sh\\)") || anchoredMatch("\\bshg\\b") || anchoredMatch("\\bsh\\b") || lower.contains("short handed") || lower.contains("short-handed") || lower.contains("shorthanded") {
            return "SHG"
        }
        if anchoredMatch("\\(en\\)") || anchoredMatch("\\beng\\b") || anchoredMatch("\\ben\\b") || lower.contains("empty net") || lower.contains ("EN") || lower.contains("empty-net") || lower.contains("emptynet") {
            return "ENG"
        }
        if lower.contains("own goal") || lower.contains("own") || lower.contains("own-goal") {
            return "OWN"
        }
        return ""
    }
    
    private func parseGoalDetails(from source: String) -> (scorer: String, assists: String) {
        var cleaned = source.replacingOccurrences(of: "Goal scored by ", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "Scored by ", with: "", options: .caseInsensitive)
        let goalCountPattern = "\\s*\\(\\d+\\)"
        cleaned = cleaned.replacingOccurrences(of: goalCountPattern, with: "", options: .regularExpression)
        let signatures = [" assisted by ", " assists: ", " assist: "]
        for signature in signatures where cleaned.localizedCaseInsensitiveContains(signature) {
            let pieces = cleaned.components(separatedBy: signature)
            let scorer = pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let assists = pieces.dropFirst().joined(separator: ", ").replacingOccurrences(of: " and ", with: ", ", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
            return (scorer, assists)
        }
        return (cleaned.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func parseGoalProfile(from source: String) -> String {
        var cleaned = source.replacingOccurrences(of: "Goal scored by ", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "Scored by ", with: "", options: .caseInsensitive)
        let metadataStrings = [
            "(Power Play)", "(Power-Play)", "(Short Handed)", "(Short-Handed)",
            "(Empty Net)", "(Empty-Net)", "(Own Goal)", "(Own-Goal)", "(Awarded)",
            "(PP)", "(SH)", "(EN)", "PPG", "SHG", "ENG", "Bat Shot", "Slap Shot", "Wrist Shot",
            "Snap Shot", "Wrap-around", "Tip-In", "Backhand", "Deflected", "Batted", "Bat Shot", "Penalty Shot"
        ]
        for match in metadataStrings { cleaned = cleaned.replacingOccurrences(of: match, with: "", options: .caseInsensitive) }
        let splitSignatures = [" assisted by ", " assists: ", " assist: "]
        for signature in splitSignatures {
            if cleaned.localizedCaseInsensitiveContains(signature) {
                let components = cleaned.components(separatedBy: signature)
                if let goalScorer = components.first, components.count > 1 {
                    let assists = components[1].replacingOccurrences(of: " and ", with: ", ", options: .caseInsensitive)
                    return "\(goalScorer.trimmingCharacters(in: .whitespacesAndNewlines)) (\(assists.trimmingCharacters(in: .whitespacesAndNewlines)))"
                }
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func verifyGoalTypeFromJSON(teamID: String?, gameID: String) -> String {
        guard let teamID = teamID else { return "" }
        
        if let cachedGameStats = fetcherManager.historicalTelemetryCache[gameID],
           let teamStatsArray = cachedGameStats[teamID] {
            
            if let ppgStat = teamStatsArray.first(where: { $0.name == "powerPlayGoals" }),
               let count = Int(ppgStat.displayValue), count > 0 {
                return "PPG"
            }
            
            if let shgStat = teamStatsArray.first(where: { $0.name == "shortHandedGoals" }),
               let count = Int(shgStat.displayValue), count > 0 {
                return "SHG"
            }
        }
        
        return ""
    }
}
