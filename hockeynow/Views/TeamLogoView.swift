import SwiftUI

// MARK: - Engine
struct TeamLogoView: View {
    let logoURLString: String?
    let teamAbbreviation: String
    var size: CGFloat = 24
    
    private var resolvedLogoURL: URL? {
        let suppliedURL = logoURLString.flatMap(URL.init(string:))
        if suppliedURL != nil { return suppliedURL }
        return URL(string: "https://a.espncdn.com/i/teamlogos/nhl/500/\(teamAbbreviation.lowercased()).png")
    }

    var body: some View {
        if let url = resolvedLogoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                case .failure(_), .empty:
                    fallbackTextCircle
                @unknown default:
                    fallbackTextCircle
                }
            }
        } else {
            fallbackTextCircle
        }
    }
    
    private var fallbackTextCircle: some View {
        ZStack {
            Circle()
                .fill(getNHLTeamColor(abbreviation: teamAbbreviation).opacity(0.18))
            Text(teamAbbreviation.prefix(2))
                .font(.system(size: size * 0.45, weight: .black, design: .monospaced))
                .foregroundColor(getNHLTeamColor(abbreviation: teamAbbreviation))
        }
        .frame(width: size, height: size)
    }
}

