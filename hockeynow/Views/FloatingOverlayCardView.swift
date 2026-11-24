import SwiftUI

// MARK: - Overlay
struct FloatingOverlayCardView: View {
    let gameID: String
    @ObservedObject var fetcher: ESPNNHLFetcher
    let closeAction: () -> Void
    
    private var liveGame: ESPNEvent? { fetcher.rawFetchedGames.first(where: { $0.id == gameID }) }
    
    var body: some View {
        if let current = liveGame, let away = current.awayTeam, let home = current.homeTeam {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            TeamLogoView(logoURLString: away.team.logo, teamAbbreviation: away.team.threeLetterAbbreviation, size: 18)
                            Text(away.team.threeLetterAbbreviation).font(.system(size: 14, weight: .black, design: .monospaced))
                            Spacer()
                            Text(away.score).font(.system(size: 16, weight: .black, design: .monospaced))
                        }
                        HStack {
                            TeamLogoView(logoURLString: home.team.logo, teamAbbreviation: home.team.threeLetterAbbreviation, size: 18)
                            Text(home.team.threeLetterAbbreviation).font(.system(size: 14, weight: .black, design: .monospaced))
                            Spacer()
                            Text(home.score).font(.system(size: 16, weight: .black, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider().background(Color.primary.opacity(0.2))
                    
                    VStack(spacing: 2) {
                        Text({
                            if current.status.type.state == "in" {
                                return current.status.displayClock ?? "20:00"
                            }
                            return current.abstractState.uppercased()
                        }())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(current.abstractState == "Live" ? .red : .primary)
                        
                        if current.abstractState == "Live" {
                            Text("P\(current.status.period ?? 1)")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(.amber)
                        }
                    }
                    .frame(width: 60)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundColor(.primary)
                
                Button(action: closeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
            .frame(minWidth: 240, minHeight: 70)
        } else {
            Text("Syncing Panel...")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}
