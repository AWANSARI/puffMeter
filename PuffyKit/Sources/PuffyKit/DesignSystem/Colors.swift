import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// PuffyMeter color tokens. Views never hardcode hex values; they use these.
public extension Color {
    static let pmBackground = Color(light: 0xF2F2F7, dark: 0x000000)
    static let pmCard = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let pmCardElevated = Color(light: 0xF2F2F7, dark: 0x2C2C2E)
    static let pmSeparator = Color(light: 0xC6C6C8, dark: 0x38383A)

    static let pmLabel = Color(light: 0x000000, dark: 0xFFFFFF)
    static let pmLabelSecondary = Color(light: 0x3C3C43, lightAlpha: 0.6, dark: 0xEBEBF5, darkAlpha: 0.6)
    static let pmLabelTertiary = Color(light: 0x3C3C43, lightAlpha: 0.3, dark: 0xEBEBF5, darkAlpha: 0.3)

    static let pmAccent = Color(light: 0xFF1050, dark: 0xFF1050)
    static let pmDePuff = pmAccent
    static let pmDePuffEnd = Color(light: 0xFF3A6E, dark: 0xFF3A6E)
    static let pmDePuffTrack = Color(light: 0xFF1050, lightAlpha: 0.22, dark: 0xFF1050, darkAlpha: 0.28)

    static let pmScan = Color(light: 0x5DA80E, dark: 0xA3E635)
    static let pmScanEnd = Color(light: 0x7BC91B, dark: 0xC6FF4A)
    static let pmScanTrack = Color(light: 0x5DA80E, lightAlpha: 0.22, dark: 0xA3E635, darkAlpha: 0.25)

    static let pmHabits = Color(light: 0x00A9B5, dark: 0x1EEAEF)
    static let pmHabitsEnd = Color(light: 0x22C4D0, dark: 0x5CF3FF)
    static let pmHabitsTrack = Color(light: 0x00A9B5, lightAlpha: 0.22, dark: 0x1EEAEF, darkAlpha: 0.25)

    static let pmLink = Color(light: 0x007AFF, dark: 0x0A84FF)
    static let pmSuccess = Color(light: 0x34C759, dark: 0x30D158)
    static let pmWarning = Color(light: 0xFF9500, dark: 0xFF9F0A)
    static let pmDestructive = Color(light: 0xFF3B30, dark: 0xFF453A)

    /// Tertiary fill used for secondary buttons so they look right in both modes.
    /// Ring arcs stay vivid in both modes (Fitness look); text uses the contrast-safe tokens above.
    static let pmRingDePuff = Color(light: 0xFF1050, dark: 0xFF1050)
    static let pmRingScan = Color(light: 0x8EE02A, dark: 0x96E52B)
    static let pmRingHabits = Color(light: 0x1EE3EF, dark: 0x1EEAEF)

    /// Tinted fill behind pink chips and tags.
    static let pmAccentFill = Color(light: 0xFF1050, lightAlpha: 0.12, dark: 0xFF1050, darkAlpha: 0.2)

    static let pmSecondaryFill = Color(light: 0x767680, lightAlpha: 0.12, dark: 0x767680, darkAlpha: 0.24)
}

extension Color {
    init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark, alpha: darkAlpha)
                : NSColor(hex: light, alpha: lightAlpha)
        })
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#elseif canImport(AppKit)
extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#endif

/// The three ring palettes.
public enum RingKind: CaseIterable, Sendable {
    case dePuff, scan, habits

    public var title: String {
        switch self {
        case .dePuff: "De-Puff"
        case .scan: "Scan"
        case .habits: "Habits"
        }
    }

    public var color: Color {
        switch self {
        case .dePuff: .pmDePuff
        case .scan: .pmScan
        case .habits: .pmHabits
        }
    }

    public var ringColor: Color {
        switch self {
        case .dePuff: .pmRingDePuff
        case .scan: .pmRingScan
        case .habits: .pmRingHabits
        }
    }

    public var endColor: Color {
        switch self {
        case .dePuff: .pmDePuffEnd
        case .scan: .pmScanEnd
        case .habits: .pmHabitsEnd
        }
    }

    public var trackColor: Color {
        switch self {
        case .dePuff: .pmDePuffTrack
        case .scan: .pmScanTrack
        case .habits: .pmHabitsTrack
        }
    }
}

public extension ChallengeDefinition.Accent {
    var ring: RingKind {
        switch self {
        case .dePuff: .dePuff
        case .scan: .scan
        case .habits: .habits
        }
    }
}
