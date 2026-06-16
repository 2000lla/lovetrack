import Foundation
import CoreLocation
import SwiftUI

#if canImport(AMapFoundation)
import AMapFoundation
import AMapMapKit
#endif

/// SwiftUI 地图视图（占位实现）。
///
/// 真实集成：
/// 1. 引入高德 SwiftUI 扩展包 `https://github.com/finestructure/AMapUIKit-SwiftUI`（或自封装 UIViewRepresentable）
/// 2. 在 `body` 里 `AMapView(...) { ... }` 渲染
/// 3. 通过 Coordinator 把高德 GCJ-02 坐标转 WGS-84 给 `LocationManager`（高德只显示，不存）
public struct MapView: View {
    public let center: CLLocationCoordinate2D
    public let annotations: [Annotation]
    public let polyline: [CLLocationCoordinate2D]
    public let showsUserLocation: Bool
    public let onTapAnnotation: ((Annotation) -> Void)?

    public init(
        center: CLLocationCoordinate2D,
        annotations: [Annotation] = [],
        polyline: [CLLocationCoordinate2D] = [],
        showsUserLocation: Bool = true,
        onTapAnnotation: ((Annotation) -> Void)? = nil
    ) {
        self.center = center
        self.annotations = annotations
        self.polyline = polyline
        self.showsUserLocation = showsUserLocation
        self.onTapAnnotation = onTapAnnotation
    }

    public var body: some View {
        ZStack {
            #if canImport(AMapMapKit)
            // 真实实现:
            // AMapSwiftUIView(
            //     center: center,
            //     annotations: annotations,
            //     polyline: polyline
            // )
            // .ignoresSafeArea()
            Color(red: 0.95, green: 0.93, blue: 0.97)
            placeholder
            #else
            Color(red: 0.95, green: 0.93, blue: 0.97)
            placeholder
            #endif
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "map.fill")
                .font(.system(size: 40))
                .foregroundStyle(.purple.opacity(0.6))
            Text("高德地图（占位）")
                .font(.headline)
            Text(String(format: "lat: %.4f, lon: %.4f", center.latitude, center.longitude))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !annotations.isEmpty {
                Text("标注: \(annotations.count) 个")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !polyline.isEmpty {
                Text("轨迹点: \(polyline.count) 个")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

extension MapView {
    public struct Annotation: Identifiable, Equatable, Sendable, Hashable {
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

        public static func == (lhs: Annotation, rhs: Annotation) -> Bool {
            // CLLocationCoordinate2D 不自动 Equatable,手动比
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
