import SwiftUI

/// 戳一戳表情互动区 — 5x2 网格
/// 对应原型 `.poke-row` 块
public struct PokeGrid: View {
    public let partnerName: String
    public let onPoke: ((PokeItem) -> Void)?

    public init(partnerName: String = "小月亮", onPoke: ((PokeItem) -> Void)? = nil) {
        self.partnerName = partnerName
        self.onPoke = onPoke
    }

    private let items: [PokeItem] = [
        .init(emoji: "👋", name: "打招呼"),
        .init(emoji: "❤️", name: "想你"),
        .init(emoji: "🍰", name: "点下午茶"),
        .init(emoji: "☕", name: "喝咖啡"),
        .init(emoji: "🌹", name: "送花"),
        .init(emoji: "🍔", name: "吃饭"),
        .init(emoji: "😘", name: "亲亲"),
        .init(emoji: "🎁", name: "送礼"),
        .init(emoji: "⭐", name: "加油"),
        .init(emoji: "😴", name: "晚安"),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.primary, Theme.violet],
                            startPoint: .leading, endPoint: .trailing
                        ))
                    Text("戳一戳\(partnerName)")
                        .font(.system(size: Theme.fontMd, weight: .semibold))
                        .foregroundColor(Theme.text)
                }
                Spacer()
                Text("轻点发送表情")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    PokeButton(item: item) {
                        onPoke?(item)
                    }
                }
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
}

public struct PokeItem: Identifiable, Hashable {
    public let id = UUID()
    public let emoji: String
    public let name: String
    public init(emoji: String, name: String) {
        self.emoji = emoji
        self.name = name
    }
}

private struct PokeButton: View {
    let item: PokeItem
    let action: () -> Void

    @State private var isBumping = false
    @State private var bursts: [BurstParticle] = []

    var body: some View {
        Button(action: trigger) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 1.00, green: 0.96, blue: 0.98), Theme.violetSoft],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .aspectRatio(1, contentMode: .fit)
                    .softShadow(Theme.shadowXs)

                Text(item.emoji)
                    .font(.system(size: 28))
                    .scaleEffect(isBumping ? 1.0 : 0.8)

                ForEach(bursts) { p in
                    Image(systemName: p.systemIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.primary, Theme.violet],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .offset(x: p.tx, y: p.ty)
                        .opacity(p.opacity)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isBumping ? 1.0 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isBumping)
    }

    private func trigger() {
        isBumping = true
        action()

        // 弹跳结束
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isBumping = false
        }

        // 粒子爆裂 — 用 SF Symbol 替换 emoji
        let burstIcons = ["sparkle", "heart.fill", "star.fill", "heart.circle.fill"]
        for i in 0..<4 {
            let p = BurstParticle(
                id: UUID(),
                systemIcon: burstIcons[i],
                tx: CGFloat.random(in: -25...25),
                ty: CGFloat.random(in: -45 ... -25),
                opacity: 1
            )
            bursts.append(p)
            withAnimation(.easeOut(duration: 0.8)) {
                if let idx = bursts.firstIndex(where: { $0.id == p.id }) {
                    bursts[idx].ty -= 30
                    bursts[idx].opacity = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                bursts.removeAll { $0.id == p.id }
            }
        }
    }
}

private struct BurstParticle: Identifiable {
    let id: UUID
    let systemIcon: String
    var tx: CGFloat
    var ty: CGFloat
    var opacity: Double
}

#Preview {
    PokeGrid(partnerName: "小月亮") { item in
        Log.info("PokeGrid", "poke: \(item.name)")
    }
    .padding()
    .background(Theme.bgGradient)
}
