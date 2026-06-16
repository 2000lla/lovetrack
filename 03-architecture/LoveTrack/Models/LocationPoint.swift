import Foundation

/// 单个定位点（实时 + 轨迹回放共用）。
///
/// 坐标系：始终存 WGS-84（CoreLocation 原生）。显示时由地图 SDK 负责转换。
public struct LocationPoint: Codable, Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public let userId: String
    public let lat: Double
    public let lon: Double
    public let altitude: Double?
    public let horizontalAccuracy: Double
    public let verticalAccuracy: Double?
    public let speed: Double?
    public let course: Double?
    public let timestamp: Date
    public let receivedAt: Date
    public let battery: BatteryInfo?
    public let source: Source
    public let sessionId: String

    public init(
        id: String = UUID().uuidString,
        userId: String,
        lat: Double,
        lon: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double,
        verticalAccuracy: Double? = nil,
        speed: Double? = nil,
        course: Double? = nil,
        timestamp: Date,
        receivedAt: Date = Date(),
        battery: BatteryInfo? = nil,
        source: Source,
        sessionId: String
    ) {
        self.id = id
        self.userId = userId
        self.lat = lat
        self.lon = lon
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
        self.timestamp = timestamp
        self.receivedAt = receivedAt
        self.battery = battery
        self.source = source
        self.sessionId = sessionId
    }
}

public struct BatteryInfo: Codable, Equatable, Sendable, Hashable {
    public let level: Double           // 0.0 ~ 1.0
    public let isCharging: Bool
    public let isLowPower: Bool

    public init(level: Double, isCharging: Bool, isLowPower: Bool) {
        self.level = level
        self.isCharging = isCharging
        self.isLowPower = isLowPower
    }
}

public enum Source: String, Codable, Sendable {
    case gps                  // GPS 卫星定位
    case wifi                 // Wi-Fi 定位
    case cell                 // 基站定位
    case significantChange    // Significant-Change 兜底
}
