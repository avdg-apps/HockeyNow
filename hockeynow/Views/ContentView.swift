import SwiftUI
import AppKit

// MARK: - View Interface
struct ContentView: View {
    @ObservedObject var fetcher: ESPNNHLFetcher
    @State private var currentLanguage: AppLanguage = .english
    @State private var currentTheme: AppTheme = .system
    @State private var revealSettings: Bool = false
    @State private var settingsSection: SettingsSection = .general
    @State private var activeGameID: String? = nil
    @State private var activeTab: ActiveTabSelection = .games
    @State private var teamSearchText: String = ""
    @State private var debouncedSearchQuery: String = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var cachedSearchResults: [ESPNEvent] = []
    @AppStorage("custom_accent_hex") private var customAccentHex: String = defaultAccentHex
    @State private var minimumLoadingDurationElapsed: Bool = false
    @State private var showSidebar: Bool = false
    @State private var openingGameID: String? = nil
    @StateObject private var network = NetworkMonitor()
    
    private var displayDateString: String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; return formatter.string(from: fetcher.selectedDate)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ContentViewHeader(currentLanguage: currentLanguage, displayDateString: displayDateString, fetcher: fetcher, revealSettings: $revealSettings, activeTab: $activeTab, settingsSection: $settingsSection, showSidebar: $showSidebar, shiftDateAction: shiftDate)
            
