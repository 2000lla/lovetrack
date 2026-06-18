import SwiftUI
import MapKit
import CoreLocation

/// SwiftUI `Map` 包装（iOS 16+）。
///
/// 设计要点：
/// - API 跟旧的 AAMapView 完全兼容（center / partner / me / zoomLevel / showsUserLocation）
///   → 改 3 处调用点就能完成迁移
/// - 用 WGS-84 坐标（iOS CoreLocation 原生），**不需要 GCJ-02 转换**
/// - 自定义 marker 用 SwiftUI view 渲染（iOS 17+ `Annotation`）/ 系统 marker（iOS 16 fallback）
///
/// 部署目标 iOS 16+。Marker 在 iOS 16 即可用；iOS 17+ 推荐用 `Annotation` 包任意 SwiftUI view。
public struct MapKitView: View {
    public let center: CLLocationCoordinate2D
    public let partner: MapPerson?
    public let me: MapPerson?
    public let zoomLevel: CGFloat
    public let showsUserLocation: Bool

    @State private var cameraPosition: MapCameraPosition

    public init(
        center: CLLocationCoordinate2D,
        partner: MapPerson? = nil,
        me: MapPerson? = nil,
        zoomLevel: CGFloat = 14,
        showsUserLocation: Bool = true
    ) {
        self.center = center
        self.partner = partner
        self.me = me
        self.zoomLevel = zoomLevel
        self.showsUserLocation = showsUserLocation
        // zoomLevel (高德/Google 体系) → MKCoordinateSpan 半径 (米)
        // zoomLevel 14 ≈ 半径 1500m, 15 ≈ 750m, 13 ≈ 3000m
        let radius = zoomLevelToRadius(zoomLevel)
        self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )))
    }

    public var body: some View {
        Map(position: $cameraPosition) {
            if showsUserLocation {
                UserAnnotation()
            }
            // 伴侣 marker
            if let p = partner {
                Annotation(p.name, coordinate: p.coordinate) {
                    PersonMarkerView(name: p.name, isMe: false)
                }
                .annotationTitles(.hidden)
            }
            // "我" marker（如果不依赖系统蓝点）
            if !showsUserLocation, let m = me {
                Annotation(m.name, coordinate: m.coordinate) {
                    PersonMarkerView(name: m.name, isMe: true)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
            if showsUserLocation {
                MapUserLocationButton()
            }
        }
        .onChange(of: center.latitude, initial: false) { _, _ in updateCamera(animated: true) }
        .onChange(of: center.longitude, initial: false) { _, _ in updateCamera(animated: true) }
        .onAppear { updateCamera(animated: false) }
    }

    private func updateCamera(animated: Bool) {
        let radius = zoomLevelToRadius(zoomLevel)
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        // MapCameraPosition.region 暂不支持 animated,所以这里统一 instant。
        // SwiftUI 的 .region 过渡本身有动画,但底层不做 setCenter 那种硬切。
        withAnimation(.easeInOut(duration: animated ? 0.35 : 0)) {
            cameraPosition = .region(region)
        }
    }
}

/// 把 AMap/Google 风格的 zoomLevel 转成可视半径（米）。
/// 对照表：zoom 14 ≈ 1.5km, 15 ≈ 750m, 16 ≈ 350m, 12 ≈ 6km, 10 ≈ 25km
private func zoomLevelToRadius(_ zoom: CGFloat) -> CLLocationDistance {
    // 经验公式：radius = 40075000 / 2^(zoom+1)（地球周长 / 2^(zoom+1)）
    return 40_075_000 / pow(2, Double(zoom + 1))
}

// MARK: - 自定义 marker

private struct PersonMarkerView: View {
    let name: String
    let isMe: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(isMe ? Color.blue : Color.pink)
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                Image(systemName: isMe ? "person.fill" : "heart.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color(.systemBackground).opacity(0.92))
                        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                )
                .foregroundColor(.primary)
        }
    }
}

/// 地图上要显示的人。id 用于稳定 identity (SwiftUI diff)。
///
/// 跟旧的 AAMapView.MapPerson 完全兼容（同样 id/name/coordinate），
/// 改完 import 即可继续用。
public struct MapPerson: Equatable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let coordinate: CLLocationCoordinate2D

    public init(id: String, name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }

    public static func == (lhs: MapPerson, rhs: MapPerson) -> Bool {
        // CLLocationCoordinate2D 不自动 Equatable, 手动比
        return lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}