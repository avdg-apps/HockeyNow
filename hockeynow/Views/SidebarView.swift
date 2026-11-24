import SwiftUI

struct SidebarView: View {
    @Binding var isPresented: Bool
    @Binding var activeTab: ActiveTabSelection
    @Binding var revealSettings: Bool
    @Binding var settingsSection: SettingsSection

    let fetcher: ESPNNHLFetcher
    let currentLanguage: AppLanguage

    private let sidebarCornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sidebarHeader

            navigationGroup(
                title: "SCORES",
                items: [
                    ("calendar", "Games", .games),
                    ("trophy.fill", "Playoffs", .playoffs)
                ]
            )

            navigationGroup(
                title: "MY HOCKEY",
                items: [("heart.fill", "My Team", .myTeam), ("checkmark.seal.fill", "Picks & Fantasy", .picks)]
            )

            navigationGroup(
                title: "STATISTICS",
                items: [
                    ("list.number", "Standings", .standings),
                    ("figure.hockey", "Players", .players),
                    ("star.circle.fill", "Leaders", .leaders)
                ]
            )

            settingsGroup

            Spacer()

            Text("Version 2.3.1")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 220, height: 480, alignment: .top)
        .background(sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, x: 5, y: 4)
        .padding(.leading, 8)
    }

    private var sidebarHeader: some View {
        HStack {
            Text("HOCKEYNOW")
                .font(.system(size: 15, weight: .black, design: .monospaced))

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    private var settingsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupTitle("APP")

            Button {
                openSettings(.general)
            } label: {
                settingsRow("gearshape.fill", "General Settings", isSelected: revealSettings && settingsSection == .general)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Button {
                openSettings(.advanced)
            } label: {
                settingsRow("slider.horizontal.3", "Advanced Settings", isSelected: revealSettings && settingsSection == .advanced)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    private func navigationGroup(
        title: String,
        items: [(String, String, ActiveTabSelection)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            groupTitle(title)

            ForEach(items, id: \.1) { item in
                Button {
                    activeTab = item.2
                    revealSettings = false
                    closeSidebar()
                } label: {
                    navigationRow(
                        iconName: item.0,
                        title: item.1,
                        isSelected: activeTab == item.2 && !revealSettings
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
    }

    private func navigationRow(iconName: String, title: String, isSelected: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: iconName)
                .frame(width: 17)

            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .monospaced))

            Spacer()
        }
        .foregroundColor(isSelected ? .accentColor : .primary)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func settingsRow(_ iconName: String, _ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: iconName)
                .frame(width: 17)
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            Spacer()
        }
        .foregroundColor(isSelected ? .accentColor : .primary)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var sidebarBackground: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            .overlay(Color.primary.opacity(0.035))
    }

    private func openSettings(_ section: SettingsSection) {
        settingsSection = section
        revealSettings = true
        closeSidebar()
    }

    private func closeSidebar() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isPresented = false
        }
    }
}
