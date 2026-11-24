import SwiftUI

// MARK: - Header
struct ContentViewHeader: View {
    let currentLanguage: AppLanguage; let displayDateString: String; @ObservedObject var fetcher: ESPNNHLFetcher
    @Binding var revealSettings: Bool; @Binding var activeTab: ActiveTabSelection; @Binding var settingsSection: SettingsSection; @Binding var showSidebar: Bool
    @State private var showCalendarPopover = false; let shiftDateAction: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 15, weight: .bold))
                        .padding(6)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(currentLanguage.localize("title"))
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                    Text(currentLanguage.localize("sub"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                HStack(spacing: 8) {
                        Button(action: { shiftDateAction(-1) }) {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).padding(6).background(Color.primary.opacity(0.06)).cornerRadius(6)
                        }.buttonStyle(.plain)
                        Button(action: { showCalendarPopover.toggle() }) {
                            Text(displayDateString).font(.system(size: 13, weight: .bold, design: .monospaced)).frame(width: 100, alignment: .center)
                        }.buttonStyle(.plain)
                        Button(action: { shiftDateAction(1) }) {
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).padding(6).background(Color.primary.opacity(0.06)).cornerRadius(6)
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, 10)
                    
                    HStack(spacing: 10) {
                        if !fetcher.localFilteredGames.isEmpty {
                            Button(action: { fetcher.cycleTicker() }) {
                                Image(systemName: "arrow.up.and.down.square.fill").font(.system(size: 14)).foregroundColor(.primary.opacity(0.8))
                            }.buttonStyle(.plain)
                        }
                        Button(action: { showCalendarPopover.toggle() }) {
                            Image(systemName: "calendar").font(.system(size: 15)).foregroundColor(.primary.opacity(0.8))
                        }.buttonStyle(.plain)
                        .popover(isPresented: $showCalendarPopover, arrowEdge: .bottom) {
                            EnlargedCalendarPicker(selection: $fetcher.selectedDate)
                        }
                        Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { revealSettings = true } }) {
                            Image(systemName: "gearshape.fill").font(.system(size: 15)).foregroundColor(.primary)
                        }.buttonStyle(.plain)
                        
                        if fetcher.isLoading { ProgressView().controlSize(.small) }
                        else {
                            Button(action: { fetcher.runCleanFetch() }) { Image(systemName: "arrow.clockwise").font(.system(size: 15)) }.buttonStyle(.plain)
                        }
                        if let lastUpdated = fetcher.lastUpdated {
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                Text("Updated \(hockeyNowCompactRelativeTime(from: lastUpdated, now: timeline.date))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
            }

        }
    
        .padding(.horizontal, 18).padding(.vertical, 14)
    }
}
