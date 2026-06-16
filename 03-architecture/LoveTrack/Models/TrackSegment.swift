import Foundation

/// 一段连续轨迹（一次"出门 - 回家"或固定时长切片）。
///
/// 用于轨迹回放页查询；MVP 阶段按"自然日"切片（每天 1 个 Segment）。
public struct TrackSegment: Codable, Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public let userId: String
    public let startedAt: Date
    public let endedAt: Date
    public var points: [LocationPoint]
    public var summary: Summary

    public struct Summary: Codable, Equatable, Sendable, Hashable {
        public let distanceMeters: Double
        public let topSpeed: Double
        public let avgSpeed: Double
        /// Google Encoded Polyline（压缩存储轨迹；前端解码后渲染折线）
        public let polylineEncoded: String

        public init(
            distanceMeters: Double,
            topSpeed: Double,
            avgSpeed: Double,
            polylineEncoded: String
        ) {
            self.distanceMeters = distanceMeters
            self.topSpeed = topSpeed
            self.avgSpeed = avgSpeed
            self.polylineEncoded = polylineEncoded
        }
    }

    public init(
        id: String = UUID().uuidString,
        userId: String,
        startedAt: Date,
        endedAt: Date,
        points: [LocationPoint] = [],
        summary: Summary
    ) {
        self.id = id
        self.userId = userId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.points = points
        self.summary = summary
    }
}
