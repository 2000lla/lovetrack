import SwiftUI
import MapKit
import CoreLocation

/// SwiftUI 地图视图 —— iOS 16+ MapKit 实现。
///
/// 用法：
/// ```swift
/// MapView(
///     center: coordinate,
///     annotations: [...],
///     polyline: [...],
///     showsUserLocation: false
/// )
/// ```
///
/// 用于 `TrackPlaybackView`：显示当天轨迹折线 + 当前位置 marker。
public struct MapView: View {
    public let center: CLLocationCoordinate2D
    public let annotations: [MapItem]
    public let polyline: [CLLocationCoordinate2D]
    public let showsUserLocation: Bool
    public let onTapAnnotation: ((MapItem) -> Void)?

    @State private var cameraPosition: MapCameraPosition

    public init(
        center: CLLocationCoordinate2D,
        annotations: [MapItem] = [],
        polyline: [CLLocationCoordinate2D] = [],
        showsUserLocation: Bool = true,
        onTapAnnotation: ((MapItem) -> Void)? = nil
    ) {
        self.center = center
        self.annotations = annotations
        self.polyline = polyline
        self.showsUserLocation = showsUserLocation
        self.onTapAnnotation = onTapAnnotation

        // 自动取景：fit 所有 polyline 点 + center
        let allCoords = polyline.isEmpty ? [center] : polyline
        if let region = Self.boundingRegion(for: allCoords) {
            self._cameraPosition = State(initialValue: .region(region))
        } else {
            self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: center,
                latitudinalMeters: 2000,
                longitudinalMeters: 2000
            )))
        }
    }

    public var body: some View {
        Map(position: $cameraPosition, selection: .constant(nil)) {
            if showsUserLocation {
                UserAnnotation()
            }
            // 轨迹折线
            if polyline.count >= 2 {
                MapPolyline(coordinates: polyline)
                    .stroke(
                        Color.purple,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }
            // 自定义 annotations —— 用 @MapContentBuilder 辅助函数让每个元素都明确是 MapContent
            annotationContents
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
            if showsUserLocation {
                MapUserLocationButton()
            }
        }
        .onChange(of: center.latitude, initial: false) { _, _ in
            cameraPosition = .region(MKCoordinateRegion(
                center: center,
                latitudinalMeters: 1500,
                longitudinalMeters: 1500
            ))
        }
    }

    /// 把所有自定义 annotations 包装成 MapContent 元素
    /// 当前用法：TrackPlaybackView 只传 1 个起点 annotation, 直接列。
    /// 注意：不要在 @MapContentBuilder 里用 `if let` —— MapContentBuilder 会把 binding 当成
    /// MapContent 元素要求 conform, 导致编译错误。改用 if + 内部 `let`。
    @MapContentBuilder
    private var annotationContents: some MapContent {
        if !annotations.isEmpty {
            let ann = annotations[0]
            Annotation(ann.title, coordinate: ann.coordinate) {
                Image(systemName: ann.iconSystemName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.purple)
                            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    )
                    .onTapGesture {
                        onTapAnnotation?(ann)
                    }
            }
        }
    }

    /// 计算一组坐标的 bounding region（留 20% padding）
    private static func boundingRegion(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coords.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

extension MapView {
    /// 自定义地图标注 (model 层) ——
    /// 命名为 `MapItem` 而非 `Annotation`, 避免遮蔽 SwiftUI `Annotation` (iOS 17+ MapContent)。
    public struct MapItem: Identifiable, Equatable, Sendable, Hashable {
        public let id: String
        public let coordinate: CLLocationCoordinate2D
        public let title: String
        public let subtitle: String?
        public let iconSystemName: String

        public init(
            id: String,
            coordinate: CLLocationCoordinate2D,
            title: String,
            subtitle: String? = nil,
            iconSystemName: String = "mappin.circle.fill"
        ) {
            self.id = id
            self.coordinate = coordinate
            self.title = title
            self.subtitle = subtitle
            self.iconSystemName = iconSystemName
        }

        public static func == (lhs: MapItem, rhs: MapItem) -> Bool {
            return lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.subtitle == rhs.subtitle
                && lhs.iconSystemName == rhs.iconSystemName
                && lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(coordinate.latitude)
            hasher.combine(coordinate.longitude)
        }
    }
}