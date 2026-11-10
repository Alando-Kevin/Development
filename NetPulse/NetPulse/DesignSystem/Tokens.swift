import SwiftUI

// Design tokens. Views take spacing, colour and type from here so the look can change in one place.

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Radius {
    static let s: CGFloat = 2
}

enum IconSize {
    /// The large signal symbol on the Live tab (scales with Dynamic Type).
    static let hero: CGFloat = 52
    /// The big speed readout (scales with Dynamic Type).
    static let heroNumber: CGFloat = 60
    static let legendSwatchWidth: CGFloat = 14
    static let legendSwatchHeight: CGFloat = 4
}

enum ChartSize {
    static let compact: CGFloat = 160
    static let regular: CGFloat = 220
}

extension Color {
    // Named by role. System colours adapt to dark mode and Increase Contrast.
    static let statusGood = Color.green
    static let statusCaution = Color.orange
    static let statusCritical = Color.red
    static let statusNeutral = Color.secondary
    static let chartLine = Color.accentColor
    static let chartDropBand = Color.red.opacity(0.22)
    static let chartDropRule = Color.red
}

extension Font {
    // Built on system text styles, so every one scales with Dynamic Type.
    static let heroTitle = Font.title2.weight(.bold)
    static let statLabel = Font.caption
    static let statValue = Font.title3.weight(.semibold).monospacedDigit()
    static let rowTitle = Font.subheadline
    static let rowDetail = Font.caption
    static let rowValue = Font.subheadline.weight(.semibold).monospacedDigit()
}

extension Quality.Level {
    var color: Color {
        switch self {
        case .excellent, .good: return .statusGood
        case .fair: return .statusCaution
        case .poor, .offline: return .statusCritical
        case .unknown: return .statusNeutral
        }
    }

    /// Shown beside the level name so status never relies on colour alone.
    var symbol: String {
        switch self {
        case .excellent, .good: return "checkmark.circle.fill"
        case .fair: return "exclamationmark.circle.fill"
        case .poor: return "exclamationmark.triangle.fill"
        case .offline: return "xmark.octagon.fill"
        case .unknown: return "ellipsis.circle"
        }
    }
}
