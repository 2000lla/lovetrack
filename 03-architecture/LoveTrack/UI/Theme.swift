import SwiftUI

/// 爱合 App 设计 token — 粉紫渐变 + 圆角 + 表情贴纸
/// 对标 HTML 原型 02-ui-prototype/love-location.html 的 `:root` 变量
public enum Theme {

    // MARK: - 品牌色

    public static let primary       = Color(red: 1.00, green: 0.36, blue: 0.61)  // #ff5b9c 玫瑰粉 600
    public static let primaryHover  = Color(red: 0.91, green: 0.25, blue: 0.50)  // #e7407f
    public static let primarySoft   = Color(red: 1.00, green: 0.94, blue: 0.96)  // #fff0f6

    public static let violet        = Color(red: 0.55, green: 0.36, blue: 0.96)  // #8b5cf6 紫罗兰 500
    public static let violetSoft    = Color(red: 0.95, green: 0.93, blue: 1.00)  // #f3edff
    public static let violetHover   = Color(red: 0.49, green: 0.23, blue: 0.93)  // #7c3aed

    public static let coral         = Color(red: 1.00, green: 0.56, blue: 0.64)  // #ff8fa3
    public static let peach         = Color(red: 1.00, green: 0.84, blue: 0.66)  // #ffd5a8

    // MARK: - 中性色

    public static let bg            = Color(red: 0.996, green: 0.969, blue: 0.984) // #fef7fb
    public static let surface       = Color.white
    public static let surface2      = Color(red: 1.00, green: 0.96, blue: 0.98)   // #fff5fa
    public static let border        = Color(red: 0.953, green: 0.882, blue: 0.925) // #f3e1ec

    public static let text          = Color(red: 0.165, green: 0.078, blue: 0.188) // #2a1430
    public static let textMuted     = Color(red: 0.541, green: 0.486, blue: 0.541) // #8a7c8a
    public static let textSubtle    = Color(red: 0.710, green: 0.659, blue: 0.722) // #b5a8b8

    // MARK: - 状态

    public static let success       = Color(red: 0.13, green: 0.77, blue: 0.37)  // #22c55e
    public static let warning       = Color(red: 0.96, green: 0.62, blue: 0.04)  // #f59e0b
    public static let danger        = Color(red: 0.94, green: 0.27, blue: 0.27)  // #ef4444

    // MARK: - 渐变

    public static let brandGradient = LinearGradient(
        colors: [primary, Color(red: 1.00, green: 0.49, blue: 0.69), Color(red: 0.69, green: 0.48, blue: 1.00)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )  // #ff5b9c → #ff7eaf → #b07aff

    public static let softGradient = LinearGradient(
        colors: [Color(red: 1.00, green: 0.96, blue: 0.98), violetSoft],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    public static let bgGradient: LinearGradient = {
        LinearGradient(
            stops: [
                .init(color: Color(red: 1.00, green: 0.84, blue: 0.91).opacity(0.6), location: 0.0),
                .init(color: Color(red: 0.91, green: 0.84, blue: 1.00).opacity(0.5), location: 1.0),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }()

    // MARK: - 圆角

    public static let radiusSm:  CGFloat = 8
    public static let radiusMd:  CGFloat = 12
    public static let radiusLg:  CGFloat = 16
    public static let radiusXl:  CGFloat = 22
    public static let radius2xl: CGFloat = 28
    public static let radiusPill: CGFloat = 9999

    // MARK: - 阴影

    public static let shadowXs = ShadowStyle(color: primary.opacity(0.06), radius: 2, x: 0, y: 1)
    public static let shadowSm = ShadowStyle(color: primary.opacity(0.08), radius: 8, x: 0, y: 2)
    public static let shadowMd = ShadowStyle(color: primary.opacity(0.12), radius: 24, x: 0, y: 8)
    public static let shadowLg = ShadowStyle(color: primary.opacity(0.18), radius: 48, x: 0, y: 18)

    // MARK: - 字体

    public static let fontXs:  CGFloat = 12
    public static let fontSm:  CGFloat = 13
    public static let fontBase: CGFloat = 14
    public static let fontMd:  CGFloat = 15
    public static let fontLg:  CGFloat = 16
    public static let fontXl:  CGFloat = 18
    public static let font2xl: CGFloat = 22
    public static let font3xl: CGFloat = 28
    public static let font4xl: CGFloat = 36
}

public struct ShadowStyle {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat
}

extension View {
    public func softShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
