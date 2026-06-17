import SwiftUI

/// 仿高德地图的迷你地图卡 — 模拟济南历城区，含万达广场 / 山大科技园 POI + 对方位置
/// 对应原型 `.map-card` 块
public struct MiniMap: View {
    public let partnerName: String
    public let partnerAvatar: String
    public let lastUpdatedText: String
    public let onPOITap: ((String) -> Void)?

    public init(
        partnerName: String = "小月亮",
        partnerAvatar: String = "👧🏻",
        lastUpdatedText: String = "1 分钟前更新",
        onPOITap: ((String) -> Void)? = nil
    ) {
        self.partnerName = partnerName
        self.partnerAvatar = partnerAvatar
        self.lastUpdatedText = lastUpdatedText
        self.onPOITap = onPOITap
    }

    public var body: some View {
        ZStack {
            // 地图底图
            MapCanvas()
            // 浮动控件
            overlay
            compass
            mapControlButtons
        }
        .frame(height: 320)
        .background(
            LinearGradient(colors: [
                Color(red: 0.91, green: 0.96, blue: 0.91),
                Color(red: 0.84, green: 0.91, blue: 0.84)
            ], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous))
        .softShadow(Theme.shadowMd)
    }

    // MARK: - Subviews

    private var overlay: some View {
        VStack {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.primary)
                        .frame(width: 8, height: 8)
                        .shadow(color: Theme.primary.opacity(0.4), radius: 4)
                    Text("\(partnerName) · \(lastUpdatedText)")
                        .font(.system(size: Theme.fontXs, weight: .semibold))
                        .foregroundColor(Theme.text)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                        .fill(Color.white.opacity(0.95))
                )
                .softShadow(Theme.shadowSm)
                Spacer()
            }
            Spacer()
        }
        .padding(12)
    }

    private var compass: some View {
        VStack {
            HStack {
                Spacer()
                Text("N")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.violet)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(Color.white.opacity(0.95))
                    )
                    .softShadow(Theme.shadowSm)
            }
            Spacer()
        }
        .padding(12)
    }

    private var mapControlButtons: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    MapFabButton(icon: "plus")
                    MapFabButton(icon: "minus")
                    MapFabButton(icon: "scope")
                }
            }
        }
        .padding(12)
    }
}

// MARK: - 地图画布

