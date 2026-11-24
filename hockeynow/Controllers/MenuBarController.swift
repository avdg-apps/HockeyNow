import AppKit
import SwiftUI
import Combine

// MARK: - Controller
class MenuBarController: NSObject {
    private var systemStatusItem: NSStatusItem?; private var fetchedEngine: ESPNNHLFetcher
    private var popoverAttached: NSPopover; private var hostingView: PassthroughHostingView<MenuBarStatusItemView>?; private var rulerView: NSHostingView<MenuBarStatusItemView>?; private var bag = Set<AnyCancellable>()
    
    init(fetcher: ESPNNHLFetcher, popover: NSPopover) {
        self.fetchedEngine = fetcher; self.popoverAttached = popover
        super.init()
        systemStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A fresh autosave name discards any stale saved position that could leave the item off-screen.
        systemStatusItem?.autosaveName = "HockeyNowStatusItemV2"
        systemStatusItem?.isVisible = true
        if let designButton = systemStatusItem?.button {
            designButton.target = self; designButton.action = #selector(handleStatusClick(_:))
            let host = PassthroughHostingView(rootView: MenuBarStatusItemView(fetchedEngine: fetcher))
            self.hostingView = host
            // A second, never-displayed copy of the view is what gets measured, so the width never depends on the button's current size.
            self.rulerView = NSHostingView(rootView: MenuBarStatusItemView(fetchedEngine: fetcher))
            designButton.addSubview(host)
            host.frame = designButton.bounds
            host.autoresizingMask = [.width, .height]
            Publishers.CombineLatest(fetchedEngine.$currentStatusString, fetchedEngine.$menuDisplayMode)
                .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self = self, let hostView = self.hostingView, let ruler = self.rulerView, let item = self.systemStatusItem else { return }
                    // Resizing a status item makes macOS re-lay-out the whole menu bar, and macOS 27 drops items that get
                    // too wide, so cap the width and only resize on a real change.
                    ruler.layoutSubtreeIfNeeded()
                    let width = min(max(ceil(ruler.fittingSize.width), 28), 260)
                    if abs(item.length - width) > 1 { item.length = width }
                    if let button = item.button { hostView.frame = button.bounds }
                }.store(in: &bag)
        }
    }
    @objc func handleStatusClick(_ sender: AnyObject?) {
        guard let designButton = systemStatusItem?.button else { return }
        if popoverAttached.isShown { popoverAttached.performClose(sender) }
        else { showPopoverAcrossSpaces(from: designButton, sender: sender) }
    }
    
    func presentPopover() {
        guard let designButton = systemStatusItem?.button, !popoverAttached.isShown else { return }
        showPopoverAcrossSpaces(from: designButton, sender: nil)
    }
    
    private func showPopoverAcrossSpaces(from designButton: NSStatusBarButton, sender: AnyObject?) {
        NSApp.activate(ignoringOtherApps: true)
        popoverAttached.show(relativeTo: designButton.bounds, of: designButton, preferredEdge: .minY)
        if let popoverWindow = popoverAttached.contentViewController?.view.window {
            popoverWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            popoverWindow.level = .statusBar
            // `.show()` above orders the window front using the app's normal (active-app-only)
            // ordering, which is unreliable while a full-screen app owns the active space since
            // HockeyNow is a background/accessory app. `orderFrontRegardless()` is the AppKit-documented
            // way to bring a window forward "even when your app isn't the active app" - without it,
            // this popover (and therefore the calendar picker inside it) can silently fail to appear
            // over a full-screen app.
            popoverWindow.orderFrontRegardless()
        }
    }
    
// MARK: - Screen Anchor
    var statusItemScreenFrame: NSRect? {
        guard let button = systemStatusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.frame)
    }
}
