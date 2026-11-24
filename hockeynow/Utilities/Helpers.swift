import Foundation
import UserNotifications

func hockeyNowTimeFormat() -> String {
    UserDefaults.standard.bool(forKey: "use_24_hour_time") ? "HH:mm" : "h:mm a"
}

func hockeyNowNotificationSound() -> UNNotificationSound? {
    UserDefaults.standard.object(forKey: "goal_alert_sound_enabled") == nil
        || UserDefaults.standard.bool(forKey: "goal_alert_sound_enabled")
        ? .default : nil
}

func hockeyNowCompactRelativeTime(from date: Date, now: Date = Date()) -> String {
    let secondsAgo = max(0, Int(now.timeIntervalSince(date)))
    if secondsAgo < 60 { return "\(secondsAgo)s" }
    let minutesAgo = secondsAgo / 60
    if minutesAgo < 60 { return "\(minutesAgo)m" }
    let hoursAgo = minutesAgo / 60
    if hoursAgo < 24 { return "\(hoursAgo)h" }
    return "\(hoursAgo / 24)d"
}

func hockeyNowBool(_ key: String, default defaultValue: Bool) -> Bool {
    UserDefaults.standard.object(forKey: key) == nil ? defaultValue : UserDefaults.standard.bool(forKey: key)
}

func hockeyNowDayWord(for date: Date, zone: TimeZone, now: Date = Date()) -> String {
    var calendar = Calendar.current
    calendar.timeZone = zone
    if calendar.isDate(date, inSameDayAs: now) {
        return calendar.component(.hour, from: date) >= 17 ? "tonight" : "today"
    }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
        return "tomorrow"
    }
    return HockeyNowFormatterCache.formatter(format: "EEE MMM d", zone: zone).string(from: date)
}

enum HockeyNowFormatterCache {
    private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()
    static func formatter(format: String, zone: TimeZone) -> DateFormatter {
        let key = "\(format)|\(zone.identifier)"
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let made = DateFormatter()
        made.locale = Locale.current
        made.timeZone = zone
        made.dateFormat = format
        cache[key] = made
        return made
    }
}

func hockeyNowClockString(for date: Date, zone: TimeZone) -> String {
    HockeyNowFormatterCache.formatter(format: hockeyNowTimeFormat(), zone: zone).string(from: date)
}

func hockeyNowCountdownText(until date: Date, now: Date = Date()) -> String {
    let seconds = Int(date.timeIntervalSince(now))
    if seconds <= 0 { return "Starting now" }
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(max(minutes, 1))m"
}

func hockeyNowExtraFavouriteTeams() -> [String] {
    (UserDefaults.standard.string(forKey: "extra_favorite_teams") ?? "")
        .split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
}

func hockeyNowFavouriteTeams() -> [String] {
    var teams: [String] = []
    let primary = UserDefaults.standard.string(forKey: "favorite_team_abbreviation") ?? ""
    if !primary.isEmpty { teams.append(primary) }
    for extra in hockeyNowExtraFavouriteTeams() where !teams.contains(extra) { teams.append(extra) }
    return teams
}
