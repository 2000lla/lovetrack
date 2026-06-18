import Foundation
import CoreLocation
import Combine
import SwiftUI

/// 情侣关系管理 Store（@MainActor ObservableObject）。
public final class RelationshipStore: ObservableObject {
    @Published public private(set) var me: User
    @Published public var partner: User?
    @Published public var relationship: Relationship?
    @Published public var lastKnownPartnerLocation: LocationPoint?
    @Published public var isPaired: Bool = false

    private let realtime: RealtimeSyncServiceProtocol
    private var partnerLocationTask: Task<Void, Never>?
    private var partnerInfoTask: Task<Void, Never>?

    public init(me: User, realtime: RealtimeSyncServiceProtocol) {
        self.me = me
        self.realtime = realtime
    }

    deinit {
        partnerLocationTask?.cancel()
        partnerInfoTask?.cancel()
    }

    /// 生成 6 位配对码。
    /// 返回后端生成的真实 code（不是本地随机）。
    /// 设计：邀请方创建码后保持 PairScreen 看邀请码；等 receive pair_success WebSocket push 再自动跳主页。
    public func generatePairCode() async throws -> String {
        try await realtime.createPairInvite(code: "PLACEHOLDER", inviter: me)
        let realCode: String
        if let http = realtime as? HTTPRealtimeSyncService {
            realCode = http.latestInviteCode
        } else {
            realCode = String(format: "%06d", Int.random(in: 0..<1_000_000))
        }
        // 记下 pending 关系（只设 relationship，不设 isPaired —— 等 pair_success 才改）
        await MainActor.run {
            self.relationship = Relationship(
                id: "pending_\(self.me.id)",
                userA: self.me.id,
                userB: "",
                status: .pending,
                pairedAt: Date()
            )
            // isPaired 保持 false，直到 WebSocket 推送 pair_success
        }
        return realCode
    }

    /// 加入（输入对方配对码）。
    public func acceptPairCode(_ code: String) async throws {
        let relationship = try await realtime.acceptPairInvite(code: code, invitee: me)
        await applyRelationship(relationship)
    }

    /// 解除关系。
    public func dissolve() async throws {
        guard let r = relationship else { return }
        try await realtime.dissolveRelationship(id: r.id)
        await MainActor.run {
            self.relationship = nil
            self.partner = nil
            self.isPaired = false
            self.lastKnownPartnerLocation = nil
        }
    }

    /// 订阅伴侣信息 + 位置变更。
    public func startObservingPartner() async {
        guard let r = relationship else { return }
        partnerInfoTask?.cancel()
        partnerInfoTask = Task { [weak self] in
            guard let self = self else { return }
            let partnerId = r.userA == self.me.id ? r.userB : r.userA
            for await partner in self.realtime.observePartnerInfo(userId: partnerId) {
                await MainActor.run { self.partner = partner }
            }
        }
        partnerLocationTask?.cancel()
        partnerLocationTask = Task { [weak self] in
            guard let self = self else { return }
            let partnerId = r.userA == self.me.id ? r.userB : r.userA
            for await point in self.realtime.observePartnerLocation(userId: partnerId) {
                await MainActor.run { self.lastKnownPartnerLocation = point }
            }
        }
    }

    // MARK: - Private

    private func applyRelationship(_ r: Relationship) async {
        await MainActor.run {
            self.relationship = r
            self.isPaired = r.status == .active
        }
        if r.status == .active {
            await startObservingPartner()
        }
    }

    /// 计算"我"到伴侣的距离（公里）。
    public func distanceKmToPartner(myLocation: CLLocation?) -> Double? {
        guard let p = lastKnownPartnerLocation, let me = myLocation else { return nil }
        let partner = CLLocation(latitude: p.lat, longitude: p.lon)
        return me.distance(from: partner) / 1000
    }

    /// 主动刷新对方位置（外部 WebSocket 流触发）
    @MainActor
    public func refreshPartnerLocation(_ point: LocationPoint) {
        self.lastKnownPartnerLocation = point
        Log.info("RelationshipStore", "partner location updated: \(point.lat), \(point.lon)")
    }
}
