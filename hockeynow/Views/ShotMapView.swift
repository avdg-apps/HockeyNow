import SwiftUI

struct ShotMapView: View {
    let game: ESPNEvent
    @State private var data: ShotMapData?
    @State private var failed = false

    private var awayAbbr: String { game.awayTeam?.team.threeLetterAbbreviation ?? "AWY" }
    private var homeAbbr: String { game.homeTeam?.team.threeLetterAbbreviation ?? "HOM" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data {
                summary(data)
                rink(data)
                    .aspectRatio(200.0 / 85.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                legend
            } else if failed {
                Text("No shot locations are published for this game yet.").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.padding(.vertical, 20)
            }
        }
        .padding(.horizontal, 18)
        .task(id: game.id) {
            while !Task.isCancelled {
                let result = await NHLStrengthService.shared.shotMap(espnGameID: game.id, awayAbbr: awayAbbr, homeAbbr: homeAbbr, start: game.systemCalendarDate)
                if let result, !result.shots.isEmpty { data = result; failed = false } else if data == nil { failed = true }
                if game.abstractState != "Live" { break }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func summary(_ data: ShotMapData) -> some View {
        HStack(spacing: 10) {
            teamBlock(abbr: awayAbbr, data: data, home: false, color: getGameTeamColor(abbreviation: awayAbbr, isHome: false, opponent: homeAbbr))
            Text("xG").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.secondary)
            teamBlock(abbr: homeAbbr, data: data, home: true, color: getGameTeamColor(abbreviation: homeAbbr, isHome: true, opponent: awayAbbr))
        }
    }

    private func teamBlock(abbr: String, data: ShotMapData, home: Bool, color: Color) -> some View {
        VStack(alignment: home ? .trailing : .leading, spacing: 1) {
            Text(abbr).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundColor(color)
            Text(String(format: "%.2f", data.expected(home: home))).font(.system(size: 18, weight: .black, design: .monospaced))
            Text("\(data.goals(home: home)) G · \(data.onGoal(home: home)) SOG").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: home ? .trailing : .leading)
    }

    private func rink(_ data: ShotMapData) -> some View {
        let awayColor = getGameTeamColor(abbreviation: awayAbbr, isHome: false, opponent: homeAbbr)
        let homeColor = getGameTeamColor(abbreviation: homeAbbr, isHome: true, opponent: awayAbbr)
        return Canvas { context, size in
            let w = size.width, h = size.height
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: (x + 100) / 200 * w, y: (42.5 - y) / 85 * h) }
            let ice = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14)
            context.fill(ice, with: .color(Color(red: 0.93, green: 0.96, blue: 0.99).opacity(0.9)))
            let line = Color(red: 0.35, green: 0.45, blue: 0.6).opacity(0.55)
            for x in [-89.0, 89.0] { var p = Path(); p.move(to: point(x, 42.5)); p.addLine(to: point(x, -42.5)); context.stroke(p, with: .color(.red.opacity(0.45)), lineWidth: 1) }
            for x in [-25.0, 25.0] { var p = Path(); p.move(to: point(x, 42.5)); p.addLine(to: point(x, -42.5)); context.stroke(p, with: .color(.blue.opacity(0.5)), lineWidth: 2) }
            var centre = Path(); centre.move(to: point(0, 42.5)); centre.addLine(to: point(0, -42.5)); context.stroke(centre, with: .color(.red.opacity(0.5)), lineWidth: 2)
            context.stroke(Path(ellipseIn: CGRect(x: point(0, 0).x - 15 / 200 * w, y: point(0, 0).y - 15 / 85 * h, width: 30 / 200 * w, height: 30 / 85 * h)), with: .color(.blue.opacity(0.4)), lineWidth: 1)
            for x in [-69.0, 69.0] { for y in [-22.0, 22.0] {
                context.stroke(Path(ellipseIn: CGRect(x: point(x, y).x - 15 / 200 * w, y: point(x, y).y - 15 / 85 * h, width: 30 / 200 * w, height: 30 / 85 * h)), with: .color(.red.opacity(0.3)), lineWidth: 1)
            } }
            for x in [-89.0, 89.0] {
                var crease = Path(); crease.addArc(center: point(x, 0), radius: 6 / 200 * w, startAngle: .degrees(x > 0 ? 90 : -90), endAngle: .degrees(x > 0 ? 270 : 90), clockwise: false)
                context.stroke(crease, with: .color(line), lineWidth: 1)
            }
            _ = line

            for shot in data.shots {
                let px = shot.isHome ? shot.x : -shot.x, py = shot.isHome ? shot.y : -shot.y
                let center = point(px, py)
                let color = shot.isHome ? homeColor : awayColor
                let radius = 3.0 + shot.xg * 14
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                switch shot.kind {
                case .goal:
                    context.fill(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(.amber))
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(color), lineWidth: 2)
                case .shot:
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.6)))
                case .miss:
                    context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.7)), lineWidth: 1.2)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Goal", AnyView(Circle().fill(Color.amber).overlay(Circle().stroke(Color.primary, lineWidth: 1.5)).frame(width: 10, height: 10)))
            legendItem("Shot on goal", AnyView(Circle().fill(Color.primary.opacity(0.55)).frame(width: 10, height: 10)))
            legendItem("Missed", AnyView(Circle().stroke(Color.primary.opacity(0.6), lineWidth: 1.2).frame(width: 10, height: 10)))
            Spacer()
            Text("Bigger dot = better chance").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
        }
        .font(.system(size: 9, design: .monospaced))
    }

    private func legendItem(_ text: String, _ mark: AnyView) -> some View {
        HStack(spacing: 4) { mark; Text(text).foregroundColor(.secondary) }
    }
}
