import AppKit
import SwiftUI
import Combine

// MARK: - Hover detection
// The window is kept at its expanded size at all times (so it is never resized mid-hover, which is what used to make
// the HUD glitch when the pointer went in and out quickly). Whether the pointer is "over the notch" is decided purely
// from the pointer position against the visible shape, using global + local mouse-move monitors.
private final class NotchHoverMonitor {
    var onMove: ((NSPoint) -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.onMove?(NSEvent.mouseLocation)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.onMove?(NSEvent.mouseLocation)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    deinit { stop() }
}

// MARK: - Panel
// A non-activating panel never steals focus from the app you're using. Together with the `.stationary` collection
// behaviour it is left alone by Mission Control, Stage Manager and "click the wallpaper to show the desktop",
// which is what keeps the HUD anchored to the notch like a piece of the menu bar.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // By default AppKit shoves a borderless window down out of the menu-bar band, which left the pin *below* the notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// MARK: - Notch HUD Controller
final class NotchHUDWindowController: NSObject {
    private var window: NSPanel?
    private var windowObservers = Set<AnyCancellable>()
    private var anchorTimer: Timer?
    private let fetcher: ESPNNHLFetcher
    private let state = NotchState()
    private var cancellables = Set<AnyCancellable>()

    private let expandedHeight: CGFloat = 300
    private var collapsedHeight: CGFloat = 32      // updated from the screen's real notch height on every layout
    private var collapseWork: DispatchWorkItem?
    private var popoutWork: DispatchWorkItem?
    private var holdOpenUntil = Date.distantPast       // a pop-out stays open even though the pointer isn't on it
    private var renderedSignature = ""
    private let hover = NotchHoverMonitor()
    private var notchWidth: CGFloat = 620
    private var collapsedWidth: CGFloat = 340
    private var hardwareNotchPoints: CGFloat = 180
    private var notchFrameOnScreen = NSRect.zero    // the window frame at its full (expanded) size

    // Above the menu bar and its status items (the level boring.notch uses).
    private let hudLevel = NSWindow.Level.popUpMenu

    init(fetcher: ESPNNHLFetcher) {
        self.fetcher = fetcher
        super.init()

        fetcher.$notchedGameInstance
            .map { $0?.id }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // Goals, penalties and period ends in followed teams' games open the notch by themselves for a few seconds.
        fetcher.liveActivity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.present(event) }
            .store(in: &cancellables)

        // The HUD setting is checked here, but UserDefaults posts for every key anywhere, so coalesce and compare.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in UserDefaults.standard.object(forKey: "notch_hud_enabled") == nil || UserDefaults.standard.bool(forKey: "notch_hud_enabled") }
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // Display changes arrive in bursts (menu bar, Spaces, resolution), so handle them once, after they settle.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh(force: true) }
            .store(in: &cancellables)

