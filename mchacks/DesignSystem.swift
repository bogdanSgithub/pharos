//
//  DesignSystem.swift
//  mchacks
//
//  Unified design system for CompanionCar
//

import SwiftUI

// MARK: - App Colors (Waze Dark Theme)
struct AppColors {
    // Primary accent - Waze Cyan/Teal
    static let accent = Color(hex: "34D1D1")
    static let accentLight = Color(hex: "5CE1E1")
    static let accentDark = Color(hex: "29A3A3")

    // Success - Green
    static let success = Color(hex: "4CD964")
    static let successLight = Color(hex: "6EE77A")

    // Warning - Waze Yellow
    static let warning = Color(hex: "FFD60A")
    static let warningLight = Color(hex: "FFE066")

    // Error - Red
    static let error = Color(hex: "FF3B30")
    static let errorLight = Color(hex: "FF6961")

    // Backgrounds (Waze Dark Gray)
    static let backgroundPrimary = Color(hex: "202124")
    static let backgroundSecondary = Color(hex: "202124")
    static let backgroundCard = Color(hex: "303134")
    static let backgroundElevated = Color(hex: "3C4043")

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "8E8E93")
    static let textTertiary = Color(hex: "636366")
    static let textMuted = Color(hex: "48484A")

    // Borders/Dividers
    static let border = Color(hex: "38383A")
    static let borderLight = Color(hex: "2C2C2E")
}

// MARK: - Hex Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Common Styles
struct AppCard: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(AppColors.border, lineWidth: 1)
            )
    }
}

struct AppButton: ViewModifier {
    var color: Color = AppColors.accent
    var isSecondary: Bool = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(isSecondary ? color : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSecondary
                    ? AnyShapeStyle(color.opacity(0.15))
                    : AnyShapeStyle(color)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func appCard(padding: CGFloat = 20) -> some View {
        modifier(AppCard(padding: padding))
    }

    func appButton(color: Color = AppColors.accent, isSecondary: Bool = false) -> some View {
        modifier(AppButton(color: color, isSecondary: isSecondary))
    }
}

// MARK: - Gradient Definitions
struct AppGradients {
    static let accentGradient = LinearGradient(
        colors: [AppColors.accent, AppColors.accentLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let successGradient = LinearGradient(
        colors: [AppColors.success, AppColors.successLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [AppColors.backgroundPrimary, AppColors.backgroundSecondary],
        startPoint: .top,
        endPoint: .bottom
    )
}
