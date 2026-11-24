import SwiftUI
import AppKit

extension Color {
    static let amber = Color(red: 1.0, green: 0.75, blue: 0.0)
    static let deepIce = Color(red: 0.1, green: 0.15, blue: 0.25)
    static let menuCapsuleBg = Color.primary.opacity(0.12)
}

extension Color {
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        let nsColor = NSColor(self)
        if let components = nsColor.usingColorSpace(.deviceRGB)
            ?? nsColor.usingColorSpace(.sRGB)
            ?? nsColor.usingColorSpace(.extendedSRGB)
            ?? nsColor.usingColorSpace(.genericRGB) {
            let r = Int((components.redComponent * 255).rounded())
            let g = Int((components.greenComponent * 255).rounded())
            let b = Int((components.blueComponent * 255).rounded())
            return String(format: "%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
        }
        if let cgComponents = nsColor.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components, cgComponents.count >= 3 {
            let r = Int((cgComponents[0] * 255).rounded())
            let g = Int((cgComponents[1] * 255).rounded())
            let b = Int((cgComponents[2] * 255).rounded())
            return String(format: "%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
        }
        return "007AFF"
    }
}

let defaultAccentHex = "007AFF"
