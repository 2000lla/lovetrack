import Foundation
import CoreLocation
#if canImport(os)
import os
#endif

/// Firebase 抽象层（protocol）。MVP 实现见 `InMemoryRealtimeSyncService`（默认注入）。
///
/// 真实集成时把 `InMemoryRealtimeSyncService` 替换为 `FirebaseRealtimeSyncService`（另开文件）。
/// 两者都实现 `RealtimeSyncServiceProtocol`，ViewModel / Store 不感知差异。
public protocol RealtimeSyncServiceProtocol: Sendable {
    // MARK: - User
    func upsertUser(_ user: User) async throws
    func observePartnerInfo(userId: String) -> AsyncStream<User>

    // MARK: - Pairing
    func createPairInvite(code: String, inviter: User) async throws
    func acceptPairInvite(code: String, invitee: User) async throws -> Relationship
    func dissolveRelationship(id: String) async throws

    // MARK: - Location
    func uploadPoint(_ point: LocationPoint) async throws
    func observePartnerLocation(userId: String) -> AsyncStream<LocationPoint>
    func fetchTrackSegment(userId: String, date: Date) async throws -> TrackSegment?
}

/// 内存版同步服务（MVP 默认）。
/// - 用 `NSLock` 保证线程安全
/// - 不会真正跨进程；用于本地开发、UI 调试、单元测试
public final class InMemoryRealtimeSyncService: RealtimeSyncServiceProtocol, @unchecked Sendable {
    public struct NotFound: Error { public let what: String }

    private let lock = NSLock()
    private var users: [String: User] = [:]
    private var partnerStreams: [String: [UUID: AsyncStream<User>.Continuation]] = [:]
    private var locationStreams: [String: [UUID: AsyncStream<LocationPoint>.Continuation]] = [:]
    private var latestPartnerLocation: [String: LocationPoint] = [:]
    private var pairCodes: [String: String] = [:]  // code -> inviterId
    private var points: [String: [LocationPoint]] = [:]  // userId -> points

    public init() {}

    // MARK: - User

    public func upsertUser(_ user: User) async throws {
        lock.lock(); defer { lock.unlock() }
        users[user.id] = user
        let userCopy = user
        let streams = partnerStreams[user.id] ?? [:]
        lock.unlock()
        for cont in streams.values { cont.yield(userCopy) }
        lock.lock()
    }

    public func observePartnerInfo(userId: String) -> AsyncStream<User> {
        AsyncStream { cont in
            let id = UUID()
            self.lock.lock()
            var dict = self.partnerStreams[userId] ?? [:]
            dict[id] = cont
            self.partnerStreams[userId] = dict
            let initial = self.users[userId]
            self.lock.unlock()
            if let u = initial { cont.yield(u) }
            cont.onTermination = { [weak self] _ in
                self?.removePartnerStream(userId: userId, streamId: id)
            }
        }
    }

    // MARK: - Pairing

    public func createPairInvite(code: String, inviter: User) async throws {
        lock.lock()
        pairCodes[code] = inviter.id
        users[inviter.id] = inviter
        lock.unlock()
    }

    public func acceptPairInvite(code: String, invitee: User) async throws -> Relationship {
        lock.lock()
        guard let inviterId = pairCodes[code] else {
            lock.unlock()
            throw NotFound(what: "pair code \(code)")
        }
        users[invitee.id] = invitee
        var inviter = users[inviterId]
        inviter?.updatedAt = Date()
        if let i = inviter { users[inviterId] = i }
        let streams = partnerStreams[inviterId] ?? [:]
        let snapshot = inviter
        let rel = Relationship(
            id: "rel_\(inviterId)_\(invitee.id)",
            userA: inviterId,
            userB: invitee.id,
            status: .active,
            pairedAt: Date()
        )
        lock.unlock()
        if let snap = snapshot {
            for cont in streams.values { cont.yield(snap) }
        }
        return rel
    }

    public func dissolveRelationship(id: String) async throws {
        lock.lock()
        // 内存版 no-op，仅占位
        _ = id
        lock.unlock()
    }

    // MARK: - Location

    public func uploadPoint(_ point: LocationPoint) async throws {
        lock.lock()
        var arr = points[point.userId] ?? []
        arr.append(point)
        points[point.userId] = arr
        latestPartnerLocation[point.userId] = point
        let streams = locationStreams[point.userId] ?? [:]
        let snapshot = point
        lock.unlock()
        for cont in streams.values { cont.yield(snapshot) }
    }

    public func observePartnerLocation(userId: String) -> AsyncStream<LocationPoint> {
        AsyncStream { cont in
            let id = UUID()
            self.lock.lock()
            var dict = self.locationStreams[userId] ?? [:]
            dict[id] = cont
            self.locationStreams[userId] = dict
            let initial = self.latestPartnerLocation[userId]
            self.lock.unlock()
            if let p = initial { cont.yield(p) }
            cont.onTermination = { [weak self] _ in
                self?.removeLocationStream(userId: userId, streamId: id)
            }
        }
    }

    public func fetchTrackSegment(userId: String, date: Date) async throws -> TrackSegment? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            return nil
        }
        lock.lock()
        let daily = (points[userId] ?? []).filter { p in
            p.timestamp >= dayStart && p.timestamp < dayEnd
        }
        lock.unlock()
        guard !daily.isEmpty else { return nil }
        let sorted = daily.sorted { $0.timestamp < $1.timestamp }
        var dist: Double = 0
        for i in 1..<sorted.count {
            let a = CLLocation(latitude: sorted[i - 1].lat, longitude: sorted[i - 1].lon)
            let b = CLLocation(latitude: sorted[i].lat, longitude: sorted[i].lon)
            dist += a.distance(from: b)
        }
        let summary = TrackSegment.Summary(
            distanceMeters: dist,
            topSpeed: sorted.compactMap { $0.speed }.max() ?? 0,
            avgSpeed: dist / max(1, Double(sorted.count)),
            polylineEncoded: ""
        )
        return TrackSegment(
            userId: userId,
            startedAt: sorted.first?.timestamp ?? dayStart,
            endedAt: sorted.last?.timestamp ?? dayEnd,
            points: sorted,
            summary: summary
        )
    }

    // MARK: - helpers

    private func removePartnerStream(userId: String, streamId: UUID) {
        lock.lock()
        partnerStreams[userId]?.removeValue(forKey: streamId)
        lock.unlock()
    }

    private func removeLocationStream(userId: String, streamId: UUID) {
        lock.lock()
        locationStreams[userId]?.removeValue(forKey: streamId)
        lock.unlock()
    }
}
