import Foundation
import Combine
import Network

// Tells the UI when the Mac is offline, so it can say that saved games are being shown.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "hockeynow.network-monitor"))
    }

    deinit { monitor.cancel() }
}
