import SwiftUI
import AppKit

let nhlAllTeams: [(abbreviation: String, name: String)] = [
    ("ANA", "Anaheim Ducks"), ("BOS", "Boston Bruins"), ("BUF", "Buffalo Sabres"), ("CAR", "Carolina Hurricanes"),
    ("CBJ", "Columbus Blue Jackets"), ("CGY", "Calgary Flames"), ("CHI", "Chicago Blackhawks"), ("COL", "Colorado Avalanche"),
    ("DAL", "Dallas Stars"), ("DET", "Detroit Red Wings"), ("EDM", "Edmonton Oilers"), ("FLA", "Florida Panthers"),
    ("LAK", "Los Angeles Kings"), ("MIN", "Minnesota Wild"), ("MTL", "Montreal Canadiens"), ("NJD", "New Jersey Devils"),
    ("NSH", "Nashville Predators"), ("NYI", "New York Islanders"), ("NYR", "New York Rangers"), ("OTT", "Ottawa Senators"),
    ("PHI", "Philadelphia Flyers"), ("PIT", "Pittsburgh Penguins"), ("SEA", "Seattle Kraken"), ("SJS", "San Jose Sharks"),
    ("STL", "St. Louis Blues"), ("TBL", "Tampa Bay Lightning"), ("TOR", "Toronto Maple Leafs"), ("UTA", "Utah Hockey Club"),
    ("VAN", "Vancouver Canucks"), ("VGK", "Vegas Golden Knights"), ("WPG", "Winnipeg Jets"), ("WSH", "Washington Capitals")
]

let nhlTeamHomeColorHex: [String: String] = [
    "ANA": "F47A38", "BOS": "FFB81C", "BUF": "002654", "CAR": "CC0000",
    "CBJ": "041E42", "CGY": "C8102E", "CHI": "CF0A2C", "COL": "6F263D",
    "DAL": "006847", "DET": "CE1126", "EDM": "FF4C00", "FLA": "C8102E",
    "LAK": "111111", "MIN": "154734", "MTL": "AF1E2D", "NJD": "CE1126",
    "NSH": "FFB81C", "NYI": "00539B", "NYR": "0038A8", "OTT": "C52032",
    "PHI": "F74902", "PIT": "FCB514", "SEA": "001628", "SJS": "006D75",
    "STL": "002F87", "TBL": "002868", "TOR": "00205B", "UTA": "71AFE5",
    "VAN": "00205B", "VGK": "B4975A", "WPG": "041E42", "WSH": "C8102E"
]

func getNHLTeamColor(abbreviation: String) -> Color {
    let team = abbreviation.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let colorMap: [String: Color] = [
        "ANA": Color(red: 0.91, green: 0.29, blue: 0.15),
        "BOS": Color(red: 0.99, green: 0.76, blue: 0.04),
        "BUF": Color(red: 0.00, green: 0.15, blue: 0.42),
        "CAR": Color(red: 0.89, green: 0.07, blue: 0.19),
        "CBJ": Color(red: 0.00, green: 0.15, blue: 0.36),
        "CGY": Color(red: 0.85, green: 0.12, blue: 0.16),
        "CHI": Color(red: 0.84, green: 0.07, blue: 0.17),
        "COL": Color(red: 0.43, green: 0.11, blue: 0.23),
        "DAL": Color(red: 0.00, green: 0.53, blue: 0.24),
        "DET": Color(red: 0.89, green: 0.04, blue: 0.17),
        "EDM": Color(red: 0.94, green: 0.34, blue: 0.12),
        "FLA": Color(red: 0.02, green: 0.15, blue: 0.31),
        "LAK": Color(red: 0.44, green: 0.45, blue: 0.46),
        "MIN": Color(red: 0.08, green: 0.32, blue: 0.21),
        "MTL": Color(red: 0.69, green: 0.11, blue: 0.16),
        "NJD": Color(red: 0.87, green: 0.08, blue: 0.15),
        "NSH": Color(red: 0.99, green: 0.74, blue: 0.04),
        "NYI": Color(red: 0.00, green: 0.33, blue: 0.65),
        "NYR": Color(red: 0.01, green: 0.24, blue: 0.61),
        "OTT": Color(red: 0.87, green: 0.09, blue: 0.16),
        "PHI": Color(red: 0.96, green: 0.41, blue: 0.11),
        "PIT": Color(red: 0.79, green: 0.65, blue: 0.36),
        "SEA": Color(red: 0.58, green: 0.79, blue: 0.80),
        "SJS": Color(red: 0.00, green: 0.42, blue: 0.47),
        "STL": Color(red: 0.00, green: 0.18, blue: 0.55),
        "TBL": Color(red: 0.00, green: 0.16, blue: 0.44),
        "TOR": Color(red: 0.00, green: 0.15, blue: 0.43),
        "UTA": Color(red: 0.41, green: 0.73, blue: 0.89),
        "VAN": Color(red: 0.00, green: 0.12, blue: 0.27),
        "VGK": Color(red: 0.70, green: 0.57, blue: 0.33),
        "WPG": Color(red: 0.02, green: 0.16, blue: 0.30),
        "WSH": Color(red: 0.02, green: 0.07, blue: 0.20)
    ]
    return colorMap[team] ?? Color.green
}