            if !minimumLoadingDurationElapsed || !fetcher.hasCompletedInitialLoad {
                EllipsisLoadingView()
                    .task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        minimumLoadingDurationElapsed = true
                    }
            } else if revealSettings {
                SettingsDropdownView(currentLanguage: currentLanguage, fetcher: fetcher, currentLanguageSelection: $currentLanguage, currentThemeSelection: $currentTheme, settingsSection: settingsSection)
                } else if activeTab == .myTeam {
                    MyTeamView(fetcher: fetcher, currentLanguage: currentLanguage)
            } else if activeTab == .picks {
                 PicksFantasyView(fetcher: fetcher)
            } else if activeTab == .standings {
                 LeagueStandingsView(fetcher: fetcher)
                    .frame(height: 480)
            } else if activeTab == .players {
                 PlayersView(fetcher: fetcher, currentLanguage: currentLanguage)
                    .frame(height: 480)
            } else if activeTab == .leaders {
                 LeadersView(fetcher: fetcher)
                    .frame(height: 480)
            } else if activeTab == .playoffs {
                 PlayoffBracketView(fetcher: fetcher)
                    .frame(height: 480)
            } else {
                VStack(spacing: 0) {
                    if let errorMessage = fetcher.lastFetchError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(errorMessage)
                            Spacer()
                            Button("Retry") { fetcher.retryFetch() }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(.secondary)
                        TextField("Search a team playing this year...", text: $teamSearchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .onChange(of: teamSearchText) { _, newValue in
                                searchDebounceTask?.cancel()
                                if newValue.isEmpty {
                                    debouncedSearchQuery = ""
                                    cachedSearchResults = []
                                    return
                                }
                                searchDebounceTask = Task {
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    if Task.isCancelled { return }
                                    await fetcher.loadSeasonIfNeeded(for: fetcher.selectedDate)
                                    if Task.isCancelled { return }
                                    let results = Array(fetcher.gamesForTeamSearch(matching: newValue, referenceDate: fetcher.selectedDate).prefix(60))
                                    debouncedSearchQuery = newValue
                                    cachedSearchResults = results
                                }
                            }
                        if teamSearchText != debouncedSearchQuery && !teamSearchText.isEmpty {
                            ProgressView().controlSize(.small)
                        }
                        if !teamSearchText.isEmpty {
                            Button(action: { teamSearchText = ""; debouncedSearchQuery = ""; cachedSearchResults = [] }) {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                    .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 6)
                    
                    ScrollView {
                        if !debouncedSearchQuery.isEmpty {
                            let searchResults = cachedSearchResults
                            if searchResults.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass").font(.system(size: 42)).foregroundColor(.secondary.opacity(0.4))
                                    Text(fetcher.seasonGames.isEmpty ? "Loading this season's games..." : "No matching team games this year.")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                                }.padding(.top, 120)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(searchResults) { game in
                                        ESPNGameCard(game: game, currentLanguage: currentLanguage, fetcher: fetcher, isOpen: activeGameID == game.id, toggleClick: { toggleGame(game) }, showDate: true)
                                        .overlay(alignment: .topTrailing) {
                                            if openingGameID == game.id { ProgressView().controlSize(.mini).padding(10) }
                                        }
                                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                                    }
                                }.padding(.horizontal, 14).padding(.bottom, 14)
                            }
                        } else {
                            let scopedGames = fetcher.favouriteTeamFirst(fetcher.localFilteredGames)
                            if scopedGames.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 42)).foregroundColor(.secondary.opacity(0.4))
                                    Text(fetcher.isShowingEmptySchedule ? currentLanguage.localize("noGamesScheduled") : currentLanguage.localize("noMatches"))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }.padding(.top, 120)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(scopedGames) { game in
                                        ESPNGameCard(game: game, currentLanguage: currentLanguage, fetcher: fetcher, isOpen: activeGameID == game.id, toggleClick: { toggleGame(game) })
                                        .overlay(alignment: .topTrailing) {
                                            if openingGameID == game.id { ProgressView().controlSize(.mini).padding(10) }
                                        }
                                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                                    }
                                }.padding(.horizontal, 14).padding(.bottom, 14)
                            }
                        }
                    }
                }.frame(height: 480)
            }
            
            Color.white.opacity(0.12).frame(height: 1)
            
            HStack {
                Button(currentLanguage.localize("quit")) { NSApplication.shared.terminate(nil) }.buttonStyle(.bordered).tint(.red)
                Spacer()
                if !network.isOnline {
                    Label("Offline · showing saved games", systemImage: "wifi.slash")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                }
                if let lastUpdated = fetcher.lastUpdated {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text("Updated \(hockeyNowCompactRelativeTime(from: lastUpdated, now: timeline.date))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                Text("Version 2.3.3").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary.opacity(0.7))
            }.padding(12).background(Color.primary.opacity(0.01))
        }
        .overlay(alignment: .leading) {
            if showSidebar {
                SidebarView(isPresented: $showSidebar, activeTab: $activeTab, revealSettings: $revealSettings, settingsSection: $settingsSection, fetcher: fetcher, currentLanguage: currentLanguage)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .frame(width: 560)
        // Keyboard shortcuts: ⌘1-⌘6 switch tabs, ⌘[ and ⌘] move the Games date a day back or forward.
        .background(
            Group {
                Button("") { activeTab = .games }.keyboardShortcut("1", modifiers: .command)
                Button("") { activeTab = .myTeam }.keyboardShortcut("2", modifiers: .command)
                Button("") { activeTab = .standings }.keyboardShortcut("3", modifiers: .command)
                Button("") { activeTab = .players }.keyboardShortcut("4", modifiers: .command)
                Button("") { activeTab = .leaders }.keyboardShortcut("5", modifiers: .command)
                Button("") { activeTab = .playoffs }.keyboardShortcut("6", modifiers: .command)
                Button("") { activeTab = .picks }.keyboardShortcut("7", modifiers: .command)
                Button("") { if activeTab == .games { shiftDate(by: -1) } }.keyboardShortcut("[", modifiers: .command)
                Button("") { if activeTab == .games { shiftDate(by: 1) } }.keyboardShortcut("]", modifiers: .command)
            }
            .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)
        )
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .preferredColorScheme(currentTheme.colorScheme)
        .tint(Color(hex: customAccentHex))
    }
    // A game opens once its details are ready (they are normally loaded already when the day appears), so the card
    // never expands into an empty "loading" panel.
    private func toggleGame(_ game: ESPNEvent) {
        let spring = Animation.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0)
        if activeGameID == game.id { withAnimation(spring) { activeGameID = nil }; return }
        if fetcher.hasDetails(for: game.id) { withAnimation(spring) { activeGameID = game.id }; return }
        openingGameID = game.id
        Task {
            await fetcher.ensureDetails(for: game.id)
            openingGameID = nil
            withAnimation(spring) { activeGameID = game.id }
        }
    }
    private func shiftDate(by days: Int) { if let newDate = Calendar.current.date(byAdding: .day, value: days, to: fetcher.selectedDate) { fetcher.selectedDate = newDate } }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material; let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = material; view.blendingMode = blendingMode; view.state = .active; return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { nsView.material = material; nsView.blendingMode = blendingMode }
}
