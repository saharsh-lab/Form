import SwiftUI
import UIKit

// MARK: - Colour tokens
//
// Every colour adapts to light and dark appearance (and to Increase Contrast)
// through a dynamic UIColor. Views use these tokens, never literal colours.

extension Color {
    /// Warm off-white / deep charcoal page background.
    static let formBackground = Color(light: 0xF6F4EF, dark: 0x121312)
    /// Card surface: white / slightly lighter charcoal.
    static let formSurface = Color(light: 0xFFFFFF, dark: 0x1C1E1C)
    /// Secondary surface for inset controls, tracks and chips.
    static let formSurfaceSecondary = Color(light: 0xEFEDE6, dark: 0x272A27)
    static let formTextPrimary = Color(light: 0x1C1C1A, dark: 0xF2F2EE, highContrastLight: 0x000000, highContrastDark: 0xFFFFFF)
    static let formTextSecondary = Color(light: 0x66655E, dark: 0xA6A69F, highContrastLight: 0x45443F, highContrastDark: 0xCFCFC8)
    static let formSeparator = Color(light: 0xE3E0D8, dark: 0x2F332F)
    /// Muted sage (light) / soft lime-sage (dark).
    static let formAccent = Color(light: 0x5B7A57, dark: 0xB4D08A, highContrastLight: 0x3F5A3C, highContrastDark: 0xCBE6A3)
    /// Text and icons drawn on top of `formAccent`.
    static let formOnAccent = Color(light: 0xFFFFFF, dark: 0x141811)
    /// Tinted fill behind accent content, such as selected chips.
    static let formAccentSoft = Color(light: 0xE4EBDF, dark: 0x2D3726)
    static let formWarning = Color(light: 0xB8662E, dark: 0xE9A26B)
    static let formDestructive = Color(light: 0xB23B32, dark: 0xF07B70)
    static let formSuccess = Color(light: 0x4E7F4F, dark: 0x9BD39A)

    // Macro colours — distinct in hue and lightness, always paired with text labels.
    static let formProtein = Color(light: 0xB86B4B, dark: 0xE79A78)
    static let formCarbs = Color(light: 0xB08D2E, dark: 0xE2C062)
    static let formFat = Color(light: 0x5E7FA6, dark: 0x93B2D8)

    static let formShadow = Color(light: 0x1C1C1A, dark: 0x000000).opacity(0.06)
}

extension Color {
    /// A colour that resolves differently in light and dark appearance.
    init(light: UInt32, dark: UInt32, highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) {
        self.init(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHighContrast = traits.accessibilityContrast == .high
            let hex: UInt32
            switch (isDark, isHighContrast) {
            case (false, false): hex = light
            case (true, false): hex = dark
            case (false, true): hex = highContrastLight ?? light
            case (true, true): hex = highContrastDark ?? dark
            }
            return UIColor(hex: hex)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Spacing and shape

/// 8-point spacing scale (with a 4-point half step).
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Radius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 20
}

enum Metrics {
    /// Minimum touch target recommended by the Human Interface Guidelines.
    static let minimumTouchTarget: CGFloat = 44
    static let primaryButtonHeight: CGFloat = 52
}

// MARK: - Typography helpers

extension View {
    /// Large numeric readouts: rounded, tabular digits, scales with Dynamic Type.
    func formNumeric(_ style: Font.TextStyle = .title2, weight: Font.Weight = .semibold) -> some View {
        font(.system(style, design: .rounded, weight: weight)).monospacedDigit()
    }

    /// Small uppercase-free caption used for secondary labels.
    func formCaption() -> some View {
        font(.footnote).foregroundStyle(Color.formTextSecondary)
    }

    /// Standard page background that extends under the safe areas.
    func formPageBackground() -> some View {
        background(Color.formBackground.ignoresSafeArea())
    }
}
