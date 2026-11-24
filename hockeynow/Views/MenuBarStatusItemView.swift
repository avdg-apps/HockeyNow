import SwiftUI
import AppKit

// MARK: - Menu Bar
struct MenuBarStatusItemView: View {
    @ObservedObject var fetchedEngine: ESPNNHLFetcher
    
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "hockey.puck.fill").font(.system(size: 11, weight: .bold))
                if fetchedEngine.menuDisplayMode != .iconOnly {
                    Text(fetchedEngine.menuDisplayMode == .short ? fetchedEngine.shortStatusString : fetchedEngine.currentStatusString)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: true, vertical: false)
                    if fetchedEngine.menuDisplayMode == .full {
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundColor(.secondary.opacity(0.8)).padding(.leading, 1)
                    }
                }
            }.padding(.horizontal, fetchedEngine.menuDisplayMode == .iconOnly ? 6 : 8).padding(.vertical, 3).background(Color.menuCapsuleBg).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }.padding(.horizontal, 2)
    }
}

// Lets clicks fall through to the status-bar button underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
