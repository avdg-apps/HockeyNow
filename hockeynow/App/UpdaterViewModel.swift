import AppKit
import Foundation
import Combine
import Sparkle

final class UpdaterViewModel: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private(set) var controller: SPUStandardUpdaterController!
    @Published var canCheckForUpdates = false
    private var bag = Set<AnyCancellable>()
    private let appcastFeedURLString = "https://raw.githubusercontent.com/avdg-apps/HockeyNow/refs/heads/main/website/appcast.xml"

    override init() {
        super.init()
        self.controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        _ = controller.updater.clearFeedURLFromUserDefaults()
        self.controller.startUpdater()

        canCheckForUpdates = controller.updater.canCheckForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &bag)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        appcastFeedURLString
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate(ignoringOtherApps: true)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
