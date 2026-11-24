import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications

struct SettingsSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    
    var body: some View {
        HStack {
            Text(label).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.primary)
            Spacer(minLength: 12)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsDropdownView: View {
    let currentLanguage: AppLanguage; @ObservedObject var fetcher: ESPNNHLFetcher
    @Binding var currentLanguageSelection: AppLanguage; @Binding var currentThemeSelection: AppTheme
    let settingsSection: SettingsSection
    @AppStorage("notifications_enabled_toggle") private var systemAlertsActive: Bool = true
    @AppStorage("favorite_team_abbreviation") private var favoriteTeamAbbreviation: String = ""
    @AppStorage("custom_accent_hex") private var customAccentHex: String = defaultAccentHex
    @AppStorage("low_power_mode_enabled") private var lowPowerModeEnabled: Bool = false
    @AppStorage("use_24_hour_time") private var use24HourTime: Bool = false
    @AppStorage("goal_alert_sound_enabled") private var goalAlertSoundEnabled: Bool = true
    @AppStorage("notch_hud_enabled") private var notchHUDEnabled: Bool = true
    @AppStorage("notch_popout_style") private var notchPopoutStyle: String = "small"
    @AppStorage("notch_popout_skip_other_game") private var notchPopoutSkipOtherGame: Bool = false
    @AppStorage("goal_alerts_favourite_only") private var goalAlertsFavouriteOnly: Bool = false
    @AppStorage("game_day_alerts_enabled") private var gameDayAlertsEnabled: Bool = true
    @AppStorage("period_alerts_enabled") private var periodAlertsEnabled: Bool = true
    @State private var savedGamesCleared = false
    @ObservedObject private var notifications = NotificationManager.shared
    @AppStorage("smart_menu_bar_text") private var smartMenuBarText: Bool = false
    @State private var showCopiedAddressFeedback: Bool = false
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    
    private var accentColorBinding: Binding<Color> {
        Binding(get: { Color(hex: customAccentHex) }, set: { customAccentHex = $0.hexString })
    }
    
    @AppStorage("extra_favorite_teams") private var extraFavouriteTeamsRaw: String = ""
    
    private var extraFavouriteList: [String] {
        extraFavouriteTeamsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }
    
    private func toggleExtraFavourite(_ abbreviation: String) {
        var list = extraFavouriteList
        if let index = list.firstIndex(of: abbreviation) { list.remove(at: index) } else { list.append(abbreviation) }
        extraFavouriteTeamsRaw = list.sorted().joined(separator: ",")
    }
    
    private var favoriteTeamBinding: Binding<String> {
        Binding(
            get: { favoriteTeamAbbreviation },
            set: { newValue in
                favoriteTeamAbbreviation = newValue
                if let homeColorHex = nhlTeamHomeColorHex[newValue] {
                    customAccentHex = homeColorHex
                }
            }
        )
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 12) {
            if settingsSection == .general {
                SettingsRow(label: currentLanguage.localize("appearance")) {
                    Picker("", selection: $currentThemeSelection) {
                        Text("System").tag(AppTheme.system)
                        Text("Light").tag(AppTheme.light)
                        Text("Dark").tag(AppTheme.dark)
                    }.pickerStyle(.menu).labelsHidden().frame(width: 160)
                }
                
                SettingsRow(label: currentLanguage.localize("language")) {
                    Picker("", selection: $currentLanguageSelection) {
                        ForEach(AppLanguage.allCases) { lang in Text(lang.displayName).tag(lang) }
                    }.pickerStyle(.menu).labelsHidden().frame(width: 160)
                }
                
                SettingsRow(label: currentLanguage.localize("timezone")) {
                    Picker("", selection: $fetcher.targetZone) {
                        ForEach(TimeZoneOption.allOptions) { option in Text(option.label).tag(option.zone) }
                    }.pickerStyle(.menu).labelsHidden().frame(width: 160)
                }
                
                SettingsRow(label: currentLanguage.localize("launchAtLogin")) {
                    Toggle("", isOn: launchAtLoginBinding).toggleStyle(.switch).labelsHidden()
                }
                
                SettingsRow(label: currentLanguage.localize("twentyFourHour")) {
                    Toggle("", isOn: $use24HourTime).toggleStyle(.switch).labelsHidden()
                }
                
                SettingsRow(label: currentLanguage.localize("hideDockIcon")) {
                    Toggle("", isOn: showDockIconBinding).toggleStyle(.switch).labelsHidden()
                }
                
                SettingsRow(label: currentLanguage.localize("automaticUpdates")) {
                    Toggle("", isOn: automaticUpdatesBinding).toggleStyle(.switch).labelsHidden()
                }
                
                HStack(spacing: 6) {
                    Button(role: .destructive) {
                        fetcher.clearSavedGameData()
                        savedGamesCleared = true
                    } label: {
                        Label(savedGamesCleared ? "Saved games cleared" : "Clear saved games", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                    Text("Box scores and past schedules kept on this Mac for faster launches.")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary.opacity(0.8))
                }.padding(.top, 4)
                
                HStack(spacing: 14) {
                    Button(action: openBugReportEmail) {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope").font(.system(size: 11))
                            Text(currentLanguage.localize("contactDeveloper")).font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                    }.buttonStyle(.plain).foregroundColor(.secondary)
                    
                    Button(action: { updaterViewModel.checkForUpdates() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                            Text(currentLanguage.localize("checkForUpdates")).font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                    }.buttonStyle(.plain).foregroundColor(.secondary)
                        .disabled(!updaterViewModel.canCheckForUpdates)
                        .opacity(updaterViewModel.canCheckForUpdates ? 1 : 0.4)
                }.padding(.top, 4)
                
                if showCopiedAddressFeedback {
                    Text(currentLanguage.localize("copiedAddress"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            } else {
                SettingsRow(label: currentLanguage.localize("menuStyle")) {
                    Picker("", selection: $fetcher.menuDisplayMode) {
                        Text(currentLanguage.localize("menuFull")).tag(MenuDisplayMode.full)
                        Text(currentLanguage.localize("menuIcon")).tag(MenuDisplayMode.short)
                        Text("Icon only").tag(MenuDisplayMode.iconOnly)
                    }.pickerStyle(.menu).labelsHidden().frame(width: 160)
                }

                SettingsRow(label: "Refresh games") {
                    Picker("", selection: $fetcher.refreshInterval) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }.pickerStyle(.menu).labelsHidden().frame(width: 160)
                }
                
                SettingsRow(label: currentLanguage.localize("notiLabel")) {
                    Toggle("", isOn: $systemAlertsActive).toggleStyle(.switch).labelsHidden()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 14) {
                        Button { notifications.sendTest() } label: {
                            Label("Send test notification", systemImage: "bell.badge")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }.buttonStyle(.plain).foregroundColor(.secondary)
                        if notifications.status == .denied {
                            Button { notifications.openSystemSettings() } label: {
                                Label("Open System Settings", systemImage: "gearshape")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }.buttonStyle(.plain).foregroundColor(.blue)
                        }
                    }
                    Text({
                        switch notifications.status {
                        case .denied: return "Blocked: turn on HockeyNow in System Settings → Notifications."
                        case .notDetermined: return "macOS hasn't been asked for permission yet. Send a test to trigger the prompt."
                        default: return "macOS notifications are allowed for HockeyNow."
                        }
                    }())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .task { await notifications.refreshStatus() }
                
                VStack(alignment: .leading, spacing: 3) {
                    SettingsRow(label: "Goal alerts: my team only") {
                        Toggle("", isOn: $goalAlertsFavouriteOnly).toggleStyle(.switch).labelsHidden()
                    }
                    Text("Off: an alert for every live game. On: only your favourite team's goals.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    SettingsRow(label: "Period & final alerts") {
                        Toggle("", isOn: $periodAlertsEnabled).toggleStyle(.switch).labelsHidden()
                    }
                    Text("End of each period, overtime or shootout starting, and the final score, for your teams.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    SettingsRow(label: "Game-day alerts") {
                        Toggle("", isOn: $gameDayAlertsEnabled).toggleStyle(.switch).labelsHidden()
                    }
                    Text("A morning alert when your team plays, and a puck-drop reminder 15 minutes before.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                AlertProfilesView()
                
                VStack(alignment: .leading, spacing: 3) {
                    SettingsRow(label: "Smart menu bar text") {
                        Toggle("", isOn: $smartMenuBarText).toggleStyle(.switch).labelsHidden()
                    }
                    Text("Shows your team's score while it plays, and its next game otherwise. A pinned game still wins.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                SettingsRow(label: currentLanguage.localize("favoriteTeam")) {
                    Picker("", selection: favoriteTeamBinding) {
                        Text(currentLanguage.localize("favoriteTeamNone")).tag("")
                        ForEach(nhlAllTeams, id: \.abbreviation) { team in
                            Text(team.name).tag(team.abbreviation)
                        }
                    }.pickerStyle(.menu).labelsHidden().frame(width: 160)
                }
                
                SettingsRow(label: "Also follow") {
                    Menu {
                        ForEach(nhlAllTeams.filter { $0.abbreviation != favoriteTeamAbbreviation }, id: \.abbreviation) { team in
                            Button {
                                toggleExtraFavourite(team.abbreviation)
                            } label: {
                                if extraFavouriteList.contains(team.abbreviation) {
                                    Label(team.name, systemImage: "checkmark")
                                } else {
                                    Text(team.name)
                                }
                            }
                        }
                    } label: {
                        Text(extraFavouriteList.isEmpty ? "None" : extraFavouriteList.joined(separator: ", "))
                            .lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 160)
                }
                
                SettingsRow(label: currentLanguage.localize("advancedTheme")) {
                    ColorPicker("", selection: accentColorBinding, supportsOpacity: false).labelsHidden()
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    SettingsRow(label: currentLanguage.localize("lowPowerMode")) {
                        Toggle("", isOn: $lowPowerModeEnabled).toggleStyle(.switch).labelsHidden()
                    }
                    Text(currentLanguage.localize("lowPowerModeHint"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                SettingsRow(label: currentLanguage.localize("goalAlertSound")) {
                    Toggle("", isOn: $goalAlertSoundEnabled).toggleStyle(.switch).labelsHidden()
                }
                
                SettingsRow(label: currentLanguage.localize("disableNotchHUD")) {
                    Toggle("", isOn: $notchHUDEnabled).toggleStyle(.switch).labelsHidden()
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    SettingsRow(label: "Notch live alerts") {
                        Picker("", selection: $notchPopoutStyle) {
                            Text("Don't drop down").tag("off")
                            Text("Small banner").tag("small")
                            Text("Full notch").tag("full")
                        }.pickerStyle(.menu).labelsHidden().frame(width: 160)
                    }
                    Text("What the notch does on a goal, penalty or period end in your team's game.")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    SettingsRow(label: "Skip if another game is shown") {
                        Toggle("", isOn: $notchPopoutSkipOtherGame).toggleStyle(.switch).labelsHidden()
                    }
                    Text("No live alert when the notch is showing a different game from the one the alert is for.")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.primary.opacity(0.03))
        .frame(height: 480, alignment: .top)
    }
    
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    print("Failed to \(newValue ? "register" : "unregister") login item: \(error)")
                }
            }
        )
    }
    
    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { NSApp.activationPolicy() == .regular },
            set: { newValue in
                UserDefaults.standard.set(newValue, forKey: "hide_dock_icon_enabled")
                DispatchQueue.main.async {
                    NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                }
            }
        )
    }
    
    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updaterViewModel.automaticallyChecksForUpdates },
            set: { updaterViewModel.automaticallyChecksForUpdates = $0 }
        )
    }
    
    private func openBugReportEmail() {
        let subject = "HockeyNow Bug Report"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        if let url = URL(string: "mailto:avdgapps@gmail.com?subject=\(encodedSubject)"), NSWorkspace.shared.open(url) {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("avdgapps@gmail.com", forType: .string)
        withAnimation { showCopiedAddressFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showCopiedAddressFeedback = false }
        }
    }
}
