//
//  AppTheme.swift
//  AssignementRadar
//
//  Created for Assignment Radar Dashboard UI Upgrade & Design System.
//

import SwiftUI
import UIKit

/// Available appearance themes for Assignment Radar.
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System Default"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    /// Returns the corresponding SwiftUI ColorScheme, or nil for system default.
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    /// Icon representing the theme.
    var iconName: String {
        switch self {
        case .system:
            return "circle.righthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }
}

// MARK: - Color Hex Initializer & Dynamic Color Helper

extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Creates a dynamic Color that adapts between Light (Sage & Ivory) and Dark (Olive Night) palettes.
    static func dynamicColor(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(Color(hex: dark))
            } else {
                return UIColor(Color(hex: light))
            }
        })
    }
}

// MARK: - Semantic Design System Tokens

/// Design System Color Tokens:
/// - Dark Theme: Olive Night (#20251B, #303829, #394332, #E6E5D8, #B5B8AA, #A9B99A)
/// - Light Theme: Sage & Ivory (#F5F4EC, #FFFFFF, #20251B, #73776C, #526548, #E6EEE0)
struct ThemeColors {
    // Backgrounds & Surfaces
    static let mainBackground = Color.dynamicColor(light: "#F5F4EC", dark: "#20251B")
    static let cardBackground = Color.dynamicColor(light: "#FFFFFF", dark: "#303829")
    static let secondarySurface = Color.dynamicColor(light: "#E6EEE0", dark: "#394332")
    static let softAccentSurface = Color.dynamicColor(light: "#E6EEE0", dark: "#394332")

    // Typography
    static let primaryText = Color.dynamicColor(light: "#20251B", dark: "#E6E5D8")
    static let secondaryText = Color.dynamicColor(light: "#73776C", dark: "#B5B8AA")

    // Brand & Accents
    static let primaryAccent = Color.dynamicColor(light: "#526548", dark: "#A9B99A")
    static let divider = Color.dynamicColor(light: "#E3E5DC", dark: "#424C3B")

    // Status Semantics
    static let warning = Color.dynamicColor(light: "#B88230", dark: "#D6A45E")
    static let warningSurface = Color.dynamicColor(light: "#F7E8D3", dark: "#3E3424")

    static let overdue = Color.dynamicColor(light: "#C63F33", dark: "#E06C60")
    static let overdueSurface = Color.dynamicColor(light: "#FDF0EE", dark: "#3B2524")

    static let exam = Color.dynamicColor(light: "#7E57C2", dark: "#B39DDB")
    static let examSurface = Color.dynamicColor(light: "#F3EDF9", dark: "#362C42")

    static let success = Color.dynamicColor(light: "#3E7B44", dark: "#81C784")
    static let successSurface = Color.dynamicColor(light: "#EAF5EA", dark: "#263828")
}

extension Color {
    static let theme = ThemeColors.self
}

// MARK: - View Modifiers for Consistent Design System

struct CardBackgroundModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(Color.theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.theme.divider, lineWidth: 0.75)
            )
    }
}

extension View {
    func themeCard(cornerRadius: CGFloat = 12) -> some View {
        self.modifier(CardBackgroundModifier(cornerRadius: cornerRadius))
    }
}
