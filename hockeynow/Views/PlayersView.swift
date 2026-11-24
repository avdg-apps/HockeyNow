import SwiftUI

// MARK: - Players Panel
struct PlayersView: View {
    @ObservedObject var fetcher: ESPNNHLFetcher
    let currentLanguage: AppLanguage
    @State private var statGroup: PlayerStatGroup = .skaters
    @State private var showPlayersCalendar = false
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var minGamesPlayed: Int = 0
    @State private var skaterSort: SkaterSort = .points
    @State private var goalieSort: GoalieSort = .wins
    
    enum PlayerStatGroup: String, CaseIterable, Identifiable {
        case skaters, goalies
        var id: String { rawValue }
    }
    
    enum SkaterSort: String, CaseIterable, Identifiable {
        case points, goals, assists, team
        var id: String { rawValue }
        var label: String {
            switch self {
            case .points: return "Points"
            case .goals: return "Goals"
            case .assists: return "Assists"
            case .team: return "Team"
            }
        }
    }
    
    enum GoalieSort: String, CaseIterable, Identifiable {
        case wins, savePct, shutouts, team
        var id: String { rawValue }
        var label: String {
            switch self {
            case .wins: return "Wins"
            case .savePct: return "SV%"
            case .shutouts: return "Shutouts"
            case .team: return "Team"
            }
        }
    }
    
