import SwiftUI

// MARK: - Per-team alert profiles (Settings)
struct AlertProfilesView: View {
    @AppStorage("favorite_team_abbreviation") private var primary = ""
    @AppStorage("extra_favorite_teams") private var extras = ""
    @AppStorage("notch_popouts_enabled") private var popoutsEnabled = true
    @State private var profiles: [String: TeamAlertProfile] = AlertProfiles.all()

    private var teams: [String] { hockeyNowFavouriteTeams() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(label: "Notch pop-outs") {
                Toggle("", isOn: $popoutsEnabled).toggleStyle(.switch).labelsHidden()
            }
            Text("The notch opens by itself for a few seconds on goals, penalties and period ends in your teams' games.")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)

            Text("ALERTS PER TEAM").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.secondary).padding(.top, 4)
            if teams.isEmpty {
                Text("Choose a favourite team to set its alerts.").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
            ForEach(teams, id: \.self) { team in
                teamCard(team)
            }
        }
        .onChange(of: primary) { _, _ in profiles = AlertProfiles.all() }
        .onChange(of: extras) { _, _ in profiles = AlertProfiles.all() }
    }

    private func binding(_ team: String, _ kind: AlertKind) -> Binding<Bool> {
        Binding(get: { (profiles[team] ?? TeamAlertProfile()).allowsIgnoringMute(kind) },
                set: { value in
                    var profile = profiles[team] ?? TeamAlertProfile()
                    profile.set(kind, value)
                    profiles[team] = profile
                    AlertProfiles.save(profile, for: team)
                })
    }

    private func muteBinding(_ team: String) -> Binding<Bool> {
        Binding(get: { profiles[team]?.muted ?? false },
                set: { value in
                    var profile = profiles[team] ?? TeamAlertProfile()
                    profile.muted = value
                    profiles[team] = profile
                    AlertProfiles.save(profile, for: team)
                })
    }

    private func teamCard(_ team: String) -> some View {
        let muted = profiles[team]?.muted ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(team).font(.system(size: 12, weight: .black, design: .monospaced))
                Spacer()
                Text("Mute").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                Toggle("", isOn: muteBinding(team)).toggleStyle(.switch).labelsHidden().controlSize(.mini)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 4) {
                ForEach(AlertKind.allCases.filter { $0 != .popouts }) { kind in
                    Toggle(kind.label, isOn: binding(team, kind)).toggleStyle(.checkbox)
                        .font(.system(size: 10, design: .monospaced))
                }
                Toggle("Notch", isOn: binding(team, .popouts)).toggleStyle(.checkbox).font(.system(size: 10, design: .monospaced))
            }
            .disabled(muted)
            .opacity(muted ? 0.4 : 1)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension TeamAlertProfile {
    // The stored value of one switch, regardless of whether the team is muted (muting only overrides it).
    func allowsIgnoringMute(_ kind: AlertKind) -> Bool {
        var copy = self
        copy.muted = false
        return copy.allows(kind)
    }
}
