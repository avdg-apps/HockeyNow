import AppKit
import SwiftUI
import Combine

class MenuBarController: NSObject {
    private var systemStatusItem: NSStatusItem?; private var fetchedEngine: ESPNNHLFetcher
    private var popoverAttached: NSPopover; private var hostingView: PassthroughHostingView<MenuBarStatusItemView>?; private var rulerView: NSHostingView<MenuBarStatusItemView>?; private var bag = Set<AnyCancellable>()

    init(fetcher: ESPNNHLFetcher, popover: NSPopover) {
        self.fetchedEngine = fetcher; self.popoverAttached = popover
        super.init()
        systemStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        systemStatusItem?.autosaveName = "HockeyNowStatusItemV2"
        systemStatusItem?.isVisible = true
        if let designButton = systemStatusItem?.button {
            designButton.target = self; designButton.action = #selector(handleStatusClick(_:))
            let host = PassthroughHostingView(rootView: MenuBarStatusItemView(fetchedEngine: fetcher))
            self.hostingView = host
            self.rulerView = NSHostingView(rootView: MenuBarStatusItemView(fetchedEngine: fetcher))
            designButton.addSubview(host)
            host.frame = designButton.bounds
            host.autoresizingMask = [.width, .height]
            Publishers.CombineLatest(fetchedEngine.$currentStatusString, fetchedEngine.$menuDisplayMode)
                .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self = self, let hostView = self.hostingView, let ruler = self.rulerView, let item = self.systemStatusItem else { return }
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
            popoverWindow.orderFrontRegardless()
        }
    }

    var statusItemScreenFrame: NSRect? {
        guard let button = systemStatusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.frame)
    }
}
