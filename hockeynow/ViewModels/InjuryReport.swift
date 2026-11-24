import Foundation
import Combine

struct InjuryEntry: Identifiable {
    let id: String
    let name: String
    let position: String
    let status: String
    let note: String
    var isOut: Bool {
        let lower = status.lowercased()
        return lower.contains("out") || lower.contains("injured reserve") || lower == "ir" || lower.contains("ltir")
    }
}

// MARK: - Injuries
// Best effort: ESPN publishes a league-wide injury list. If it is missing or shaped differently, the section stays hidden.
@MainActor
final class InjuryReport: ObservableObject {
    @Published private(set) var entriesByTeamName: [String: [InjuryEntry]] = [:]
    @Published private(set) var hasLoaded = false
    private var lastLoad: Date?

    func load() async {
        if let lastLoad, Date().timeIntervalSince(lastLoad) < 30 * 60 { return }
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/injuries") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(InjuryResponse.self, from: data)
            var result: [String: [InjuryEntry]] = [:]
            for team in decoded.injuries ?? [] {
                guard let teamName = team.displayName else { continue }
                result[teamName] = (team.injuries ?? []).enumerated().compactMap { index, item in
                    guard let name = item.athlete?.displayName else { return nil }
                    return InjuryEntry(id: "\(teamName)-\(index)-\(name)", name: name, position: item.athlete?.position?.abbreviation ?? "",
                                       status: item.status ?? "Out", note: item.shortComment ?? "")
                }
            }
            entriesByTeamName = result
            hasLoaded = true
            lastLoad = Date()
        } catch {
            hasLoaded = true
        }
    }

    func entries(forTeamName name: String) -> [InjuryEntry] {
        if let exact = entriesByTeamName[name] { return exact }
        let nickname = name.split(separator: " ").last.map(String.init) ?? name
        return entriesByTeamName.first { $0.key.hasSuffix(nickname) }?.value ?? []
    }
}

private struct InjuryResponse: Decodable { let injuries: [TeamInjuries]? }

private struct TeamInjuries: Decodable {
    let displayName: String?
    let injuries: [InjuryItem]?
    enum CodingKeys: String, CodingKey { case displayName, injuries }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try? container.decodeIfPresent(String.self, forKey: .displayName)
        injuries = try? container.decodeIfPresent([InjuryItem].self, forKey: .injuries)
    }
}

private struct InjuryItem: Decodable {
    let status: String?
    let shortComment: String?
    let athlete: InjuryAthlete?
    enum CodingKeys: String, CodingKey { case status, shortComment, athlete }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        shortComment = try? container.decodeIfPresent(String.self, forKey: .shortComment)
        athlete = try? container.decodeIfPresent(InjuryAthlete.self, forKey: .athlete)
    }
}

private struct InjuryAthlete: Decodable {
    let displayName: String?
    let position: Position?
    struct Position: Decodable { let abbreviation: String? }
    enum CodingKeys: String, CodingKey { case displayName, position }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try? container.decodeIfPresent(String.self, forKey: .displayName)
        position = try? container.decodeIfPresent(Position.self, forKey: .position)
    }
}
