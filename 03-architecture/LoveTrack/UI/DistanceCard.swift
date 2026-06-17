import SwiftUI

/// 距离卡 + 开启定位开关
/// 对应原型 `.distance-card` 块
public struct DistanceCard: View {
    @Binding public var locationEnabled: Bool
    public let distanceMeters: Int?
    public let partnerName: String
    public let onToggle: ((Bool) -> Void)?

    public init(
        locationEnabled: Binding<Bool>,
        distanceMeters: Int? = 1200,
        partnerName: String = "小月亮",
        onToggle: ((Bool) -> Void)? = nil
    ) {
        self._locationEnabled = locationEnabled
        self.distanceMeters = distanceMeters
        self.partnerName = partnerName
        self.onToggle = onToggle
    }

    public var body: some View {
        HStack {
            distanceInfo
            Spacer()
            BrandToggle(isOn: $locationEnabled, onChange: onToggle)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .fill(Theme.softGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .strokeBorder(Theme.primary.opacity(0.15), lineWidth: 1.5)
        )
        .softShadow(Theme.shadowSm)
    }

    private var distanceInfo: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Theme.primary, Theme.violet],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 52, height: 52)
                    .softShadow(ShadowStyle(color: Theme.primary.opacity(0.3), radius: 16, x: 0, y: 6))
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("我们距离")
                    .font(.system(size: Theme.fontXs, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                if let m = distanceMeters {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(formattedNumber(m))
                            .font(.system(size: Theme.font2xl, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(LinearGradient(
                                colors: [Theme.primary, Theme.violet],
                                startPoint: .leading, endPoint: .trailing
                            ))
                        Text("m")
                            .font(.system(size: Theme.fontMd, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                    }
                } else {
                    Text("--")
                        .font(.system(size: Theme.font2xl, weight: .bold))
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
    }

    private func formattedNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// 自定义 toggle — 粉紫渐变 + 弹跳动画
public struct BrandToggle: View {
    @Binding public var isOn: Bool
    public var onChange: ((Bool) -> Void)?

    public init(isOn: Binding<Bool>, onChange: ((Bool) -> Void)? = nil) {
        self._isOn = isOn
        self.onChange = onChange
    }

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isOn.toggle()
            }
            onChange?(isOn)
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn
                          ? AnyShapeStyle(LinearGradient(
                              colors: [Theme.primary, Color(red: 0.69, green: 0.48, blue: 1.00)],
                              startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color(red: 0.91, green: 0.84, blue: 0.88)))
                    .frame(width: 56, height: 32)
                    .shadow(color: isOn ? Theme.primary.opacity(0.4) : .clear, radius: 14, y: 4)

                Circle()
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .padding(3)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DistanceCardPreview()
}

private struct DistanceCardPreview: View {
    @State private var on = true
    var body: some View {
        VStack(spacing: 20) {
            DistanceCard(locationEnabled: $on, distanceMeters: 1200, partnerName: "小月亮")
            DistanceCard(locationEnabled: .constant(false), distanceMeters: nil, partnerName: "小月亮")
        }
        .padding()
        .background(Theme.bgGradient)
    }
}
