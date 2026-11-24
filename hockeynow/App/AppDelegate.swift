import AppKit
import SwiftUI
import UserNotifications

// MARK: - Auto Bridge
class AppDelegate: NSObject, NSApplicationDelegate {
    private var sharedFetcher: ESPNNHLFetcher?; private var barController: MenuBarController?; private var notchHUDController: NotchHUDWindowController?
    let updaterViewModel = UpdaterViewModel()
    let centralPopover = NSPopover()
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsBackup.restoreIfNeeded()
        SettingsBackup.startAutoBackup()
        if UserDefaults.standard.object(forKey: "notifications_enabled_toggle") == nil {
            UserDefaults.standard.set(true, forKey: "notifications_enabled_toggle")
        }
        if UserDefaults.standard.bool(forKey: "hide_dock_icon_enabled") {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
        // The delegate must exist before anything is posted, or macOS hides banners while the app counts as frontmost.
        NotificationManager.shared.configure()
        let fetcher = ESPNNHLFetcher(); self.sharedFetcher = fetcher
        HockeyNowBridge.fetcher = fetcher
        centralPopover.contentSize = NSSize(width: 560, height: 560); centralPopover.behavior = .transient
        centralPopover.contentViewController = NSHostingController(rootView: ContentView(fetcher: fetcher).environmentObject(updaterViewModel))
        self.barController = MenuBarController(fetcher: fetcher, popover: centralPopover)
        self.notchHUDController = NotchHUDWindowController(fetcher: fetcher)
        
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let panel = note.object as? NSColorPanel, panel === NSColorPanel.shared,
                  let anchor = self?.barController?.statusItemScreenFrame,
                  let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) })?.frame ?? NSScreen.main?.frame
            else { return }
            let panelSize = panel.frame.size
            let x = min(max(anchor.midX - panelSize.width / 2, screenFrame.minX + 12), screenFrame.maxX - panelSize.width - 12)
            let y = anchor.minY - panelSize.height - 8
            panel.setFrameOrigin(NSPoint(x: x, y: max(y, screenFrame.minY + 12)))
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "q" {
                NSApplication.shared.terminate(nil)
                return nil
            }
            return event
        }
    }
}
