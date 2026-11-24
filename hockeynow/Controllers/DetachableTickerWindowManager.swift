import AppKit
import SwiftUI

class DetachableTickerWindowManager {
    static let shared = DetachableTickerWindowManager()
    private var activeWindows: [String: NSWindow] = [:]

    func spawnTickerWindow(for game: ESPNEvent, fetcher: ESPNNHLFetcher) {
        if let existing = activeWindows[game.id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let initialRect = NSRect(x: 300, y: 300, width: 280, height: 75)
        let overlay = NSWindow(contentRect: initialRect, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        overlay.isMovableByWindowBackground = true

        overlay.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.15)
        overlay.isOpaque = false
        overlay.hasShadow = true
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces]

        let hosting = NSHostingView(rootView: ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            FloatingOverlayCardView(gameID: game.id, fetcher: fetcher, closeAction: { [weak self] in
                self?.activeWindows[game.id]?.orderOut(nil)
                self?.activeWindows.removeValue(forKey: game.id)
            })
        })

        overlay.contentView = hosting
        activeWindows[game.id] = overlay
        overlay.makeKeyAndOrderFront(nil)
    }
}
