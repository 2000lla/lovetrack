import SwiftUI

/// 通用 iOS 状态栏占位（时间 + 信号 + WiFi + 96% 电池）
/// 原型里所有页面顶部都有这一行
public struct StatusBar: View {
    public init() {}
    public var body: some View {
        HStack {
            Text("22:55")
                .font(.system(size: Theme.fontSm, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12))
                Image(systemName: "wifi")
                    .font(.system(size: 12))
                Text("96")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    StatusBar()
        .padding()
        .background(Theme.bg)
}
