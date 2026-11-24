import Foundation
import Combine

@MainActor
enum SettingsBackup {
    private static let markerKey = "settings_store_initialised"
    private static var bag = Set<AnyCancellable>()

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("HockeyNow", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("settings-backup.plist")
    }

    private static func ownKeys(_ domain: [String: Any]) -> [String: Any] {
        domain.filter { key, _ in
            !key.hasPrefix("SU") && !key.hasPrefix("NS") && !key.hasPrefix("Apple") && !key.hasPrefix("com.apple") && !key.hasPrefix("AK")
        }
    }

    static func restoreIfNeeded() {
        let defaults = UserDefaults.standard
        defer { defaults.set(true, forKey: markerKey) }
        guard defaults.object(forKey: markerKey) == nil,
              let url = fileURL, let data = try? Data(contentsOf: url),
              let saved = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else { return }
        for (key, value) in ownKeys(saved) where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
    }

    static func startAutoBackup() {
        write()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .seconds(3), scheduler: DispatchQueue.main)
            .sink { _ in write() }
            .store(in: &bag)
    }

    private static func write() {
        guard let id = Bundle.main.bundleIdentifier, let url = fileURL,
              let domain = UserDefaults.standard.persistentDomain(forName: id) else { return }
        let snapshot = ownKeys(domain)
        guard PropertyListSerialization.propertyList(snapshot, isValidFor: .binary),
              let data = try? PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
