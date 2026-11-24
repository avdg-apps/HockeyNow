import SwiftUI

// MARK: - Panel
struct LeagueStandingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var fetcher: ESPNNHLFetcher
    @State private var showStandingsCalendar = false
    @AppStorage("standings_view_mode") private var storedMode = StandingsViewMode.division.rawValue
    @AppStorage("favorite_team_abbreviation") private var favouriteTeamAbbreviation = ""
    @AppStorage("app_theme") private var storedTheme = AppTheme.system.rawValue

    private var mode: StandingsViewMode { StandingsViewMode(rawValue: storedMode) ?? .division }
    private var displayedGroups: [StandingGroup] { standingGroups(for: mode, from: fetcher.standingsGroups) }
    
    private var standingsDateString: String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; return formatter.string(from: fetcher.standingsDate)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Standings as of").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
                    Spacer()
                    Button(action: { shiftStandingsDate(by: -1) }) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).padding(6).background(Color.primary.opacity(0.06)).cornerRadius(6)
                    }.buttonStyle(.plain)
                    Button(action: { showStandingsCalendar.toggle() }) {
                        Text(standingsDateString).font(.system(size: 12, weight: .bold, design: .monospaced))
                    }.buttonStyle(.plain).frame(width: 110)
                    .popover(isPresented: $showStandingsCalendar, arrowEdge: .bottom) {
                        EnlargedCalendarPicker(selection: $fetcher.standingsDate)
                    }
                    Button(action: { shiftStandingsDate(by: 1) }) {
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).padding(6).background(Color.primary.opacity(0.06)).cornerRadius(6)
                    }.buttonStyle(.plain)
                    if fetcher.isLoadingStandings { ProgressView().controlSize(.small).padding(.leading, 4) }
                }
                .padding(.horizontal, 4)

                // The view picker and the preseason switch live on their own row, apart from the date controls.
                HStack(spacing: 12) {
                    Picker("", selection: $storedMode) {
                        ForEach(StandingsViewMode.allCases) { viewMode in
                            Text(viewMode.rawValue).tag(viewMode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    PreseasonToggle(fetcher: fetcher)
                }
                .padding(.horizontal, 4)
                
                if fetcher.standingsGroups.isEmpty {
                    HStack {
                        Spacer()
                        Text(fetcher.isLoadingStandings ? "Loading standings..." : (fetcher.showPreseasonOnly ? "No completed preseason games for this date." : "No completed games yet for this date."))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }.padding(.top, 40)
                } else {
                    ForEach(displayedGroups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title.uppercased())
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 0) {
                                HStack(spacing: 3) {
                                    Text("#").frame(width: 26, alignment: .leading)
                                    Text("TEAM").frame(width: 122, alignment: .leading)
                                    Spacer()
                                    Text("GP").frame(width: 30, alignment: .center)
                                    Text("W").frame(width: 30, alignment: .center)
                                    Text("L").frame(width: 30, alignment: .center)
                                    Text("OT").frame(width: 30, alignment: .center)
                                    Text("ROW").frame(width: 32, alignment: .center).help("Regulation + overtime wins: the second tiebreaker after games played and RW")
                                    Text("PTS").frame(width: 35, alignment: .trailing)
                                    Text("GD").frame(width: 36, alignment: .trailing)
                                    Text("L10").frame(width: 52, alignment: .center)
                                    Text("STRK").frame(width: 40, alignment: .center)
                                }
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                
                                Divider()
                                
                                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                    let isFavourite = !favouriteTeamAbbreviation.isEmpty && entry.teamAbbreviation == favouriteTeamAbbreviation
                                    let favouriteColor = getReadableFavouriteTeamColor(abbreviation: favouriteTeamAbbreviation, theme: AppTheme(rawValue: storedTheme) ?? .system, colorScheme: colorScheme)
                                    HStack(spacing: 3) {
                                        Text(standingRankLabel(at: index, in: group.entries))
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 26, alignment: .leading)
                                        HStack(spacing: 6) {
                                            TeamLogoView(logoURLString: entry.teamLogo, teamAbbreviation: entry.teamAbbreviation, size: 16)
                                            Text(entry.teamDisplayName)
                                                .font(.system(size: 11, weight: isFavourite ? .black : .semibold, design: .monospaced))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                            if isFavourite {
                                                Image(systemName: "heart.fill").font(.system(size: 8)).foregroundColor(favouriteColor)
                                            }
                                            if index < group.wildCardSlots {
                                                Text("WC\(index + 1)")
                                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                                    .padding(.horizontal, 3).padding(.vertical, 1)
                                                    .background(Color.amber)
                                                    .foregroundColor(.black)
                                                    .cornerRadius(3)
                                            }
                                        }
                                        .frame(width: 122, alignment: .leading)
                                        
                                        Spacer()
                                        Text("\(entry.gamesPlayed)").frame(width: 30, alignment: .center)
                                        Text("\(entry.wins)").frame(width: 30, alignment: .center)
                                        Text("\(entry.losses)").frame(width: 30, alignment: .center)
                                        Text("\(entry.otLosses)").frame(width: 30, alignment: .center)
                                        Text("\(entry.regulationOvertimeWins)").foregroundColor(.secondary).frame(width: 32, alignment: .center)
                                        Text("\(entry.points)")
                                            .font(.system(size: 11, weight: .black, design: .monospaced))
                                            .foregroundColor(.amber)
                                            .frame(width: 35, alignment: .trailing)
                                        Text(entry.goalDifferentialText)
                                            .foregroundColor(entry.goalDifferential > 0 ? .green : (entry.goalDifferential < 0 ? .red : .secondary))
                                            .frame(width: 36, alignment: .trailing)
                                        Text(entry.last10Text)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                                            .frame(width: 52, alignment: .center)
                                        streakChip(for: entry).frame(width: 40, alignment: .center)
                                    }
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                                    .background(isFavourite ? favouriteColor.opacity(0.16) : Color.primary.opacity(0.01))
                                    .overlay(alignment: .leading) {
                                        if isFavourite { Rectangle().fill(favouriteColor).frame(width: 3) }
                                    }

                                    // Playoff-line style cut-off under the second wild card.
                                    if group.wildCardSlots > 0 && index == group.wildCardSlots - 1 && index < group.entries.count - 1 {
                                        Rectangle().fill(Color.amber.opacity(0.7)).frame(height: 1.5)
                                    }
                                }
                            }
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .padding(14)
        }
    }
    
    // Small coloured chip: green for a winning streak, red for losses, orange for overtime losses.
    @ViewBuilder
    private func streakChip(for entry: ComputedStandingEntry) -> some View {
        if let result = entry.streakResult, entry.streakLength > 0 {
            let colour: Color = result == .win ? .green : (result == .loss ? .red : .orange)
            Text(entry.streakText)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(colour)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(colour.opacity(0.16)))
        } else {
            Text("—").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
        }
    }

    private func shiftStandingsDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: fetcher.standingsDate) {
            fetcher.standingsDate = newDate
        }
    }
}
