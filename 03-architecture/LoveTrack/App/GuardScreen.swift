import SwiftUI

/// 守护 Tab — 大守护状态 hero + 今日守护数据 + 设置项
public struct GuardScreen: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore

    @State private var guardEnabled: Bool = true
    @State private var notifyOnLowBattery: Bool = true
    @State private var notifyOnSafeZoneExit: Bool = true
    @State private var shareLocationToFamily: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            backgroundGradient
            contentScroll
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            Theme.bg
            LinearGradient(
                colors: [Color(red: 1.00, green: 0.84, blue: 0.91).opacity(0.5),
                         Color.clear,
                         Color(red: 0.91, green: 0.84, blue: 1.00).opacity(0.5)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Content

    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 14) {
                StatusBar()
                guardHero
                todayStats
                guardianTimeline
                settingsSection
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Hero

    private var guardHero: some View {
        ZStack {
            // 装饰光斑
            Circle().fill(Color.white.opacity(0.3)).frame(width: 140, height: 140)
                .blur(radius: 2).offset(x: 130, y: -50)
            Circle().fill(Color.white.opacity(0.18)).frame(width: 100, height: 100)
                .blur(radius: 2).offset(x: -100, y: 60)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(guardEnabled ? "正在守护" : "守护已关闭")
                            .font(.system(size: Theme.fontXl, weight: .bold))
                            .foregroundColor(.white)
                        Text(guardEnabled
                             ? "已守护 16 小时 24 分钟"
                             : "开启后实时共享位置给 TA")
                            .font(.system(size: Theme.fontXs))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Spacer()
                    BrandToggle(isOn: $guardEnabled)
                }

                // 守护双方头像 + 中间爱心连线
                HStack(spacing: 0) {
                    guardAvatar(avatarText: "月", name: "小月亮", isOnline: true)
                    connectorLine
                    guardAvatar(avatarText: "我", name: "我", isOnline: true)
                }
            }
            .padding(20)
        }
        .background(Theme.brandGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous))
        .softShadow(Theme.shadowMd)
    }

    private func guardAvatar(avatarText: String, name: String, isOnline: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 56, height: 56)
                Circle()
                    .fill(LinearGradient(colors: [
                        Color(red: 1.00, green: 0.84, blue: 0.91),
                        Color(red: 0.91, green: 0.84, blue: 1.00)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(avatarText)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    )
                if isOnline {
                    Circle()
                        .fill(Color(red: 0.29, green: 0.87, blue: 0.50))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: 18, y: 18)
                }
            }
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.95))
        }
    }

    private var connectorLine: some View {
        ZStack {
            // 虚线
            Path { p in
                p.move(to: CGPoint(x: 0, y: 28))
                p.addLine(to: CGPoint(x: 80, y: 28))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .foregroundColor(.white.opacity(0.7))
            // 中间爱心
            ZStack {
                Circle().fill(Color.white.opacity(0.95))
                    .frame(width: 32, height: 32)
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .offset(x: 40, y: 28)
        }
        .frame(width: 80, height: 56)
    }

    // MARK: - 今日统计

    private var todayStats: some View {
        HStack(spacing: 10) {
            statCard(systemIcon: "mappin.circle.fill", value: "12", unit: "次", label: "今日位置更新")
            statCard(systemIcon: "shield.checkered", value: "2", unit: "次", label: "安全到家")
            statCard(systemIcon: "clock.fill", value: "16h", unit: "24m", label: "守护时长")
        }
    }

    private func statCard(systemIcon: String, value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [Theme.primary, Theme.violet],
                    startPoint: .leading, endPoint: .trailing
                ))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: Theme.fontLg, weight: .bold))
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.primary, Theme.violet],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textMuted)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1.5)
        )
        .softShadow(Theme.shadowXs)
    }

    // MARK: - 守护时间线

    private var guardianTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.primary, Theme.violet],
                            startPoint: .leading, endPoint: .trailing
                        ))
                    Text("今日守护时间线")
                        .font(.system(size: Theme.fontMd, weight: .semibold))
                }
                Spacer()
                Text("11/22")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }

            VStack(spacing: 0) {
                timelineRow(time: "22:30", systemIcon: "moon.fill", title: "正在守护中", subtitle: "小月亮位置: 万达广场", accent: true)
                Divider().padding(.leading, 50)
                timelineRow(time: "20:15", systemIcon: "bag.fill", title: "到达 万达广场", subtitle: "停留约 25 分钟", accent: false)
                Divider().padding(.leading, 50)
                timelineRow(time: "18:00", systemIcon: "house.fill", title: "已安全到家", subtitle: "系统自动识别", accent: false)
                Divider().padding(.leading, 50)
                timelineRow(time: "14:30", systemIcon: "graduationcap.fill", title: "到达 山大科技园", subtitle: "停留 3 小时 22 分钟", accent: false)
                Divider().padding(.leading, 50)
                timelineRow(time: "08:00", systemIcon: "sun.max.fill", title: "开始今日守护", subtitle: "小月亮出门", accent: false)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1.5)
        )
        .softShadow(Theme.shadowSm)
    }

    private func timelineRow(time: String, systemIcon: String, title: String, subtitle: String, accent: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(time)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent ? Theme.primary : Theme.textMuted)
                    .monospacedDigit()
            }
            .frame(width: 38)

            ZStack {
                Circle()
                    .fill(accent
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Theme.primarySoft))
                    .frame(width: 28, height: 28)
                Image(systemName: systemIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent ? .white : Theme.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.fontSm, weight: accent ? .semibold : .medium))
                    .foregroundColor(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    // MARK: - 设置项

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.primary, Theme.violet],
                            startPoint: .leading, endPoint: .trailing
                        ))
                    Text("守护设置")
                        .font(.system(size: Theme.fontMd, weight: .semibold))
                }
                Spacer()
            }

            VStack(spacing: 0) {
                settingRow(systemIcon: "battery.25", title: "低电提醒", subtitle: "TA 电量 < 20% 时通知你",
                          color: Theme.primarySoft, tint: Theme.primary, isOn: $notifyOnLowBattery)
                Divider().padding(.leading, 50)
                settingRow(systemIcon: "door.left.hand.closed", title: "离开安全区提醒", subtitle: "家、公司等",
                          color: Theme.violetSoft, tint: Theme.violet, isOn: $notifyOnSafeZoneExit)
                Divider().padding(.leading, 50)
                settingRow(systemIcon: "person.2.fill", title: "同步位置给家人", subtitle: "父母可查看 TA 的位置",
                          color: Color(red: 0.92, green: 0.99, blue: 0.96), tint: Theme.success, isOn: $shareLocationToFamily)
                Divider().padding(.leading, 50)
                NavigationLink {
                    EmergencyContactsView()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                                .fill(Color(red: 1.00, green: 0.95, blue: 0.95))
                                .frame(width: 32, height: 32)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(red: 0.94, green: 0.27, blue: 0.27))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("紧急联系人")
                                .font(.system(size: Theme.fontSm, weight: .medium))
                            Text("一键通知 3 位紧急联系人")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.textSubtle)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1.5)
        )
        .softShadow(Theme.shadowSm)
    }

    private func settingRow(systemIcon: String, title: String, subtitle: String,
                            color: Color, tint: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .fill(color)
                    .frame(width: 32, height: 32)
                Image(systemName: systemIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.fontSm, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
            BrandToggle(isOn: isOn)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - 紧急联系人

public struct EmergencyContactsView: View {
    @State private var contacts: [(String, String, String)] = [
        ("妈妈", "138 ****  8866", "M"),
        ("爸爸", "139 ****  5521", "B"),
        ("闺蜜 小雨", "186 ****  0073", "X"),
    ]
    @State private var showAdd = false

    public init() {}

    public var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(contacts.indices, id: \.self) { i in
                        contactRow(name: contacts[i].0, phone: contacts[i].1, avatarText: contacts[i].2)
                    }
                    addButton
                }
                .padding(16)
            }
        }
        .navigationTitle("紧急联系人")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func contactRow(name: String, phone: String, avatarText: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.primarySoft, Theme.violetSoft],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Text(avatarText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                    startPoint: .leading, endPoint: .trailing))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: Theme.fontMd, weight: .semibold))
                Text(phone)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
            Button {
                // TODO: call action
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1.5)
        )
    }

    private var addButton: some View {
        Button {
            showAdd = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("添加紧急联系人")
            }
            .foregroundStyle(LinearGradient(colors: [Theme.primary, Theme.violet],
                                            startPoint: .leading, endPoint: .trailing))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                    .strokeBorder(Theme.primary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            )
        }
    }
}

#Preview {
    NavigationStack {
        GuardScreen()
    }
    .environmentObject(AppSession())
    .environmentObject(RelationshipStore(
        me: User(id: "u1", displayName: "我"),
        realtime: HTTPRealtimeSyncService(userId: "u1")
    ))
}
