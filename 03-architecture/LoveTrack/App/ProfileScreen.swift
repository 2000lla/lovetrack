import SwiftUI

/// 我的 Tab — 个人资料 hero + 守护数据 + 设置 + 会员入口
public struct ProfileScreen: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore

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
                profileHero
                statsRow
                vipCard
                settingsGroup
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Profile hero

    private var profileHero: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.3)).frame(width: 160, height: 160)
                .blur(radius: 2).offset(x: 130, y: -50)
            Circle().fill(Color.white.opacity(0.18)).frame(width: 120, height: 120)
                .blur(radius: 2).offset(x: -120, y: 60)

            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    Spacer()
                    Button {} label: {
                        Image(systemName: "qrcode")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.25)))
                    }
                    Button {} label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.25)))
                    }
                }
                .padding(.top, 4)

                ZStack {
                    Circle().fill(Color.white.opacity(0.5))
                        .frame(width: 84, height: 84)
                    Circle().fill(LinearGradient(colors: [
                        Color(red: 1.00, green: 0.84, blue: 0.91),
                        Color(red: 0.91, green: 0.84, blue: 1.00)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 76, height: 76)
                    .overlay(Text("我").font(.system(size: 28, weight: .bold)).foregroundColor(.white))
                }

                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(session.currentUser.displayName)
                            .font(.system(size: Theme.fontXl, weight: .bold))
                            .foregroundColor(.white)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    Text("ID: \(String(session.currentUser.id.prefix(8)))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }

                HStack(spacing: 16) {
                    relationshipPill(systemIcon: "heart.fill", text: "在一起 142 天")
                    relationshipPill(systemIcon: "shield.lefthalf.filled", text: "已守护 16h")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .background(Theme.brandGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous))
        .softShadow(Theme.shadowMd)
    }

    private func relationshipPill(systemIcon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemIcon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.25)))
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 10) {
            statItem(systemIcon: "mappin.and.ellipse", value: "1,234", label: "位置更新")
            statItem(systemIcon: "envelope.fill", value: "567", label: "发送戳一戳")
            statItem(systemIcon: "shield.fill", value: "42", label: "守护天数")
            statItem(systemIcon: "gift.fill", value: "18", label: "纪念日")
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

    private func statItem(systemIcon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [Theme.primary, Theme.violet],
                    startPoint: .leading, endPoint: .trailing
                ))
            Text(value)
                .font(.system(size: Theme.fontMd, weight: .bold))
                .foregroundColor(Theme.text)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - VIP

    private var vipCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 1.00, green: 0.84, blue: 0.66),
                                                  Color(red: 0.95, green: 0.59, blue: 0.27)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: "crown.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("开通 VIP 守护")
                        .font(.system(size: Theme.fontMd, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("PRO")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                         startPoint: .leading, endPoint: .trailing))
                        )
                        .foregroundColor(.white)
                }
                Text("解锁 30 天轨迹回放、无限守护、家人地图")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSubtle)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.00, green: 0.97, blue: 0.88),
                                              Color(red: 1.00, green: 0.92, blue: 0.96)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .strokeBorder(Color(red: 0.95, green: 0.78, blue: 0.50).opacity(0.4), lineWidth: 1.5)
        )
        .softShadow(Theme.shadowSm)
    }

    // MARK: - Settings group

    private var settingsGroup: some View {
        VStack(spacing: 0) {
            settingsRow(systemIcon: "shield.fill", title: "守护设置", subtitle: "位置、低电、安全区",
                       color: Theme.violetSoft, tint: Theme.violet)
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "bell.fill", title: "通知提醒", subtitle: "消息、戳一戳、电量",
                       color: Theme.primarySoft, tint: Theme.primary)
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "lock.fill", title: "隐私与权限", subtitle: "位置、通讯录、轨迹",
                       color: Color(red: 0.92, green: 0.99, blue: 0.96), tint: Theme.success)
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "paintbrush.fill", title: "主题外观", subtitle: "粉紫 / 星空 / 森系",
                       color: Color(red: 0.95, green: 0.91, blue: 1.00), tint: Color(red: 0.55, green: 0.36, blue: 0.96))
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "heart.fill", title: "邀请好友", subtitle: "双方各得 7 天 VIP",
                       color: Color(red: 1.00, green: 0.94, blue: 0.88), tint: Color(red: 0.95, green: 0.59, blue: 0.27))
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "questionmark.circle.fill", title: "帮助与反馈", subtitle: "常见问题、联系客服",
                       color: Theme.surface2, tint: Theme.textMuted)
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "info.circle.fill", title: "关于爱合", subtitle: "v0.1.0 · 用科技守护亲密",
                       color: Theme.surface2, tint: Theme.textMuted)
        }
        .padding(.horizontal, 14)
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

    private func settingsRow(systemIcon: String, title: String, subtitle: String,
                             color: Color, tint: Color) -> some View {
        Button(action: {}) {
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
                        .foregroundColor(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSubtle)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileScreen()
        .environmentObject(AppSession())
        .environmentObject(RelationshipStore(
            me: User(id: "u1", displayName: "我"),
            realtime: HTTPRealtimeSyncService(userId: "u1")
        ))
}
