// /AdlerCRM/Helpers/AppTheme.swift  08/04/2026 06:00:00 EDT
import SwiftUI
import UIKit

// MARK: - Adaptive Color Helper

extension Color {
    /// Creates a color that automatically adapts to light/dark mode
    init(light: String, dark: String) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: CGFloat
        switch hex.count {
        case 6:
            r = CGFloat((int >> 16) & 0xFF) / 255
            g = CGFloat((int >> 8) & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - App Theme

/// Centralized color definitions with light/dark mode support.
/// Usage: Color.theme.background, Color.theme.text, etc.
///
/// Accent colors (green, gold, red) remain constant across modes.
/// Neutral colors (backgrounds, text, borders) adapt automatically.
struct AppTheme {

    // ── Backgrounds ────────────────────────────────────────────────────
    /// Main screen background
    let background = Color(light: "f5f4f0", dark: "0f1117")
    /// Card/surface background (lists, cards, sheets)
    let surface = Color(light: "ffffff", dark: "1a1b23")
    /// Grouped/inset background
    let surfaceSecondary = Color(light: "f5f4f0", dark: "12131a")
    /// Input field background
    let inputBackground = Color(light: "ffffff", dark: "22232e")

    // ── Text ───────────────────────────────────────────────────────────
    /// Primary text
    let text = Color(light: "0f1117", dark: "f0efe8")
    /// Secondary/muted text
    let textSecondary = Color(light: "7a7f94", dark: "9a9eb2")
    /// Tertiary/hint text
    let textTertiary = Color(light: "7a7f94", dark: "6b6f82")

    // ── Borders ────────────────────────────────────────────────────────
    /// Default border
    let border = Color(light: "e2dfd6", dark: "2a2c38")
    /// Separator lines
    let separator = Color(light: "e2dfd6", dark: "2a2c38")

    // ── Accents (constant across modes) ────────────────────────────────
    /// Primary green
    let green = Color(hex: "2d6a4f")
    /// Gold/amber
    let gold = Color(hex: "c8893a")
    /// Error red
    let red = Color(hex: "c1121f")
    /// Dark (used for dark buttons/badges)
    let dark = Color(light: "0f1117", dark: "f0efe8")

    // ── Navigation Bar ─────────────────────────────────────────────────
    /// Tab bar / toolbar background
    let toolbarBackground = Color(light: "ffffff", dark: "16171f")
}

// MARK: - Color Extension for Theme Access

extension Color {
    /// Access adaptive theme colors: Color.theme.background, Color.theme.text, etc.
    static let theme = AppTheme()
}
