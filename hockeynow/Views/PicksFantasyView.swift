import SwiftUI
import AppKit

struct PicksFantasyView: View {
    @ObservedObject var fetcher: ESPNNHLFetcher
    @ObservedObject private var store = PicksFantasyStore.shared
    @State private var section: Section = .watchParty
    @State private var search = ""

    enum Section: String, CaseIterable, Identifiable {
        case watchParty = "Watch party", picks = "Pick'em", fantasy = "Fantasy"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 18).padding(.top, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    switch section {
                    case .watchParty: watchParty
                    case .picks: pickem
                    case .fantasy: fantasy
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 16)
            }
        }
        .frame(height: 480)
    }

    private var allGames: [ESPNEvent] {
        var seen = Set<String>()
        return (fetcher.rawFetchedGames + fetcher.seasonGames).filter { seen.insert($0.id).inserted }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(.secondary).tracking(0.6)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var upcomingForFollowed: [ESPNEvent] {
        let followed = hockeyNowFavouriteTeams()
        let now = Date().addingTimeInterval(-3 * 3600)
        let pool = allGames.filter { game in
            guard game.abstractState != "Final", let date = game.systemCalendarDate, date > now else { return false }
            let a = game.awayTeam?.team.threeLetterAbbreviation ?? "", h = game.homeTeam?.team.threeLetterAbbreviation ?? ""
            return followed.isEmpty || followed.contains(a) || followed.contains(h)
        }
        return Array(pool.sorted { ($0.systemCalendarDate ?? .distantFuture) < ($1.systemCalendarDate ?? .distantFuture) }.prefix(3))
    }

    @ViewBuilder private var watchParty: some View {
        if upcomingForFollowed.isEmpty {
            Text("No upcoming games found yet for your teams.").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).padding(.top, 30)
        }
        ForEach(upcomingForFollowed, id: \.id) { game in
            if let start = game.systemCalendarDate, let away = game.awayTeam, let home = game.homeTeam {
                let matchup = "\(away.team.threeLetterAbbreviation) @ \(home.team.threeLetterAbbreviation)"
                card {
                    HStack {
                        Text(matchup).font(.system(size: 15, weight: .black, design: .monospaced))
                        Spacer()
                        if game.abstractState == "Live" {
                            Text("LIVE").font(.system(size: 9, weight: .black, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.red).foregroundColor(.white).clipShape(Capsule())
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(game.abstractState == "Live" ? "Game is on now" : countdown(to: start, now: context.date))
                            .font(.system(size: 22, weight: .black, design: .monospaced)).foregroundColor(.amber)
                            .contentTransition(.numericText())
                    }
                    Text("\(hockeyNowDayWord(for: start, zone: fetcher.targetZone)) · \(hockeyNowClockString(for: start, zone: fetcher.targetZone)) \(fetcher.targetZone.abbreviation(for: start) ?? "")")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    HStack(spacing: 8) {
                        Button { addToCalendar(game, start: start, matchup: matchup) } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                        Button { copyInvite(start: start, matchup: matchup) } label: { Label("Copy invite", systemImage: "doc.on.doc") }
                    }
                    .buttonStyle(.bordered).controlSize(.small).font(.system(size: 10, design: .monospaced))
                }
            }
        }
    }

    private func countdown(to date: Date, now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "Puck drop!" }
        let d = seconds / 86_400, h = (seconds % 86_400) / 3_600, m = (seconds % 3_600) / 60, s = seconds % 60
        if d > 0 { return String(format: "%dd %02dh %02dm", d, h, m) }
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func copyInvite(start: Date, matchup: String) {
        let zones: [(String, String)] = [("Here", fetcher.targetZone.identifier), ("ET", "America/New_York"), ("PT", "America/Los_Angeles"), ("UK", "Europe/London")]
        var seenZones = Set<String>()
        let lines = zones.compactMap { label, id -> String? in
            guard let zone = TimeZone(identifier: id), seenZones.insert(id).inserted else { return nil }
            let day = HockeyNowFormatterCache.formatter(format: "EEE d MMM", zone: zone).string(from: start)
            let clock = HockeyNowFormatterCache.formatter(format: hockeyNowTimeFormat(), zone: zone).string(from: start)
            return "\(label): \(day), \(clock) \(zone.abbreviation(for: start) ?? "")"
        }
        let text = "Watch party! \(matchup)\n" + lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func addToCalendar(_ game: ESPNEvent, start: Date, matchup: String) {
        let stamp = HockeyNowFormatterCache.formatter(format: "yyyyMMdd'T'HHmmss'Z'", zone: TimeZone(secondsFromGMT: 0)!)
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//HockeyNow//EN
        BEGIN:VEVENT
        UID:hockeynow-\(game.id)@hockeynow
        DTSTAMP:\(stamp.string(from: Date()))
        DTSTART:\(stamp.string(from: start))
        DTEND:\(stamp.string(from: start.addingTimeInterval(3 * 3600)))
        SUMMARY:\(matchup) (NHL)
        BEGIN:VALARM
        TRIGGER:-PT15M
        ACTION:DISPLAY
        DESCRIPTION:Puck drop in 15 minutes
        END:VALARM
        END:VEVENT
        END:VCALENDAR
        """.replacingOccurrences(of: "\n        ", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HockeyNow-\(game.id).ics")
        if (try? ics.write(to: url, atomically: true, encoding: .utf8)) != nil { NSWorkspace.shared.open(url) }
    }

    private var todaysSlate: [ESPNEvent] { fetcher.localFilteredGames }

    @ViewBuilder private var pickem: some View {
        let record = store.record(finals: allGames.filter { $0.abstractState == "Final" })
        card {
            heading("YOUR RECORD")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(record.wins)-\(record.losses)").font(.system(size: 24, weight: .black, design: .monospaced)).foregroundColor(.amber)
                Text("\(record.percentage)%").font(.system(size: 14, weight: .bold, design: .monospaced))
                if record.streak != 0 {
                    Text(record.streak > 0 ? "W\(record.streak) streak" : "L\(-record.streak) streak")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(record.streak > 0 ? .green : .red)
                }
            }
        }
        heading("PICK A WINNER · \(todaysSlate.count) GAMES")
        if todaysSlate.isEmpty {
            Text("No games on the selected date.").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
        }
        ForEach(todaysSlate, id: \.id) { game in pickRow(game) }
    }

    @ViewBuilder private func pickRow(_ game: ESPNEvent) -> some View {
        if let away = game.awayTeam, let home = game.homeTeam {
            let a = away.team.threeLetterAbbreviation, h = home.team.threeLetterAbbreviation
            let chosen = store.picks[game.id]?.pick
            let winner = PicksFantasyStore.winner(of: game)
            let locked = game.abstractState != "Preview"
            HStack(spacing: 8) {
                pickButton(a, selected: chosen == a, state: state(for: a, chosen: chosen, winner: winner)) { store.choose(a, in: game) }.disabled(locked)
                VStack(spacing: 1) {
                    Text(locked ? "\(away.score)–\(home.score)" : "@").font(.system(size: 11, weight: .bold, design: .monospaced))
                    if let start = game.systemCalendarDate, !locked {
                        Text(hockeyNowClockString(for: start, zone: fetcher.targetZone)).font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary)
                    } else if game.abstractState == "Live" {
                        Text("LIVE").font(.system(size: 8, weight: .black, design: .monospaced)).foregroundColor(.red)
                    }
                }.frame(width: 70)
                pickButton(h, selected: chosen == h, state: state(for: h, chosen: chosen, winner: winner)) { store.choose(h, in: game) }.disabled(locked)
            }
        }
    }

    private enum PickState { case none, pending, correct, wrong }
    private func state(for team: String, chosen: String?, winner: String?) -> PickState {
        guard chosen == team else { return .none }
        guard let winner else { return .pending }
        return winner == team ? .correct : .wrong
    }

    private func pickButton(_ team: String, selected: Bool, state: PickState, action: @escaping () -> Void) -> some View {
        let fill: Color = state == .correct ? .green : (state == .wrong ? .red : (selected ? .amber : Color.primary.opacity(0.07)))
        return Button(action: action) {
            HStack(spacing: 5) {
                Text(team).font(.system(size: 13, weight: .black, design: .monospaced))
                if state == .correct { Image(systemName: "checkmark") } else if state == .wrong { Image(systemName: "xmark") }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(fill.opacity(selected ? 0.9 : 1))
            .foregroundColor(selected ? .black : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var searchResults: [SkaterSeasonLine] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return [] }
        return Array(fetcher.skaterLeaders.filter { $0.displayName.lowercased().contains(query) && !store.isPinned($0.id) }.prefix(6))
    }

    private func gameToday(for team: String) -> ESPNEvent? {
        let calendar = Calendar.current
        let todays = allGames.filter { game in
            guard let date = game.systemCalendarDate, calendar.isDate(date, inSameDayAs: Date()) || game.abstractState == "Live" else { return false }
            return game.awayTeam?.team.threeLetterAbbreviation == team || game.homeTeam?.team.threeLetterAbbreviation == team
        }
        return todays.first { $0.abstractState == "Live" } ?? todays.first { $0.abstractState == "Final" } ?? todays.first
    }

    private func todayLine(for player: PinnedPlayer, in game: ESPNEvent?) -> FantasyScoring.Line? {
        guard let game, game.abstractState != "Preview" else { return nil }
        if let groups = fetcher.gameLineups[game.id], let line = FantasyScoring.line(for: player.id, in: groups) { return line }
        if let groups = fetcher.playerBoxscoreCache[game.id] { return FantasyScoring.line(for: player.id, in: groups) }
        return nil
    }

    @ViewBuilder private var fantasy: some View {
        let rows = store.pinned.map { player -> (PinnedPlayer, ESPNEvent?, FantasyScoring.Line?) in
            let game = gameToday(for: player.team)
            return (player, game, todayLine(for: player, in: game))
        }
        let total = rows.reduce(0.0) { $0 + ($1.2?.points ?? 0) }
        card {
            heading("TODAY'S FANTASY POINTS")
            Text(String(format: "%.1f", total)).font(.system(size: 28, weight: .black, design: .monospaced)).foregroundColor(.amber)
            Text(FantasyScoring.summary).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
        }
        heading("PINNED PLAYERS (\(store.pinned.count)/12)")
        if rows.isEmpty {
            Text("Search below and pin players to follow their points live.").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
        }
        ForEach(rows, id: \.0.id) { player, game, line in
            HStack(spacing: 10) {
                PlayerHeadshotView(headshotURLString: player.headshot, initials: String(player.name.split(separator: " ").compactMap { $0.first }.prefix(2)).uppercased(), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name).font(.system(size: 12, weight: .bold, design: .monospaced)).lineLimit(1)
                    Text("\(player.team) · \(player.position) · \(status(of: game))").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                }
                Spacer()
                if let line {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: "%.1f", line.points)).font(.system(size: 15, weight: .black, design: .monospaced)).foregroundColor(.amber)
                        Text("\(line.goals)G \(line.assists)A \(line.shots)S").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                    }
                } else {
                    Text("—").foregroundColor(.secondary)
                }
                Button { store.unpin(player.id) } label: { Image(systemName: "pin.slash") }.buttonStyle(.plain).foregroundColor(.secondary)
            }
            .padding(10).background(Color.primary.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        heading("ADD A PLAYER")
        TextField("Search skaters", text: $search).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
        ForEach(searchResults) { skater in
            HStack {
                PlayerHeadshotView(headshotURLString: skater.headshotURL, initials: String(skater.displayName.split(separator: " ").compactMap { $0.first }.prefix(2)).uppercased(), size: 24)
                Text(skater.displayName).font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("\(skater.teamAbbreviation) · \(skater.points) P").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
                Button("Pin") {
                    store.pin(PinnedPlayer(id: skater.id, name: skater.displayName, team: skater.teamAbbreviation, position: skater.position, headshot: skater.headshotURL))
                    search = ""
                }.controlSize(.small)
            }
        }
        Color.clear.frame(height: 0).task(id: store.pinned.map(\.id)) {
            while !Task.isCancelled {
                for player in store.pinned {
                    if let game = gameToday(for: player.team), game.abstractState != "Preview" { await fetcher.fetchDetails(for: game.id, silent: true) }
                }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func status(of game: ESPNEvent?) -> String {
        guard let game else { return "no game today" }
        switch game.abstractState {
        case "Live": return "live"
        case "Final": return "final"
        default: return game.systemCalendarDate.map { hockeyNowClockString(for: $0, zone: fetcher.targetZone) } ?? "tonight"
        }
    }
}
