import SwiftUI

/// Semantic colours. Everything the app paints goes through here so light and dark
/// stay in step and there is a single place to retune the brand.
enum Theme {
    static let accent = Color("AccentColor")

    /// Reserved for "happening right now" — the live ring, the now line, the pulse.
    static let live = Color(light: Color(hex: 0xF43F5E), dark: Color(hex: 0xFB7185))

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(light: Color(hex: 0x8A94A6), dark: Color(hex: 0x6E7889))

    static let canvas = Color(light: Color(hex: 0xF4F5FA), dark: Color(hex: 0x0B0D12))
    static let surface = Color(light: .white, dark: Color(hex: 0x161A21))
    static let surfaceSoft = Color(light: Color(hex: 0xEDEFF6), dark: Color(hex: 0x1D222B))
    static let hairline = Color(light: Color(hex: 0xD7DCE8), dark: Color(hex: 0x2C333F))

    static let success = Color(light: Color(hex: 0x16A34A), dark: Color(hex: 0x4ADE80))
    static let warning = Color(light: Color(hex: 0xB45309), dark: Color(hex: 0xFBBF24))
    static let danger = Color(light: Color(hex: 0xDC2626), dark: Color(hex: 0xF87171))

    /// Backdrop hues for the aurora mesh behind the main screens.
    static let auroraLight: [Color] = [
        Color(hex: 0xEEF1FF), Color(hex: 0xE7ECFF), Color(hex: 0xF6F0FF),
        Color(hex: 0xE3F2FF), Color(hex: 0xF4F5FA), Color(hex: 0xFFEFF3),
        Color(hex: 0xEFF6FF), Color(hex: 0xF7F3FF), Color(hex: 0xFFF4EC),
    ]

    static let auroraDark: [Color] = [
        Color(hex: 0x131A2E), Color(hex: 0x0E1422), Color(hex: 0x1B1430),
        Color(hex: 0x0C1526), Color(hex: 0x0B0D12), Color(hex: 0x241322),
        Color(hex: 0x0D1830), Color(hex: 0x181233), Color(hex: 0x20150F),
    ]
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Picks between two literal colours based on the rendering trait, without
    /// needing an asset-catalog entry for every shade.
    init(light: Color, dark: Color) {
        #if os(iOS)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
        #endif
    }
}

/// Deterministic colour per course, hashed from the same seed the web app uses so a
/// given course keeps the colour students already associate with it.
enum CourseColor {
    static let palette: [Color] = [
        Color(hex: 0x0EA5E9), Color(hex: 0x14B8A6), Color(hex: 0xF97316),
        Color(hex: 0xEF4444), Color(hex: 0x8B5CF6), Color(hex: 0x22C55E),
        Color(hex: 0xEC4899), Color(hex: 0xEAB308), Color(hex: 0x06B6D4),
    ]

    static func hash(_ value: String) -> Int {
        var hash = 0
        for scalar in value.unicodeScalars {
            hash = Int(scalar.value) &+ ((hash << 5) &- hash)
            hash = hash & 0x7FFF_FFFF
        }
        return abs(hash)
    }

    static func color(for event: CourseEvent) -> Color {
        let seed = event.courseTypeName ?? event.typeName ?? event.code ?? event.title
        return palette[hash(seed) % palette.count]
    }

    static func color(seed: String) -> Color {
        palette[hash(seed) % palette.count]
    }
}

// MARK: - Typography

extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let screenTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let cardTitle = Font.system(.headline, design: .rounded).weight(.semibold)
    static let cardMeta = Font.system(.subheadline, design: .rounded)
    static let label = Font.system(.caption, design: .rounded).weight(.semibold)
}

// MARK: - Metrics

enum Metrics {
    static let cardRadius: CGFloat = 26
    static let tileRadius: CGFloat = 20
    static let chipRadius: CGFloat = 14
    static let gutter: CGFloat = 18
    static let stack: CGFloat = 14
}

// MARK: - Motion

enum Motion {
    static let snappy = Animation.snappy(duration: 0.34, extraBounce: 0.08)
    static let smooth = Animation.smooth(duration: 0.45)
    static let bouncy = Animation.bouncy(duration: 0.5, extraBounce: 0.18)
    static let quick = Animation.easeOut(duration: 0.18)
}