        // Entering or leaving a full-screen Space can leave the window behind; raise it once, only if it is hidden.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let window = self?.window, !window.occlusionState.contains(.visible) else { return }
                window.orderFrontRegardless()
            }
            .store(in: &cancellables)
    }

    // MARK: - Layout
    private func refresh(force: Bool = false) {
        let enabled = UserDefaults.standard.object(forKey: "notch_hud_enabled") == nil || UserDefaults.standard.bool(forKey: "notch_hud_enabled")
        guard enabled,
              let game = fetcher.notchedGameInstance,
              let away = game.awayTeam, let home = game.homeTeam,
              let screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }) else {
            removeHUD()
            return
        }

        // Size and position come from the screen's own notch geometry, never from the app's menu bar.
        // The hardware notch is exactly safeAreaInsets.top tall; using the full value keeps the HUD flush with it.
        if screen.safeAreaInsets.top > 0 { collapsedHeight = screen.safeAreaInsets.top }
        var centerX = screen.frame.midX
        var hardwareNotchWidth: CGFloat = 180
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, right.minX - left.maxX > 0 {
            hardwareNotchWidth = right.minX - left.maxX
            centerX = (left.maxX + right.minX) / 2
        }
        let width = min(640, screen.frame.width - 40)     // wide enough for two columns of content
        collapsedWidth = min(width, max(hardwareNotchWidth + 110, 320))     // unchanged: the collapsed size stays as it was
        hardwareNotchPoints = hardwareNotchWidth
        // Keep a stable expanded window; the visible panel contracts around the hardware notch while idle.
        let frame = NSRect(x: centerX - width / 2, y: screen.frame.maxY - expandedHeight, width: width, height: expandedHeight)
        notchWidth = width
        notchFrameOnScreen = frame
        let signature = "\(game.id)-\(Int(width))-\(Int(collapsedWidth))-\(Int(hardwareNotchPoints))-\(Int(collapsedHeight))-\(Int(expandedHeight))"

        if window == nil {
            makeWindow(frame: frame, away: away, home: home, game: game, width: width)
        } else {
            if window?.frame != frame { window?.setFrame(frame, display: true) }
            if window?.level != hudLevel { window?.level = hudLevel }
            if window?.isVisible == false { window?.orderFrontRegardless() }
            // The root view only needs rebuilding when the game or the geometry changed.
            if force || signature != renderedSignature { installRootView(away: away, home: home, game: game, width: width) }
        }
        renderedSignature = signature
    }

    private func makeWindow(frame: NSRect, away: ESPNEvent.ESPNCompetitor, home: ESPNEvent.ESPNCompetitor, game: ESPNEvent, width: CGFloat) {
        let panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // isFloatingPanel resets the window level to "floating", so it has to be set first and the real level after it.
        // Otherwise the HUD ends up beneath the menu bar and its icons draw over the expanded notch.
        panel.isFloatingPanel = true
        panel.level = hudLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.isReleasedWhenClosed = false

        // Collapsed, the (transparent) window must never swallow clicks meant for the menu bar beneath it.
        panel.ignoresMouseEvents = true
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        panel.contentView = container
        window = panel
        observeWindow(panel)
        startAnchorWatchdog()
        hover.onMove = { [weak self] point in self?.handlePointer(point) }
        hover.start()
        installRootView(away: away, home: home, game: game, width: width)
        panel.orderFrontRegardless()
    }

    private func installRootView(away: ESPNEvent.ESPNCompetitor, home: ESPNEvent.ESPNCompetitor, game: ESPNEvent, width: CGFloat) {
        guard let tracker = window?.contentView else { return }
        tracker.subviews.forEach { $0.removeFromSuperview() }
        let hosting = NSHostingView(rootView: InteractiveNotchRootView(away: away, home: home, game: game, fetcher: fetcher,
                                                                      notchWidth: width, collapsedWidth: collapsedWidth, hardwareNotchWidth: hardwareNotchPoints, collapsedHeight: collapsedHeight, expandedHeight: expandedHeight, state: state))
        hosting.sizingOptions = []
        hosting.frame = tracker.bounds
        hosting.autoresizingMask = [.width, .height]
        tracker.addSubview(hosting)
    }

    // If the system slides the window away (show-desktop, Spaces) or hides it, put it straight back.
    private func observeWindow(_ panel: NSPanel) {
        windowObservers.removeAll()
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let window = self.window else { return }
                let target = self.notchFrameOnScreen
                if abs(window.frame.minX - target.minX) > 1 || abs(window.frame.minY - target.minY) > 1 { window.setFrame(target, display: true) }
            }
            .store(in: &windowObservers)
        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: panel)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let window = self?.window, !window.occlusionState.contains(.visible) else { return }
                window.orderFrontRegardless()
            }
            .store(in: &windowObservers)
    }
    
    // "Click the wallpaper to show the desktop" slides windows away inside WindowServer, so AppKit often isn't told.
    // This compares where the window really is on screen with where it should be, and snaps it back.
    private func startAnchorWatchdog() {
        anchorTimer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.enforceAnchoring() }
        RunLoop.main.add(timer, forMode: .common)
        anchorTimer = timer
    }
    
    private func enforceAnchoring() {
        guard let window, window.windowNumber > 0 else { return }
        let target = notchFrameOnScreen
        var misplaced = abs(window.frame.minX - target.minX) > 1 || abs(window.frame.maxY - target.maxY) > 1
        var hidden = !window.isVisible
        if let primary = NSScreen.screens.first,
           let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window.windowNumber)) as? [[String: Any]])?.first {
            if let boundsDict = info[kCGWindowBounds as String] as? NSDictionary, let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                let expectedTop = primary.frame.height - target.maxY      // CG space is top-left based
                if abs(bounds.minX - target.minX) > 2 || abs(bounds.minY - expectedTop) > 2 { misplaced = true }
            }
            if let onScreen = info[kCGWindowIsOnscreen as String] as? Bool, !onScreen { hidden = true }
        }
        guard misplaced || hidden else { return }
        // Nudge first: setting an identical frame can be a no-op even though the server moved the window.
        window.setFrame(target.offsetBy(dx: 0, dy: -1), display: false)
        window.setFrame(target, display: true)
        window.orderFrontRegardless()
    }
    
    // MARK: - Expand / collapse
    // The rectangle the pointer must be inside for the HUD to be open: just the notch strip when collapsed, and the whole
    // expanded shape (with a little slack, so the edge doesn't flicker) when open.
    private func hoverRect() -> NSRect {
        let f = notchFrameOnScreen
        if state.isExpanded {
            return NSRect(x: f.minX - 6, y: f.minY - 6, width: f.width + 12, height: f.height + 6 + 4)
        }
        let minX = f.midX - collapsedWidth / 2
        return NSRect(x: minX, y: f.maxY - collapsedHeight, width: collapsedWidth, height: collapsedHeight + 4)
    }

    private func handlePointer(_ point: NSPoint) {
        guard window != nil else { return }
        let rect = hoverRect()
        // `contains` excludes the top edge, but the pointer rests exactly on it when pushed to the top of the screen.
        let inside = point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !state.isExpanded { setExpanded(true) }
        } else if state.isExpanded, collapseWork == nil, Date() >= holdOpenUntil {
            // A short delay avoids flicker if the pointer briefly leaves the edge; re-entering cancels it.
            let work = DispatchWorkItem { [weak self] in
                self?.collapseWork = nil
                self?.setExpanded(false)
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }

    // MARK: - Pop-outs
    private func present(_ event: LiveActivityEvent) {
        guard window != nil else { return }
        let style = UserDefaults.standard.string(forKey: "notch_popout_style") ?? "small"
        guard style != "off" else { return }
        // Optionally stay quiet when the notch is showing a different game from the one this alert is about.
        if UserDefaults.standard.bool(forKey: "notch_popout_skip_other_game"), fetcher.notchedGameInstance?.id != event.gameID { return }
        popoutWork?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { state.banner = event }
        let showFor: TimeInterval = event.kind == .goal ? 7 : 5
        // "small" only drops a thin strip under the notch; "full" opens the whole notch.
        if style == "full" {
            holdOpenUntil = Date().addingTimeInterval(showFor)
            if !state.isExpanded { setExpanded(true) }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { self.state.banner = nil }
            self.holdOpenUntil = .distantPast
            // Close again unless the pointer is resting on the notch.
            let point = NSEvent.mouseLocation
            let rect = self.hoverRect()
            let inside = point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
            if !inside, self.state.isExpanded { self.setExpanded(false) }
        }
        popoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showFor, execute: work)
    }

    private func setExpanded(_ expanded: Bool) {
        guard state.isExpanded != expanded else { return }
        // While open, the window takes mouse events so the scoring list can be scrolled; while closed it is click-through.
        window?.ignoresMouseEvents = !expanded
        state.isExpanded = expanded
    }

    private func removeHUD() {
        collapseWork?.cancel()
        collapseWork = nil
        hover.stop()
        state.isExpanded = false
        renderedSignature = ""
        windowObservers.removeAll()
        anchorTimer?.invalidate(); anchorTimer = nil
        window?.orderOut(nil)
        window = nil
    }
}
