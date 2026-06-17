import Foundation
import CoreLocation
import SwiftUI

#if canImport(MAMapKit)
import AMapFoundationKit
import MAMapKit

/// SwiftUI 包装的高德 3D 地图视图。
///
/// 用法：
/// ```swift
/// AAMapView(
///     center: CLLocationCoordinate2D(latitude: 36.65, longitude: 117.12),
///     partner: MapPerson(id: "p1", name: "小月亮", coordinate: ...),
///     me: MapPerson(id: "u1", name: "我", coordinate: ...)
/// )
/// ```
///
/// Sprint 1 用法：替换 RealtimeMapScreen 里的 MiniMap Canvas 占位，
/// 显示真实地图 + 双方位置 marker。
public struct AAMapView: UIViewRepresentable {
    public let center: CLLocationCoordinate2D
    public let partner: MapPerson?
    public let me: MapPerson?
    public let zoomLevel: CGFloat
    public let showsUserLocation: Bool

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
    }

    public func makeUIView(context: Context) -> MAMapView {
        // 隐私合规：必须先于任何 MAMapView 创建前调用
        // (iOS 15+ 强制要求, 否则地图无法加载)
        MAMapView.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        MAMapView.updatePrivacyAgree(.didAgree)

        let map = MAMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = showsUserLocation
        map.zoomLevel = zoomLevel
        map.setCenter(center, animated: false)
        // 关闭高德 logo 缩放控件
        map.showsCompass = true
        map.showsScale = true
        return map
    }

    public func updateUIView(_ map: MAMapView, context: Context) {
        // 1. 清旧的自定义 annotation (保留系统 userLocation)
        let stale = map.annotations.filter { !($0 is MAUserLocation) }
        map.removeAnnotations(stale)

        // 2. 加伴侣 marker
        if let p = partner {
            let pin = MAPointAnnotation()
            pin.coordinate = p.coordinate
            pin.title = p.name
            pin.subtitle = "TA 在这里"
            map.addAnnotation(pin)
        }

        // 3. 加我 marker (如果不用 showsUserLocation 蓝点)
        if !showsUserLocation, let m = me {
            let pin = MAPointAnnotation()
            pin.coordinate = m.coordinate
            pin.title = m.name
            pin.subtitle = "我在这里"
            map.addAnnotation(pin)
        }

        // 4. 中心点移动 (动画)
        map.setCenter(center, animated: true)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator: NSObject, MAMapViewDelegate {
        public func mapView(
            _ mapView: MAMapView!,
            viewFor annotation: MAAnnotation!
        ) -> MAAnnotationView! {
            // 系统 userLocation 不需要自定义
            guard let point = annotation as? MAPointAnnotation else { return nil }

            let id = "lovetrack-pin"
            let view: MAAnnotationView
            if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: id) {
                view = dequeued
                view.annotation = point
            } else {
                view = MAAnnotationView(annotation: point, reuseIdentifier: id)
            }
            // 用 SF Symbol 渲染 pin (比默认红点好看)
            let cfg = UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold)
            let baseImage = UIImage(systemName: "heart.circle.fill", withConfiguration: cfg)
            view.image = baseImage?.withTintColor(.systemPink, renderingMode: .alwaysOriginal)
            view.canShowCallout = true
            view.centerOffset = CGPoint(x: 0, y: -16)
            return view
        }
    }
}

/// 地图上要显示的人。id 用于稳定 identity (SwiftUI diff)。
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
        hasher.combine(name)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}
#endif