    private var playersDateString: String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; return formatter.string(from: fetcher.playersDate)
    }
    
    // Players level on the stat the table is sorted by share a rank, written "T2". Sorting by Team gives plain numbers.
    private func tieRankLabel(at index: Int, keys: [String?]) -> String {
        guard keys.indices.contains(index), let key = keys[index] else { return "\(index + 1)" }
        let first = keys.firstIndex { $0 == key } ?? index
        let tied = keys.filter { $0 == key }.count > 1
        return tied ? "T\(first + 1)" : "\(index + 1)"
    }
    
    private func skaterTieKey(_ skater: SkaterSeasonLine) -> String? {
        switch skaterSort {
        case .points: return "\(skater.points)"
        case .goals: return "\(skater.goals)"
        case .assists: return "\(skater.assists)"
        case .team: return nil
        }
    }
    
    private func goalieTieKey(_ goalie: GoalieSeasonLine) -> String? {
        switch goalieSort {
        case .wins: return "\(goalie.wins)"
        case .savePct: return String(format: "%.3f", goalie.savePercentage)
        case .shutouts: return "\(goalie.shutouts)"
        case .team: return nil
        }
    }
    
    private var filteredSkaters: [SkaterSeasonLine] {
        var pool = fetcher.skaterLeaders.filter { $0.gamesPlayed >= minGamesPlayed }
        let trimmed = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            pool = pool.filter { $0.displayName.lowercased().contains(trimmed) || $0.teamAbbreviation.lowercased().contains(trimmed) }
        }
        switch skaterSort {
        case .points: pool.sort { $0.points != $1.points ? $0.points > $1.points : $0.goals > $1.goals }
        case .goals: pool.sort { $0.goals != $1.goals ? $0.goals > $1.goals : $0.points > $1.points }
        case .assists: pool.sort { $0.assists != $1.assists ? $0.assists > $1.assists : $0.points > $1.points }
        case .team: pool.sort { $0.teamAbbreviation != $1.teamAbbreviation ? $0.teamAbbreviation < $1.teamAbbreviation : $0.points > $1.points }
        }
        return Array(pool.prefix(50))
    }
    
    private var filteredGoalies: [GoalieSeasonLine] {
        var pool = fetcher.goalieLeaders.filter { $0.gamesPlayed >= minGamesPlayed }
        let trimmed = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            pool = pool.filter { $0.displayName.lowercased().contains(trimmed) || $0.teamAbbreviation.lowercased().contains(trimmed) }
        }
        switch goalieSort {
        case .wins: pool.sort { $0.wins != $1.wins ? $0.wins > $1.wins : $0.savePercentage > $1.savePercentage }
        case .savePct: pool.sort { $0.savePercentage > $1.savePercentage }
        case .shutouts: pool.sort { $0.shutouts != $1.shutouts ? $0.shutouts > $1.shutouts : $0.wins > $1.wins }
        case .team: pool.sort { $0.teamAbbreviation != $1.teamAbbreviation ? $0.teamAbbreviation < $1.teamAbbreviation : $0.wins > $1.wins }
        }
        return Array(pool.prefix(50))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Leaders as of").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
                Button(action: { shiftPlayersDate(by: -1) }) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).padding(6).background(Color.primary.opacity(0.06)).cornerRadius(6)
                }.buttonStyle(.plain)
                Button(action: { showPlayersCalendar.toggle() }) {
                    Text(playersDateString).font(.system(size: 12, weight: .bold, design: .monospaced))
                }.buttonStyle(.plain).frame(width: 110)
                .popover(isPresented: $showPlayersCalendar, arrowEdge: .bottom) {
                    EnlargedCalendarPicker(selection: $fetcher.playersDate)
                }
                Button(action: { shiftPlayersDate(by: 1) }) {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).padding(6).background(Color.primary.opacity(0.06)).cornerRadius(6)
                }.buttonStyle(.plain)
                if fetcher.isLoadingPlayerStats { ProgressView().controlSize(.small).padding(.leading, 4) }
            }
            .padding(.horizontal, 4)
            
            HStack(spacing: 12) {
                Picker("", selection: $statGroup) {
                    Text(currentLanguage.localize("skaters")).tag(PlayerStatGroup.skaters)
                    Text(currentLanguage.localize("goalies")).tag(PlayerStatGroup.goalies)
                }
                .pickerStyle(.segmented)
                PreseasonToggle(fetcher: fetcher)
            }
            .padding(.horizontal, 4)
            
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(.secondary)
                TextField("Search a player...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onChange(of: searchText) { _, newValue in
                        searchDebounceTask?.cancel()
                        searchDebounceTask = Task {
                            try? await Task.sleep(nanoseconds: 180_000_000)
                            if Task.isCancelled { return }
                            debouncedSearchText = newValue
                        }
                    }
                if !searchText.isEmpty {
                    Button(action: { searchText = ""; debouncedSearchText = ""; searchDebounceTask?.cancel() }) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 4)
            
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("Min GP").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
                    Stepper("\(minGamesPlayed)", value: $minGamesPlayed, in: 0...82)
                        .font(.system(size: 10, design: .monospaced))
                        .labelsHidden()
                    Text("\(minGamesPlayed)").font(.system(size: 10, weight: .bold, design: .monospaced)).frame(width: 18)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("Sort").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
                    if statGroup == .skaters {
                        Menu {
                            ForEach(SkaterSort.allCases) { option in
                                Button(option.label) { skaterSort = option }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(skaterSort.label)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    } else {
                        Menu {
                            ForEach(GoalieSort.allCases) { option in
                                Button(option.label) { goalieSort = option }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(goalieSort.label)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 4)
            
            ScrollView {
                if let progress = fetcher.playerStatsLoadProgress {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                                .frame(width: 160)
                            Text("Loading game \(progress.completed) of \(progress.total)…")
                                .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                        }
                        Spacer()
                    }.padding(.top, 60)
                } else if statGroup == .skaters {
                    if filteredSkaters.isEmpty {
                        emptyState
                    } else {
                        skaterTable
                    }
                } else {
                    if filteredGoalies.isEmpty {
                        emptyState
                    } else {
                        goalieTable
                    }
                }
            }
        }
        .padding(14)
        .onAppear { fetcher.loadPlayerLeadersIfNeeded() }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 42)).foregroundColor(.secondary.opacity(0.4))
            Text(fetcher.isLoadingPlayerStats ? "Loading player stats..." : (debouncedSearchText.isEmpty && minGamesPlayed == 0 ? "No stats recorded yet for this date." : "No matching players."))
                .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
        }
        // Forcing full width here is what actually centers this - the outer VStack for this whole
        // view is left-aligned (so the date/search/filter rows above hug the leading edge like the
        // rest of the app), and without an explicit frame this block just inherits that instead of
        // centering itself inside the scroll area.
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
    
    private var skaterTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("#").frame(width: 22, alignment: .leading)
                Text("PLAYER").frame(width: 160, alignment: .leading)
                Spacer()
                Text("GP").frame(width: 30, alignment: .center)
                Text("G").frame(width: 30, alignment: .center)
                Text("A").frame(width: 30, alignment: .center)
                Text("PTS").frame(width: 35, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.vertical, 4).padding(.horizontal, 8)
            
            Divider()
            let skaters = filteredSkaters
            let skaterKeys = skaters.map { skaterTieKey($0) }
            LazyVStack(spacing: 0) {
                ForEach(Array(skaters.enumerated()), id: \.element.id) { index, entry in
                    HStack {
                        Text(tieRankLabel(at: index, keys: skaterKeys)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7).frame(width: 22, alignment: .leading)
                        HStack(spacing: 6) {
                            PlayerHeadshotView(headshotURLString: entry.headshotURL, initials: initials(for: entry.displayName), size: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(entry.displayName).font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)
                                Text("\(entry.teamAbbreviation)\(entry.position.isEmpty ? "" : " · \(entry.position)")").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                            }
                        }.frame(width: 160, alignment: .leading)
                        Spacer()
                        Text("\(entry.gamesPlayed)").frame(width: 30, alignment: .center)
                        Text("\(entry.goals)").frame(width: 30, alignment: .center)
                        Text("\(entry.assists)").frame(width: 30, alignment: .center)
                        Text("\(entry.points)")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.amber)
                            .frame(width: 35, alignment: .trailing)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.01))
                }
            }
        }
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
    }
    
    private var goalieTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("#").frame(width: 22, alignment: .leading)
                Text("PLAYER").frame(width: 150, alignment: .leading)
                Spacer()
                Text("GP").frame(width: 28, alignment: .center)
                Text("W").frame(width: 28, alignment: .center)
                Text("L").frame(width: 28, alignment: .center)
                        Text("OTL").frame(width: 32, alignment: .center)
                        Text("SO").frame(width: 28, alignment: .center)
                        Text("SV%").frame(width: 45, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.vertical, 4).padding(.horizontal, 8)
            
            Divider()
            
            let goalies = filteredGoalies
            let goalieKeys = goalies.map { goalieTieKey($0) }
            LazyVStack(spacing: 0) {
                ForEach(Array(goalies.enumerated()), id: \.element.id) { index, entry in
                    HStack {
                        Text(tieRankLabel(at: index, keys: goalieKeys)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7).frame(width: 22, alignment: .leading)
                        HStack(spacing: 6) {
                            PlayerHeadshotView(headshotURLString: entry.headshotURL, initials: initials(for: entry.displayName), size: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(entry.displayName).font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)
                                Text(entry.teamAbbreviation).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                            }
                        }.frame(width: 150, alignment: .leading)
                        Spacer()
                        Text("\(entry.gamesPlayed)").frame(width: 28, alignment: .center)
                        Text("\(entry.wins)").frame(width: 28, alignment: .center)
                        Text("\(entry.losses)").frame(width: 28, alignment: .center)
                        Text("\(entry.otLosses)").frame(width: 32, alignment: .center)
                        Text("\(entry.shutouts)").frame(width: 28, alignment: .center)
                        Text(String(format: "%.3f", entry.savePercentage))
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.amber)
                            .frame(width: 45, alignment: .trailing)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.01))
                }
            }
        }
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
    }
    
    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.compactMap { $0.first }.prefix(2)
        return String(letters).uppercased()
    }
    
    private func shiftPlayersDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: fetcher.playersDate) {
            fetcher.playersDate = newDate
        }
    }
}

// MARK: - Headshot
struct PlayerHeadshotView: View {
    let headshotURLString: String?
    let initials: String
    var size: CGFloat = 20
    
    var body: some View {
        if let urlString = headshotURLString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
                case .failure(_), .empty:
                    fallback
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }
    
    private var fallback: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.1))
            Text(initials).font(.system(size: size * 0.4, weight: .black, design: .monospaced)).foregroundColor(.secondary)
        }.frame(width: size, height: size)
    }
}
