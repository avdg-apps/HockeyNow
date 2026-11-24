import WidgetKit
import SwiftUI
import AppIntents

// HockeyNow widget: next game and standings for one team. It talks to the NHL's public API itself, so it needs no App Group
// (which a free Apple ID can't use). See README.md in this folder for the Xcode steps.

struct TeamChoiceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Team"
    static let description = IntentDescription("Which team the widget follows.")
    @Parameter(title: "Team (abbreviation, e.g. TOR)", default: "TOR") var team: String
}

struct WidgetData {
    var team: String
    var opponent: String?
    var isHome = true
    var start: Date?
    var record = ""
    var points = 0
    var divisionRank = 0
    var divisionName = ""
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, data: WidgetData(team: "TOR", opponent: "MTL", start: .now.addingTimeInterval(7200), record: "5-2-1", points: 11, divisionRank: 2, divisionName: "Atlantic")) }
    func snapshot(for configuration: TeamChoiceIntent, in context: Context) async -> Entry { await load(configuration.team) }
    func timeline(for configuration: TeamChoiceIntent, in context: Context) async -> Timeline<Entry> {
        let entry = await load(configuration.team)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(20 * 60)))
    }

    private func json(_ path: String) async -> [String: Any]? {
        guard let url = URL(string: "https://api-web.nhle.com/v1/\(path)"), let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func load(_ teamText: String) async -> Entry {
        let team = teamText.trimmingCharacters(in: .whitespaces).uppercased()
        var data = WidgetData(team: team)
        let plain = ISO8601DateFormatter()
        if let schedule = await json("club-schedule-season/\(team)/now"), let games = schedule["games"] as? [[String: Any]] {
            for game in games {
                guard let text = game["startTimeUTC"] as? String, let start = plain.date(from: text), start > .now.addingTimeInterval(-3 * 3600) else { continue }
                let state = (game["gameState"] as? String) ?? "FUT"
                if state == "FINAL" || state == "OFF" { continue }
                let away = ((game["awayTeam"] as? [String: Any])?["abbrev"] as? String) ?? ""
                let home = ((game["homeTeam"] as? [String: Any])?["abbrev"] as? String) ?? ""
                data.isHome = home == team
                data.opponent = data.isHome ? away : home
                data.start = start
                break
            }
        }
        if let standings = await json("standings/now"), let rows = standings["standings"] as? [[String: Any]] {
            let division = rows.first { (($0["teamAbbrev"] as? [String: Any])?["default"] as? String) == team }?["divisionName"] as? String
            var rank = 0
            for row in rows where (row["divisionName"] as? String) == division {
                rank += 1       // the feed is already league-ordered; counting within the division gives the division place
                if (((row["teamAbbrev"] as? [String: Any])?["default"] as? String) == team) {
                    let w = row["wins"] as? Int ?? 0, l = row["losses"] as? Int ?? 0, o = row["otLosses"] as? Int ?? 0
                    data.record = "\(w)-\(l)-\(o)"; data.points = row["points"] as? Int ?? 0
                    data.divisionRank = rank; data.divisionName = division ?? ""
                }
            }
        }
        return Entry(date: .now, data: data)
    }
}

struct Entry: TimelineEntry { let date: Date; let data: WidgetData }

struct HockeyNowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        let d = entry.data
        VStack(alignment: .leading, spacing: 4) {
            Text(d.team).font(.system(size: 13, weight: .black, design: .monospaced)).foregroundStyle(.secondary)
            if let opponent = d.opponent, let start = d.start {
                Text("\(d.isHome ? "vs" : "@") \(opponent)").font(.system(size: 22, weight: .black, design: .monospaced))
                Text(start, style: .relative).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(.orange)
                Text(start.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            } else {
                Text("No game scheduled").font(.system(size: 12, design: .monospaced))
            }
            if family != .systemSmall, !d.record.isEmpty {
                Divider()
                Text("\(d.record) · \(d.points) pts").font(.system(size: 14, weight: .bold, design: .monospaced))
                Text("#\(d.divisionRank) in \(d.divisionName)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct HockeyNowWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HockeyNowWidget", intent: TeamChoiceIntent.self, provider: Provider()) { entry in
            HockeyNowWidgetView(entry: entry)
        }
        .configurationDisplayName("HockeyNow")
        .description("Next game and standings for your team.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct HockeyNowWidgetBundle: WidgetBundle {
    var body: some Widget { HockeyNowWidget() }
}
