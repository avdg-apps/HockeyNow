import SwiftUI

struct LeadersView: View {
    @ObservedObject var fetcher: ESPNNHLFetcher
    @StateObject private var rookies = RookieDirectory()
    @State private var group: LeaderGroup = .overall
    @State private var category: Category = .points

    enum LeaderGroup: String, CaseIterable, Identifiable {
        case overall = "Overall", rookies = "Rookies", goalies = "Goalies"
        var id: String { rawValue }
        var categories: [Category] {
            switch self {
            case .overall: return [.points, .goals, .assists, .pointsPerGame]
            case .rookies: return [.points, .goals, .assists, .goalieWins, .savePercentage]
            case .goalies: return [.goalieWins, .savePercentage, .goalsAgainstAverage, .shutouts]
            }
        }
    }

    enum Category: String, Identifiable {
        case points = "Points", goals = "Goals", assists = "Assists", pointsPerGame = "Pts / GP"
        case goalieWins = "Wins", savePercentage = "SV%", goalsAgainstAverage = "GAA", shutouts = "Shutouts"
        var id: String { rawValue }
    }

    private struct Row: Identifiable {
        let id: String
        let name: String
        let team: String
        let logo: String?
        let headshot: String?
        let value: String
        let detail: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LEAGUE LEADERS").font(.system(size: 11, weight: .black, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $group) {
                    ForEach(LeaderGroup.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(group.categories) { item in
                        Button { category = item } label: {
                            Text(item.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(category == item ? Color.amber.opacity(0.9) : Color.primary.opacity(0.07))
                                .foregroundColor(category == item ? .black : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }

            content
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.03))
        .onChange(of: group) { _, newGroup in
            if !newGroup.categories.contains(category) { category = newGroup.categories[0] }
        }
        .task { fetcher.loadPlayerLeadersIfNeeded() }
        .task(id: group) {
            guard group == .rookies else { return }
            await rookies.load(teamIDs: teamIDs())
        }
    }

    @ViewBuilder
    private var content: some View {
        if !fetcher.hasLoadedPlayerLeaders || fetcher.isLoadingPlayerStats {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                if let progress = fetcher.playerStatsLoadProgress {
                    Text("Loading season stats \(progress.0)/\(progress.1)")
                } else {
                    Text("Loading season stats…")
                }
            }
            .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if group == .rookies && rookies.isLoading {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Finding rookies…").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if group == .rookies && rookies.rookieIDs.isEmpty {
            Text("Rookie data isn't available right now.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let rows = leaderRows()
            if rows.isEmpty {
                Text("No stats yet").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            rowView(rank: rankInfo(index, in: rows), row: row)
                            if index < rows.count - 1 { Divider().opacity(0.3) }
                        }
                    }
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
    }

    private func rankInfo(_ index: Int, in rows: [Row]) -> (label: String, number: Int) {
        let value = rows[index].value
        let first = rows.firstIndex { $0.value == value } ?? index
        let tied = rows.filter { $0.value == value }.count > 1
        return (tied ? "T\(first + 1)" : "\(index + 1)", first + 1)
    }

    private func rowView(rank: (label: String, number: Int), row: Row) -> some View {
        HStack(spacing: 8) {
            Text(rank.label)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(rank.number <= 3 ? .amber : .secondary)
                .frame(width: 28)
            PlayerHeadshotView(headshotURLString: row.headshot,
                               initials: String(row.name.split(separator: " ").compactMap { $0.first }.prefix(2)).uppercased(), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)
                HStack(spacing: 4) {
                    TeamLogoView(logoURLString: row.logo, teamAbbreviation: row.team, size: 12)
                    Text(row.team).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(row.value).font(.system(size: 14, weight: .black, design: .monospaced))
                Text(row.detail).font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func teamIDs() -> [String] {
        (fetcher.seasonGames + fetcher.rawFetchedGames).flatMap { $0.competitions.first?.competitors.map(\.id) ?? [] }
    }

    private func savePercentText(_ value: Double) -> String {
        let text = String(format: "%.3f", value)
        return text.hasPrefix("0") ? String(text.dropFirst()) : text
    }

    private func leaderRows() -> [Row] {
        let onlyRookies = group == .rookies
        let rookieIDs = rookies.rookieIDs

        switch category {
        case .points, .goals, .assists, .pointsPerGame:
            var skaters = fetcher.skaterLeaders
            if onlyRookies { skaters = skaters.filter { rookieIDs.contains($0.id) } }
            if category == .pointsPerGame {
                let minimum = min(10, max(1, (skaters.map(\.gamesPlayed).max() ?? 1) / 2))
                skaters = skaters.filter { $0.gamesPlayed >= minimum }
            }
            func score(_ s: SkaterSeasonLine) -> Double {
                switch category {
                case .goals: return Double(s.goals)
                case .assists: return Double(s.assists)
                case .pointsPerGame: return s.gamesPlayed > 0 ? Double(s.points) / Double(s.gamesPlayed) : 0
                default: return Double(s.points)
                }
            }
            return skaters
                .filter { score($0) > 0 }
                .sorted { score($0) != score($1) ? score($0) > score($1) : ($0.points, $0.goals) > ($1.points, $1.goals) }
                .prefix(10)
                .map { s in
                    Row(id: s.id, name: s.displayName, team: s.teamAbbreviation, logo: s.teamLogo, headshot: s.headshotURL,
                        value: category == .pointsPerGame ? String(format: "%.2f", score(s)) : "\(Int(score(s)))",
                        detail: "\(s.goals)G \(s.assists)A · \(s.gamesPlayed) GP")
                }

        case .goalieWins, .savePercentage, .goalsAgainstAverage, .shutouts:
            var goalies = fetcher.goalieLeaders
            if onlyRookies { goalies = goalies.filter { rookieIDs.contains($0.id) } }
            if category == .savePercentage || category == .goalsAgainstAverage {
                let minimum = min(10, max(1, (goalies.map(\.gamesPlayed).max() ?? 1) / 2))
                goalies = goalies.filter { $0.gamesPlayed >= minimum && $0.shotsAgainst > 0 }
            }
            let ordered: [GoalieSeasonLine]
            switch category {
            case .savePercentage: ordered = goalies.sorted { $0.savePercentage > $1.savePercentage }
            case .goalsAgainstAverage: ordered = goalies.sorted { $0.goalsAgainstAverage < $1.goalsAgainstAverage }
            case .shutouts: ordered = goalies.filter { $0.shutouts > 0 }.sorted { ($0.shutouts, $0.wins) > ($1.shutouts, $1.wins) }
            default: ordered = goalies.filter { $0.wins > 0 }.sorted { ($0.wins, $0.savePercentage) > ($1.wins, $1.savePercentage) }
            }
            return ordered.prefix(10).map { g in
                let value: String
                switch category {
                case .savePercentage: value = savePercentText(g.savePercentage)
                case .goalsAgainstAverage: value = String(format: "%.2f", g.goalsAgainstAverage)
                case .shutouts: value = "\(g.shutouts)"
                default: value = "\(g.wins)"
                }
                return Row(id: g.id, name: g.displayName, team: g.teamAbbreviation, logo: g.teamLogo, headshot: g.headshotURL,
                           value: value, detail: "\(g.wins)-\(g.losses)-\(g.otLosses) · \(g.gamesPlayed) GP")
            }
        }
    }
}
