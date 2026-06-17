import SwiftUI

/// 顶部伴侣信息卡 — 粉紫渐变 hero
/// 对应原型 `.partner-hero` 块
public struct PartnerHero: View {
    public let name: String
    public let avatar: String          // emoji 或 SF symbol
    public let distanceKm: Double?
    public let isOnline: Bool
    public let deviceModel: String     // e.g. "iPhone 15 Pro"
    public let batteryPercent: Int?    // 0-100
    public let networkLabel: String    // e.g. "5G · WiFi"

    public init(
        name: String,
        avatar: String = "👧🏻",
        distanceKm: Double? = nil,
        isOnline: Bool = true,
        deviceModel: String = "iPhone 15 Pro",
        batteryPercent: Int? = 78,
        networkLabel: String = "5G · WiFi"
    ) {
        self.name = name
        self.avatar = avatar
        self.distanceKm = distanceKm
        self.isOnline = isOnline
        self.deviceModel = deviceModel
        self.batteryPercent = batteryPercent
        self.networkLabel = networkLabel
    }

    public var body: some View {
        ZStack {
            // 装饰光斑
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 120, height: 120)
                .blur(radius: 2)
                .offset(x: 130, y: -40)
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 80, height: 80)
                .blur(radius: 2)
                .offset(x: 0, y: 60)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    avatarView
                    infoView
                    Spacer()
                    if isOnline {
                        onlineBadge
                    }
                }
                metaRow
            }
            .padding(18)
        }
        .background(Theme.brandGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous))
        .softShadow(Theme.shadowMd)
    }

    // MARK: - Subviews

    private var avatarView: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.6),
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(0))
                .animation(.linear(duration: 18).repeatForever(autoreverses: false),
                           value: UUID())
            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 64, height: 64)
                .overlay(
                    Circle()
                        .fill(LinearGradient(colors: [
                            Color(red: 1.00, green: 0.84, blue: 0.91),
                            Color(red: 0.91, green: 0.84, blue: 1.00)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 58, height: 58)
                        .overlay(
                            Text(avatar)
                                .font(.system(size: 26))
                        )
                )
        }
    }

    private var infoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: Theme.fontLg, weight: .bold))
                    .foregroundColor(.white)
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
            }
            distanceLabel
        }
    }

    @ViewBuilder
    private var distanceLabel: some View {
        if let km = distanceKm {
            HStack(spacing: 4) {
                Text("距你")
                    .font(.system(size: Theme.fontXs))
                    .foregroundColor(.white.opacity(0.95))
                Text(String(format: "%.1f", km))
                    .font(.system(size: Theme.fontMd, weight: .bold))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text("km")
                    .font(.system(size: Theme.fontXs))
                    .foregroundColor(.white.opacity(0.95))
                Text("·")
                    .foregroundColor(.white.opacity(0.7))
                Text(walkingMinutes(km: km))
                    .font(.system(size: Theme.fontXs))
                    .foregroundColor(.white.opacity(0.95))
            }
        } else {
            Text("正在获取位置…")
                .font(.system(size: Theme.fontXs))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private var onlineBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(red: 0.29, green: 0.87, blue: 0.50))
                .frame(width: 6, height: 6)
                .shadow(color: Color(red: 0.29, green: 0.87, blue: 0.50), radius: 3)
            Text("在线")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.white.opacity(0.25))
        )
    }

    private var metaRow: some View {
        HStack(spacing: 16) {
            metaItem(systemIcon: "iphone", text: deviceModel)
            if let battery = batteryPercent {
                metaItem(systemIcon: nil, text: nil, customView: AnyView(batteryView(percent: battery)))
                Text("\(battery)%")
                    .font(.system(size: Theme.fontXs, weight: .semibold))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .offset(x: -8)
            }
            metaItem(systemIcon: "antenna.radiowaves.left.and.right", text: networkLabel)
        }
        .padding(.top, 14)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(height: 1)
                .padding(.top, 6),
            alignment: .top
        )
    }

    private func metaItem(systemIcon: String?, text: String?, customView: AnyView? = nil) -> some View {
        HStack(spacing: 6) {
            if let systemIcon = systemIcon {
                Image(systemName: systemIcon)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.95))
            }
            if let customView = customView {
                customView
            }
            if let text = text {
                Text(text)
                    .font(.system(size: Theme.fontXs))
                    .foregroundColor(.white.opacity(0.95))
            }
        }
    }

    private func batteryView(percent: Int) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                .frame(width: 22, height: 10)
                .overlay(
                    GeometryReader { geo in
                        HStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.95))
                                .frame(width: geo.size.width * CGFloat(percent) / 100 - 2, height: 6)
                                .cornerRadius(1)
                            Spacer(minLength: 0)
                        }
                        .padding(1)
                    }
                )
            // 电池正极凸起
            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 2, height: 5)
                .offset(x: -1)
        }
    }

    private func walkingMinutes(km: Double) -> String {
        let minutes = Int((km * 1000 / 80).rounded()) // 80m/分钟 步行
        if minutes < 1 { return "<1 分钟" }
        if minutes < 60 { return "步行 \(minutes) 分钟" }
        return "步行 \(minutes / 60) 小时"
    }
}

#Preview {
    PartnerHero(
        name: "小月亮",
        avatar: "👧🏻",
        distanceKm: 1.2,
        isOnline: true,
        deviceModel: "iPhone 15 Pro",
        batteryPercent: 78,
        networkLabel: "5G · WiFi"
    )
    .padding()
    .background(Theme.bgGradient)
}