let nhlTeamAwayColorHex: [String: String] = [
    "ANA": "B9975B", "BOS": "9EA2A2", "BUF": "FFB81C", "CAR": "A2AAAD",
    "CBJ": "C8102E", "CGY": "F1BE48", "CHI": "FF671B", "COL": "236192",
    "DAL": "A2AAAD", "DET": "A2AAAD", "EDM": "0057B8", "FLA": "C8102E",
    "LAK": "C9CCCE", "MIN": "A6192E", "MTL": "2B6CC4", "NJD": "8A8D8F",
    "NSH": "3A5A9B", "NYI": "F47D30", "NYR": "CE1126", "OTT": "B79257",
    "PHI": "8A8D8F", "PIT": "A2AAAD", "SEA": "E9072B", "SJS": "EA7200",
    "STL": "FCB514", "TBL": "A2AAAD", "TOR": "A2AAAD", "UTA": "B0B7BC",
    "VAN": "00843D", "VGK": "A2AAAD", "WPG": "4F81C7", "WSH": "C8102E"
]

func getNHLTeamAwayColor(abbreviation: String) -> Color {
    guard let hex = nhlTeamAwayColorHex[abbreviation.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)] else {
        return getNHLTeamColor(abbreviation: abbreviation)
    }
    return Color(hex: hex)
}

private func rgbComponents(_ color: Color) -> (r: Double, g: Double, b: Double) {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color).usingColorSpace(.deviceRGB)
    return (Double(ns?.redComponent ?? 0), Double(ns?.greenComponent ?? 0), Double(ns?.blueComponent ?? 0))
}

func colorBrightness(_ color: Color) -> Double {
    let c = rgbComponents(color)
    return c.r * 0.299 + c.g * 0.587 + c.b * 0.114
}

func colorsAreSimilar(_ a: Color, _ b: Color, threshold: Double = 0.30) -> Bool {
    let x = rgbComponents(a), y = rgbComponents(b)
    let distance = ((x.r - y.r) * (x.r - y.r) + (x.g - y.g) * (x.g - y.g) + (x.b - y.b) * (x.b - y.b)).squareRoot()
    return distance < threshold
}

func getGameTeamColor(abbreviation: String, isHome: Bool, opponent: String) -> Color {
    let own = getNHLTeamColor(abbreviation: abbreviation)
    if isHome { return own }
    return colorsAreSimilar(own, getNHLTeamColor(abbreviation: opponent)) ? getNHLTeamAwayColor(abbreviation: abbreviation) : own
}

func getReadableFavouriteTeamColor(abbreviation: String, theme: AppTheme, colorScheme: ColorScheme? = nil) -> Color {
    let isDark = colorScheme.map { $0 == .dark } ?? (theme == .dark)
    let home = getNHLTeamColor(abbreviation: abbreviation)
    guard isDark else {
        return colorBrightness(home) > 0.72 ? Color(red: 0.08, green: 0.08, blue: 0.08) : home
    }
    let away = getNHLTeamAwayColor(abbreviation: abbreviation)
    let chosen = colorBrightness(away) > colorBrightness(home) ? away : home
    return colorBrightness(chosen) < 0.30 ? .white : chosen
}
