import Foundation
import CoreLocation

/// WGS-84 ↔ GCJ-02 坐标转换（"火星坐标"）。
///
/// **为什么需要**：iOS CoreLocation 返回 WGS-84（国际标准），中国地图（高德/腾讯）
/// 内部使用 GCJ-02（国测局加密坐标）。如果直接把 WGS-84 喂给 MAMapView，pin
/// 会在地图上偏移 50-500 米（在南宁实测 ~511 米）。
///
/// **使用场景**：
/// - ❌ 不要在 server 端转换（server 应该存原始 WGS-84，方便国际用户/未来扩展）
/// - ❌ 不要在 upload 端转换（设备采集就该是 WGS-84）
/// - ✅ 只在 display 端转换（喂给地图前一刻）
///
/// 转换算法来源：国测局 GCJ-02 加密算法公开实现。
extension CLLocationCoordinate2D {
    /// WGS-84 → GCJ-02（中国境内）
    public var gcj02: CLLocationCoordinate2D {
        // 中国境外不做转换
        guard CLLocationCoordinate2D.isInChina(longitude: longitude, latitude: latitude) else {
            return self
        }
        let a: Double = 6378245.0
        let ee: Double = 0.00669342162296594323

        var dLat = Self.transformLat(x: longitude - 105.0, y: latitude - 35.0)
        var dLng = Self.transformLng(x: longitude - 105.0, y: latitude - 35.0)
        let radLat = latitude / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)

        return CLLocationCoordinate2D(
            latitude: latitude + dLat,
            longitude: longitude + dLng
        )
    }

    /// 中国境内判定（粗略矩形框）
    public static func isInChina(longitude: Double, latitude: Double) -> Bool {
        if longitude < 72.004 || longitude > 137.8347 { return false }
        if latitude < 0.8293 || latitude > 55.8271 { return false }
        return true
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLng(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}