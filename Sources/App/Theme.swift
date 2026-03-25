import AppKit
import SwiftUI

enum Theme {
    // MARK: - Accent

    static let accent = Color(hex: 0x6E5DBA)

    // MARK: - Backgrounds

    static let backgroundWindow = adaptive(light: 0xF4F1F8, dark: 0x1A1824)
    static let backgroundSidebar = adaptive(light: 0xEAE6F2, dark: 0x0A0A12)
    static let backgroundControl = adaptive(light: 0xE5E0EF, dark: 0x232130)
    static let backgroundControlSelected = adaptive(light: 0xB8ACD1, dark: 0x3A3358)
    static let backgroundControlHover = Color.primary.opacity(0.06)
    static let backgroundToggleOff = adaptive(light: 0xB2A9C8, dark: 0x2A2838)
    static let previewOverlay = Color.black.opacity(0.42)
    static let previewOverlayStroke = Color.white.opacity(0.14)

    // MARK: - Text

    static let textPrimary = adaptive(light: 0x2A2838, dark: 0xD8D8E4)
    static let textSecondary = adaptive(light: 0x555164, dark: 0x7A7A8A)
    static let textTertiary = adaptive(light: 0x666177, dark: 0x5A5A6A)
    static let textHeading = adaptive(light: 0x1A1824, dark: 0xE8E8F0)
    static let textLabel = adaptive(light: 0x5A556E, dark: 0x9A9AAA)
    static let textStatus = adaptive(light: 0x625D74, dark: 0x6A6A7A)
    static let previewOverlayTextPrimary = Color.white.opacity(0.96)
    static let previewOverlayTextSecondary = Color.white.opacity(0.82)
    static let previewOverlayTextShadow = Color.black.opacity(0.32)

    // MARK: - Dividers

    static let divider = adaptive(lightAlpha: (0x000000, 0.10), darkAlpha: (0xFFFFFF, 0.06))
    static let controlBorder = adaptive(lightAlpha: (0x000000, 0.14), darkAlpha: (0xFFFFFF, 0.08))
    static let controlShadow = Color.black.opacity(0.12)

    // MARK: - Spacing

    static let sidebarWidth: CGFloat = 260
    static let sidebarPadding: CGFloat = 16
    static let previewPadding: CGFloat = 32
    static let previewCornerRadius: CGFloat = 12

    // MARK: - Helpers

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        })
    }

    private static func adaptive(
        lightAlpha: (UInt32, Double),
        darkAlpha: (UInt32, Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (hex, alpha) = isDark ? darkAlpha : lightAlpha
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            return NSColor(red: r, green: g, blue: b, alpha: CGFloat(alpha))
        })
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
