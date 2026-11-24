import SwiftUI
import Foundation

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { self.rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }
}

enum MenuDisplayMode: String, CaseIterable, Identifiable {
    case full, short, iconOnly
    var id: String { self.rawValue }
}

enum RefreshInterval: Int, CaseIterable, Identifiable {
    case automatic = 0
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .fifteenSeconds: return "15 seconds"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        }
    }
}

enum ActiveTabSelection: String, CaseIterable, Identifiable {
    case games, myTeam, picks, standings, players, leaders, playoffs
    var id: String { self.rawValue }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, advanced
    var id: String { self.rawValue }
}

struct TimeZoneOption: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let zone: TimeZone

    static let allOptions: [TimeZoneOption] = [
        TimeZoneOption(label: "📌 Local System Time", zone: .current),
        TimeZoneOption(label: "Hawaii (HST / GMT -10:00)", zone: TimeZone(identifier: "Pacific/Honolulu") ?? .current),
        TimeZoneOption(label: "Alaska (AKST / GMT-09)", zone: TimeZone(identifier: "America/Anchorage") ?? .current),
        TimeZoneOption(label: "Pacific Time (PST / GMT-08)", zone: TimeZone(identifier: "America/Los_Angeles") ?? .current),
        TimeZoneOption(label: "Mountain Time (MST / GMT-07)", zone: TimeZone(identifier: "America/Denver") ?? .current),
        TimeZoneOption(label: "Central Time (CST / GMT-06)", zone: TimeZone(identifier: "America/Chicago") ?? .current),
        TimeZoneOption(label: "Eastern Time (EST / GMT-05)", zone: TimeZone(identifier: "America/New_York") ?? .current),
        TimeZoneOption(label: "Atlantic Time (AST / GMT-04)", zone: TimeZone(identifier: "America/Halifax") ?? .current),
        TimeZoneOption(label: "Newfoundland (NST / GMT-03:30)", zone: TimeZone(identifier: "America/St_Johns") ?? .current),
        TimeZoneOption(label: "London / Dublin (GMT+00)", zone: TimeZone(identifier: "Europe/London") ?? .current),
        TimeZoneOption(label: "Paris / Berlin / Rome (GMT+01)", zone: TimeZone(identifier: "Europe/Paris") ?? .current),
        TimeZoneOption(label: "Helsinki / Riga / Kyiv (GMT+02)", zone: TimeZone(identifier: "Europe/Helsinki") ?? .current),
        TimeZoneOption(label: "Dubai / Moscow (GMT+04)", zone: TimeZone(identifier: "Asia/Dubai") ?? .current),
        TimeZoneOption(label: "Singapore / Beijing (GMT+08)", zone: TimeZone(identifier: "Asia/Singapore") ?? .current),
        TimeZoneOption(label: "Tokyo / Seoul (GMT+09)", zone: TimeZone(identifier: "Asia/Tokyo") ?? .current),
        TimeZoneOption(label: "Sydney / Melbourne (GMT+10)", zone: TimeZone(identifier: "Australia/Sydney") ?? .current)
    ]
}
