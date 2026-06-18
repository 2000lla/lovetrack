import SwiftUI
import CoreLocation

/// 配对屏幕（创建邀请码 / 输入邀请码）。
///
/// Day 1 demo：用户首次打开 App → 看到这个屏幕
///   - A 点"创建邀请码" → 拿到 6 位码
///   - B 点"输入邀请码" → 输入 A 的码 → 双方绑定
///
/// 未配对时也显示 mini 地图（仅自己位置），让用户验证 app 真的在定位
public struct PairScreen: View {
    @EnvironmentObject var session: AppSession
    @State private var mode: Mode = .home
    @State private var inviteCode: String = ""
    @State private var inputCode: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    enum Mode {
        case home          // 默认：两个按钮
        case create        // 创建邀请码后展示
        case join          // 输入邀请码
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.36, blue: 0.61),
                        Color(red: 0.55, green: 0.36, blue: 0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                content
                    .padding(24)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .home: homeView
        case .create: createView
        case .join: joinView
        }
    }

    // MARK: - Home

    private var homeView: some View {
        VStack(spacing: 20) {
            // 顶部标题
            VStack(spacing: 8) {
                Text("💕")
                    .font(.system(size: 64))
                Text("LoveTrack")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("和 TA 保持连接")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.top, 16)

            // ⬇️ mini 地图: 未配对时也能验证 app 真在定位
            if AAMapBootstrap.isAvailable, let me = session.lastLocation {
                AAMapView(
                    center: me.coordinate,
                    partner: nil,
                    me: MapPerson(
                        id: session.currentUser.id,
                        name: "我",
                        coordinate: me.coordinate
                    ),
                    zoomLevel: 15
                )
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                )
                .softShadow(Theme.shadowMd)
                .padding(.horizontal, 8)
            }

            Spacer()

            // 底部按钮
            VStack(spacing: 16) {
                Button {
                    Task { await createInvite() }
                } label: {
                    HStack {
                        Image(systemName: "qrcode")
                        Text("创建邀请码")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .foregroundStyle(Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    mode = .join
                } label: {
                    HStack {
                        Image(systemName: "keyboard")
                        Text("输入邀请码")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white, lineWidth: 2)
                    )
                }

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.top, 8)
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(.top, 8)
                }
            }

            Spacer()
        }
    }

    // MARK: - Create

    private var createView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🎉")
                .font(.system(size: 80))

            Text("你的邀请码")
                .font(.title2)
                .foregroundStyle(.white)

            Text(inviteCode)
                .font(.system(size: 56, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.vertical, 20)
                .padding(.horizontal, 32)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white, lineWidth: 3)
                )

            Text("把这个码发给 TA\n10 分钟内有效")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Button {
                session.completePairing()
            } label: {
                Text("进入 App")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .foregroundStyle(Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Button("返回") {
                mode = .home
                inviteCode = ""
            }
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Join

    private var joinView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🔗")
                .font(.system(size: 80))

            Text("输入 TA 的邀请码")
                .font(.title2)
                .foregroundStyle(.white)

            TextField("6 位邀请码", text: $inputCode)
                .font(.system(size: 32, weight: .heavy, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(Color.white)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onChange(of: inputCode) { new in
                    inputCode = String(new.prefix(6)).uppercased()
                }

            Spacer()

            Button {
                Task { await joinWithCode() }
            } label: {
                Text("绑定")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .foregroundStyle(Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(inputCode.count != 6 || isLoading)

            if isLoading {
                ProgressView().tint(.white)
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            Button("返回") { mode = .home }
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Actions

    private func createInvite() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // DEBUG 和 RELEASE 都走后端真配对 —— 两台真机测试时需要 server 知道谁跟谁配对了
        // 才能在 location_update 时把 partner_location 推给对方
        do {
            let code = try await session.relationshipStore.generatePairCode()
            inviteCode = code
            mode = .create
            print("[PairScreen] ✅ 创建邀请码成功: \(code)")
        } catch {
            errorMessage = "创建失败: \(error.localizedDescription)"
            print("[PairScreen] ❌ 创建邀请码失败: \(error)")
        }
    }

    private func joinWithCode() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // DEBUG 和 RELEASE 都走后端真绑定 —— 输任意 6 位并不会通过，
        // 后端只接受由 /bind 生成的真实邀请码
        do {
            try await session.relationshipStore.acceptPairCode(inputCode)
            session.completePairing()
            print("[PairScreen] ✅ 绑定成功: code=\(inputCode)")
        } catch {
            errorMessage = "绑定失败: \(error.localizedDescription)"
            print("[PairScreen] ❌ 绑定失败: \(error)")
        }
    }
}