private struct MapCanvas: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 360
            let h = size.height
            let w = size.width

            // 网格
            let gridStep: CGFloat = 20 * scale
            var gridPath = Path()
            var x: CGFloat = 0
            while x < w {
                gridPath.move(to: CGPoint(x: x, y: 0))
                gridPath.addLine(to: CGPoint(x: x, y: h))
                x += gridStep
            }
            var y: CGFloat = 0
            while y < h {
                gridPath.move(to: CGPoint(x: 0, y: y))
                gridPath.addLine(to: CGPoint(x: w, y: y))
                y += gridStep
            }
            context.stroke(gridPath, with: .color(Theme.violet.opacity(0.06)), lineWidth: 0.5)

            // 河流（小清河）
            var river = Path()
            river.move(to: CGPoint(x: 0, y: 220 * scale))
            river.addQuadCurve(to: CGPoint(x: 120 * scale, y: 230 * scale),
                               control: CGPoint(x: 60 * scale, y: 200 * scale))
            river.addQuadCurve(to: CGPoint(x: 240 * scale, y: 240 * scale),
                               control: CGPoint(x: 180 * scale, y: 235 * scale))
            river.addQuadCurve(to: CGPoint(x: w, y: 230 * scale),
                               control: CGPoint(x: 300 * scale, y: 245 * scale))
            river.addLine(to: CGPoint(x: w, y: 250 * scale))
            river.addQuadCurve(to: CGPoint(x: 240 * scale, y: 260 * scale),
                               control: CGPoint(x: 300 * scale, y: 265 * scale))
            river.addQuadCurve(to: CGPoint(x: 120 * scale, y: 250 * scale),
                               control: CGPoint(x: 180 * scale, y: 255 * scale))
            river.addQuadCurve(to: CGPoint(x: 0, y: 240 * scale),
                               control: CGPoint(x: 60 * scale, y: 220 * scale))
            river.closeSubpath()
            context.fill(river, with: .color(Color(red: 0.83, green: 0.91, blue: 0.97).opacity(0.85)))

            // 公园
            for (cx, cy, rx, ry, label, labelX, labelY) in [
                (80.0, 100.0, 40.0, 28.0, "历城公园", 62.0, 103.0),
                (290.0, 290.0, 50.0, 32.0, "华山湖湿地", 266.0, 294.0)
            ] {
                let park = Path(ellipseIn: CGRect(
                    x: (cx - rx) * scale, y: (cy - ry) * scale,
                    width: rx * 2 * scale, height: ry * 2 * scale
                ))
                context.fill(park, with: .color(Color(red: 0.78, green: 0.90, blue: 0.78).opacity(0.7)))
                context.draw(Text(label)
                    .font(.system(size: 9 * scale, weight: .medium))
                    .foregroundColor(Color(red: 0.35, green: 0.54, blue: 0.35)),
                             at: CGPoint(x: labelX * scale, y: labelY * scale))
            }

            // 主路（黄色）
            var mainRoad = Path()
            mainRoad.move(to: CGPoint(x: 0, y: 180 * scale))
            mainRoad.addLine(to: CGPoint(x: w, y: 180 * scale))
            context.stroke(mainRoad, with: .color(Color(red: 1.00, green: 0.97, blue: 0.77)), lineWidth: 8 * scale)
            var mainRoadDash = Path()
            mainRoadDash.move(to: CGPoint(x: 0, y: 180 * scale))
            mainRoadDash.addLine(to: CGPoint(x: w, y: 180 * scale))
            context.stroke(mainRoadDash, with: .color(Color(red: 1.00, green: 0.97, blue: 0.77).opacity(0.6)),
                           style: StrokeStyle(lineWidth: 2 * scale, dash: [6 * scale, 4 * scale]))

            // 主路竖向
            var mainRoadV = Path()
            mainRoadV.move(to: CGPoint(x: 180 * scale, y: 0))
            mainRoadV.addLine(to: CGPoint(x: 180 * scale, y: h))
            context.stroke(mainRoadV, with: .color(Color(red: 1.00, green: 0.97, blue: 0.77)), lineWidth: 6 * scale)

            // 二级道路（白色）
            for (sx, sy, ex, ey, lw) in [
                (60.0, 0.0, 60.0, 360.0, 3.0),
                (300.0, 0.0, 300.0, 360.0, 3.0),
                (0.0, 80.0, 360.0, 80.0, 3.0),
                (0.0, 300.0, 360.0, 300.0, 2.5)
            ] {
                var road = Path()
                road.move(to: CGPoint(x: sx * scale, y: sy * scale))
                road.addLine(to: CGPoint(x: ex * scale, y: ey * scale))
                context.stroke(road, with: .color(.white.opacity(0.85)), lineWidth: lw * scale)
            }

            // 建筑块
            for (bx, by, bw, bh) in [
                (100.0, 140.0, 50.0, 30.0),
                (210.0, 100.0, 40.0, 50.0),
                (220.0, 200.0, 55.0, 40.0),
                (100.0, 250.0, 40.0, 35.0)
            ] {
                let bld = Path(roundedRect: CGRect(
                    x: bx * scale, y: by * scale,
                    width: bw * scale, height: bh * scale
                ), cornerRadius: 4 * scale)
                context.fill(bld, with: .color(Color(red: 0.96, green: 0.90, blue: 0.85).opacity(0.85)))
            }

            // POI 1: 万达广场
            drawPOI(context: context, x: 140, y: 165, label: "万达广场",
                    color: Theme.primary, systemIcon: "bag.fill", scale: scale)
            // POI 2: 山大科技产业园
            drawPOI(context: context, x: 245, y: 145, label: "山大科技产业园",
                    color: Theme.violet, systemIcon: "graduationcap.fill", scale: scale)

            // 路线（小月亮 → 山大科技园）
            var route = Path()
            route.move(to: CGPoint(x: 195 * scale, y: 200 * scale))
            route.addQuadCurve(to: CGPoint(x: 245 * scale, y: 145 * scale),
                               control: CGPoint(x: 215 * scale, y: 175 * scale))
            context.stroke(route, with: .color(Theme.primary.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 3 * scale, dash: [6 * scale, 6 * scale]))

            // 用户当前位置（小月亮）
            let userX = 195 * scale
            let userY = 200 * scale
            // 光圈脉冲
            for i in 0..<3 {
                let r = (14 + CGFloat(i) * 6) * scale
                context.fill(
                    Path(ellipseIn: CGRect(x: userX - r, y: userY - r, width: r * 2, height: r * 2)),
                    with: .color(Theme.primary.opacity(0.18 - Double(i) * 0.06))
                )
            }
            // 中心点
            context.fill(
                Path(ellipseIn: CGRect(x: userX - 10 * scale, y: userY - 10 * scale, width: 20 * scale, height: 20 * scale)),
                with: .color(.white)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: userX - 7 * scale, y: userY - 7 * scale, width: 14 * scale, height: 14 * scale)),
                with: .color(Theme.primary)
            )
        }
    }

    private func drawPOI(context: GraphicsContext, x: Double, y: Double, label: String,
                         color: Color, systemIcon: String, scale: CGFloat) {
        let cx = x * scale
        let cy = y * scale
        // 光圈
        context.fill(
            Path(ellipseIn: CGRect(x: cx - 22 * scale, y: cy - 22 * scale, width: 44 * scale, height: 44 * scale)),
            with: .color(color.opacity(0.18))
        )
        // 中心圆
        context.fill(
            Path(ellipseIn: CGRect(x: cx - 14 * scale, y: cy - 14 * scale, width: 28 * scale, height: 28 * scale)),
            with: .color(color)
        )
        // 中心 SF Symbol（用 Canvas 的 resolvedSymbol 模式）
        // 简化为只画带圆点的中心,因为 Canvas 中画 SF Symbol 较复杂
        context.fill(
            Path(ellipseIn: CGRect(x: cx - 4 * scale, y: cy - 4 * scale, width: 8 * scale, height: 8 * scale)),
            with: .color(.white)
        )
        // 标签背景
        let labelWidth: CGFloat = CGFloat(label.count) * 8 * scale + 16
        let labelRect = CGRect(
            x: cx - labelWidth / 2, y: cy + 18 * scale,
            width: labelWidth, height: 22 * scale
        )
        context.fill(
            Path(roundedRect: labelRect, cornerRadius: 11 * scale),
            with: .color(.white)
        )
        context.stroke(
            Path(roundedRect: labelRect, cornerRadius: 11 * scale),
            with: .color(color),
            lineWidth: 1.5 * scale
        )
        context.draw(
            Text(label)
                .font(.system(size: 10 * scale, weight: .semibold))
                .foregroundColor(color),
            at: CGPoint(x: cx, y: cy + 28 * scale)
        )
    }
}

private struct MapFabButton: View {
    let icon: String

    var body: some View {
        Button(action: {}) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.violet)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                        .fill(Color.white.opacity(0.95))
                )
                .softShadow(Theme.shadowSm)
        }
    }
}

#Preview {
    MiniMap()
        .padding()
        .background(Theme.bgGradient)
}
