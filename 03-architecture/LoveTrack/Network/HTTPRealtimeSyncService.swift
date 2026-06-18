import Foundation
import CoreLocation

/// HTTP + WebSocket 实现的 RealtimeSyncService，对接 Node.js 后端（05-backend）。
///
/// 协议面（RealtimeSyncServiceProtocol）和 InMemoryRealtimeSyncService 一致，
/// 但实际数据走 HTTP 邀请码 / WebSocket 位置同步。
///
/// MVP 限制：
/// - WebSocket 连接断线后只重连 1 次（后续可加重试退避）
/// - 不做 HTTP auth（Demo 阶段够用）
public final class HTTPRealtimeSyncService: RealtimeSyncServiceProtocol, @unchecked Sendable {

    // MARK: - Errors

    public enum ServiceError: Error, LocalizedError {
        case httpStatus(Int, String)
        case decoding(Error)
        case connectionClosed

        public var errorDescription: String? {
            switch self {
            case .httpStatus(let code, let body):
                return "HTTP \(code): \(body)"
            case .decoding(let err):
                return "Decode failed: \(err.localizedDescription)"
            case .connectionClosed:
                return "WebSocket connection closed"
            }
        }
    }

    /// 配对成功回调（从 WebSocket pair_success 或 HTTP pair 回来）
    public var onPairSuccess: ((String) -> Void)?

    // MARK: - Internal state

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var isConnected = false

    /// 用户 ID
    private let userId: String

    /// 状态锁
    private let lock = NSLock()

    /// 对方位置流（key: userId）
    private var locationStreams: [String: [UUID: AsyncStream<LocationPoint>.Continuation]] = [:]

    /// 对方用户流
    private var partnerStreams: [String: [UUID: AsyncStream<User>.Continuation]] = [:]

    /// 缓存的最新对方位置
    private var latestPartnerLocation: [String: LocationPoint] = [:]

    /// 缓存的 User
    private var users: [String: User] = [:]

    /// 当前已配对关系
    private var relationship: Relationship?

    /// 最近一次创建邀请码返回的真实 code（供 UI 显示）
    public private(set) var latestInviteCode: String = ""

    public init(userId: String) {
        self.userId = userId
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - User

    public func upsertUser(_ user: User) async throws {
        lock.lock()
        users[user.id] = user
        lock.unlock()
        // 不需要后端持久化（demo 用）
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
                self?.lock.lock()
                self?.partnerStreams[userId]?.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    // MARK: - Pairing

    /// 创建邀请码（调后端 POST /bind）
    public func createPairInvite(code: String, inviter: User) async throws {
        var req = URLRequest(url: BackendConfig.baseURL.appendingPathComponent("bind"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 5

        let body = ["userId": inviter.id]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        Log.info("HTTPRealtime", "POST \(req.url?.absoluteString ?? "?") body=\(body)")

        do {
            let (data, resp) = try await session.data(for: req)
            Log.info("HTTPRealtime", "got response, status=\((resp as? HTTPURLResponse)?.statusCode ?? 0)")
            guard let http = resp as? HTTPURLResponse else {
                throw ServiceError.httpStatus(0, "no http response")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ServiceError.httpStatus(http.statusCode, body)
            }

            // 解析返回 { code: "...", expiresIn: 600 }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let serverCode = json["code"] as? String else {
                throw ServiceError.decoding(NSError(domain: "decode", code: 0))
            }
            latestInviteCode = serverCode
            Log.info("HTTPRealtime", "bind OK: code=\(serverCode) userId=\(inviter.id)")

            // 后端返回的是 serverCode，不是入参 code —— 入参 code 是占位
            // 我们信任后端返回的 code
            lock.lock()
            relationship = Relationship(
                id: "pending_\(inviter.id)",
                userA: inviter.id,
                userB: "",
                status: .pending,
                pairedAt: Date()
            )
            lock.unlock()

            // 启动 WebSocket
            await connectWebSocket()
        } catch let urlError as URLError {
            Log.warn("HTTPRealtime", "URLError: \(urlError.code.rawValue) - \(urlError.localizedDescription)")
            throw urlError
        }
    }

    /// 用邀请码绑定（调后端 POST /pair）
    public func acceptPairInvite(code: String, invitee: User) async throws -> Relationship {
        var req = URLRequest(url: BackendConfig.baseURL.appendingPathComponent("pair"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["code": code, "userId": invitee.id]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ServiceError.httpStatus(0, "no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpStatus(http.statusCode, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inviterId = json["inviterId"] as? String else {
            throw ServiceError.decoding(NSError(domain: "decode", code: 0))
        }

        let rel = Relationship(
            id: "rel_\(inviterId)_\(invitee.id)",
            userA: inviterId,
            userB: invitee.id,
            status: .active,
            pairedAt: Date()
        )

        lock.lock()
        relationship = rel
        users[inviterId] = User(id: inviterId, displayName: "伴侣")
        // 邀请方是 inviterId，我们（invitee）的 partnerKey 就是 inviterId
        actualPartnerKey = inviterId
        lock.unlock()

        Log.info("HTTPRealtime", "pair OK: \(inviterId) ↔ \(invitee.id), partnerKey=\(inviterId)")
        await connectWebSocket()
        return rel
    }

    public func dissolveRelationship(id: String) async throws {
        lock.lock()
        relationship = nil
        lock.unlock()
        await disconnectWebSocket()
    }

    // MARK: - Location

    public func uploadPoint(_ point: LocationPoint) async throws {
        guard isConnected, let task = task else {
            // 没连上就跳过，不抛错（demo 阶段够用）
            return
        }

        let payload: [String: Any] = [
            "lat": point.lat,
            "lng": point.lon,
            "battery": point.battery?.level ?? 1.0,
        ]
        let msg: [String: Any] = [
            "type": "location_update",
            "payload": payload,
        ]

        let data = try JSONSerialization.data(withJSONObject: msg)
        let str = String(data: data, encoding: .utf8) ?? ""
        try await task.send(.string(str))
    }

    public func observePartnerLocation(userId: String) -> AsyncStream<LocationPoint> {
        AsyncStream { cont in
            let id = UUID()
            // 关键修复：用 actualPartnerKey 作为订阅 key，而不是入参 userId。
            // 入参可能是 "partner"（AppSession 的旧调用）或真 partner UUID（RelationshipStore）。
            // 真实 partner_location 缓存时也是用 actualPartnerKey，这样三种调用方式都对得上。
            self.lock.lock()
            let effectiveKey = self.actualPartnerKey ?? userId
            var dict = self.locationStreams[effectiveKey] ?? [:]
            dict[id] = cont
            self.locationStreams[effectiveKey] = dict
            let initial = self.latestPartnerLocation[effectiveKey]
            self.lock.unlock()
            Log.info("HTTPRealtime", "observePartnerLocation(userId=\(userId)) → effective=\(effectiveKey), hasInitial=\(initial != nil)")
            if let p = initial { cont.yield(p) }
            cont.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.locationStreams[effectiveKey]?.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    public func fetchTrackSegment(userId: String, date: Date) async throws -> TrackSegment? {
        // MVP 不实现后端轨迹拉取
        return nil
    }

    /// HTTP 兜底拉取对方最后位置（WebSocket 断线 / 后台被杀 / 服务重启时用）。
    /// GET /location/:userId → { lat, lng, battery, timestamp }
    public func fetchPartnerLocation(userId: String) async throws -> LocationPoint? {
        let url = BackendConfig.baseURL.appendingPathComponent("location/\(userId)")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5

        Log.info("HTTPRealtime", "GET \(url.absoluteString)")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            Log.warn("HTTPRealtime", "fetchPartnerLocation: no http response")
            return nil
        }
        // 404 是合法状态（对方还没上报过位置）
        if http.statusCode == 404 {
            Log.info("HTTPRealtime", "fetchPartnerLocation: 404 (no location yet)")
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            Log.warn("HTTPRealtime", "fetchPartnerLocation: HTTP \(http.statusCode) \(body)")
            throw ServiceError.httpStatus(http.statusCode, body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = json["lat"] as? Double,
              let lng = json["lng"] as? Double else {
            Log.warn("HTTPRealtime", "fetchPartnerLocation: bad payload")
            return nil
        }
        let battery = json["battery"] as? Double ?? 1.0
        let tsMs = json["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
        let timestamp = Date(timeIntervalSince1970: tsMs / 1000)

        let point = LocationPoint(
            userId: userId,
            lat: lat,
            lon: lng,
            altitude: 0,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            speed: -1,
            course: -1,
            timestamp: timestamp,
            receivedAt: Date(),
            battery: BatteryInfo(level: battery, isCharging: false, isLowPower: false),
            source: .gps,
            sessionId: ""
        )
        Log.info("HTTPRealtime", "fetchPartnerLocation: ✅ lat=\(lat), lng=\(lng), battery=\(Int(battery*100))%, age=\(Int(Date().timeIntervalSince(timestamp)))s")

        // 同时更新内部缓存 + 推送给订阅者
        self.lock.lock()
        let key = self.actualPartnerKey ?? userId
        self.latestPartnerLocation[key] = point
        // 兜底：也存到 "partner" key，旧订阅者用得上
        self.latestPartnerLocation["partner"] = point
        let streams = self.locationStreams[key] ?? [:]
        let fallbackStreams = self.locationStreams["partner"] ?? [:]
        self.lock.unlock()
        let totalSubs = streams.count + fallbackStreams.count
        Log.debug("HTTPRealtime", "fetchPartnerLocation: yield to \(totalSubs) subscribers (key=\(key) + fallback)")
        for cont in streams.values { cont.yield(point) }
        for cont in fallbackStreams.values { cont.yield(point) }

        return point
    }

    /// App 启动时拉取自己的关系状态（用于恢复"我是不是 paired"）。
    /// GET /me?userId=xxx → { userId, relationship, partner, lastKnownPartnerLocation, myLastLocation, isOnline }
    /// 返回 nil 表示当前未 paired。
    public func fetchMyState() async throws -> MyState? {
        var comps = URLComponents(url: BackendConfig.baseURL, resolvingAgainstBaseURL: false)!
        comps.path = "/me"
        comps.queryItems = [URLQueryItem(name: "userId", value: userId)]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5

        Log.info("HTTPRealtime", "GET \(url.absoluteString)")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            Log.warn("HTTPRealtime", "fetchMyState: no http response")
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            Log.warn("HTTPRealtime", "fetchMyState: HTTP \(http.statusCode) \(body)")
            throw ServiceError.httpStatus(http.statusCode, body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Log.warn("HTTPRealtime", "fetchMyState: bad payload")
            return nil
        }
        let relJson = json["relationship"] as? [String: Any]
        guard let relJson = relJson,
              let inviterId = relJson["inviterId"] as? String,
              let inviteeId = relJson["inviteeId"] as? String,
              let statusStr = relJson["status"] as? String,
              statusStr == "active" || statusStr == "paired" else {
            Log.info("HTTPRealtime", "fetchMyState: not paired")
            return nil
        }
        let partnerId = (inviterId == userId) ? inviteeId : inviterId
        let rel = Relationship(
            id: relJson["id"] as? String ?? "rel_\(inviterId)_\(inviteeId)",
            userA: inviterId,
            userB: inviteeId,
            status: .active,
            pairedAt: Date()
        )

        // 解析 partner lastLocation（如果有）
        var partnerLoc: LocationPoint?
        if let pl = json["lastKnownPartnerLocation"] as? [String: Any],
           let plat = pl["lat"] as? Double,
           let plng = pl["lng"] as? Double {
            let pbatt = pl["battery"] as? Double ?? 1.0
            let ptsMs = pl["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
            partnerLoc = LocationPoint(
                userId: partnerId,
                lat: plat,
                lon: plng,
                altitude: 0, horizontalAccuracy: 0, verticalAccuracy: 0,
                speed: -1, course: -1,
                timestamp: Date(timeIntervalSince1970: ptsMs / 1000),
                receivedAt: Date(),
                battery: BatteryInfo(level: pbatt, isCharging: false, isLowPower: false),
                source: .gps, sessionId: ""
            )
        }

        Log.info("HTTPRealtime", "fetchMyState: ✅ paired with \(partnerId), hasPartnerLoc=\(partnerLoc != nil)")
        if let loc = partnerLoc {
            Log.info("HTTPRealtime", "📍 fetchMyState partnerLoc: userId=\(loc.userId) lat=\(loc.lat) lon=\(loc.lon)")
        }
        return MyState(relationship: rel, partnerId: partnerId, lastKnownPartnerLocation: partnerLoc)
    }

    public struct MyState: Sendable {
        public let relationship: Relationship
        public let partnerId: String
        public let lastKnownPartnerLocation: LocationPoint?
    }

    /// 实际的 partner userId 缓存（acceptPairInvite 或 pair_success 时设置）。
    /// 修这个之前 observePartnerLocation(userId: "partner") 是个 magic string，
    /// 实际 RelationshipStore.startObservingPartner 用的是真 partner UUID，对不上。
    /// 现在统一用 actualPartnerKey 路由。
    private var actualPartnerKey: String?

    public func setPartnerKey(_ userId: String?) {
        lock.lock()
        let oldKey = actualPartnerKey
        actualPartnerKey = userId
        // 如果 partner 变了，把旧的 latest 迁移过来（避免切换时丢位置）
        if oldKey != userId, let userId = userId {
            if let oldLoc = latestPartnerLocation[oldKey ?? "partner"] {
                latestPartnerLocation[userId] = oldLoc
            }
        }
        lock.unlock()
        // 🐛 Bug 排查:不要把自己设成 partnerKey。
        if userId == self.userId {
            Log.error("HTTPRealtime", "🐛 BUG: setPartnerKey(\(userId ?? "nil")) 但 self.userId 也是 \(self.userId)!")
        }
        Log.info("HTTPRealtime", "partnerKey set: \(userId ?? "nil") (was: \(oldKey ?? "nil"))")
    }

    // MARK: - WebSocket

    /// 在 App 启动时提前连 WS（不依赖配对）
    public func bootstrapConnect() async {
        Log.info("HTTPRealtime", "bootstrapConnect called")
        await connectWebSocket()
    }

    private func connectWebSocket() async {
        guard task == nil else { return }
        var comps = URLComponents(url: BackendConfig.wsURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "userId", value: userId)]
        guard let url = comps.url else { return }

        let newTask = session.webSocketTask(with: url)
        self.task = newTask
        newTask.resume()
        isConnected = true
        Log.info("HTTPRealtime", "WebSocket connecting to \(url.absoluteString)")
        // 后台跑接收循环（不要 await，否则会阻塞外层）
        Task { await self.receiveLoop() }
    }

    private func disconnectWebSocket() async {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func receiveLoop() async {
        guard let task = task else { return }
        do {
            while true {
                let msg = try await task.receive()
                switch msg {
                case .string(let s):
                    handleServerMessage(s)
                case .data(let d):
                    if let s = String(data: d, encoding: .utf8) {
                        handleServerMessage(s)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            Log.warn("HTTPRealtime", "WebSocket error: \(error.localizedDescription)")
            isConnected = false
        }
    }

    private func handleServerMessage(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = msg["type"] as? String else {
            Log.warn("HTTPRealtime", "⚠️ 无法解析服务端消息: \(raw.prefix(120))")
            return
        }

        switch type {
        case "partner_location":
            guard let payload = msg["payload"] as? [String: Any],
                  let lat = payload["lat"] as? Double,
                  let lng = payload["lng"] as? Double else {
                Log.warn("HTTPRealtime", "partner_location payload 缺 lat/lng")
                return
            }
            let batteryLevel = payload["battery"] as? Double ?? 1.0
            let ts = payload["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
            let timestamp = Date(timeIntervalSince1970: ts / 1000)

            // 用 actualPartnerKey 路由（避免 RelationshipStore 和 AppSession 订阅对不上）
            self.lock.lock()
            let partnerKey = self.actualPartnerKey ?? "partner"
            self.lock.unlock()

            // 🐛 Bug 排查:打印接收方 / partnerKey / 实际收到的坐标。
            // 之前 bug = "A看A正确但A看B不正确",这条日志会显示 iOS 是否真的拿到了对方的坐标。
            Log.info("HTTPRealtime", "📍 partner_location 收: 接收方=\(self.userId) partnerKey=\(partnerKey) lat=\(lat) lng=\(lng) bat=\(Int(batteryLevel*100))% age=\(Int(Date().timeIntervalSince(timestamp)))s")

            // 🐛 防御:partnerLocation 不应该是自己。如果 partnerKey 跟自己一致,
            // 说明 actualPartnerKey 没正确初始化(典型症状:A 的 marker 显示在 A 自己的位置上)。
            if partnerKey == self.userId {
                Log.error("HTTPRealtime", "🐛 BUG: partnerKey(\(partnerKey)) == self.userId(\(self.userId))! 收到的 partner_location 会被当成自己的位置。actualPartnerKey 路由错乱。")
            }

            let point = LocationPoint(
                userId: partnerKey,
                lat: lat,
                lon: lng,
                altitude: 0,
                horizontalAccuracy: 0,
                verticalAccuracy: 0,
                speed: -1,
                course: -1,
                timestamp: timestamp,
                receivedAt: Date(),
                battery: BatteryInfo(level: batteryLevel, isCharging: false, isLowPower: false),
                source: .gps,
                sessionId: ""
            )

            lock.lock()
            latestPartnerLocation[partnerKey] = point
            // 兜底：也存到 "partner" key，兼容老的 AppSession 订阅
            latestPartnerLocation["partner"] = point
            // 🐛 BUG FIX: 当 partnerKey == "partner" 时,streams 和 fallbackStreams 是同一个 dict,
            // 双重迭代会把每个订阅者 yield 两次 → refreshPartnerLocation 被调 2 次 → 日志里 "subscribers=2" 是误报。
            // 改为用 Set 去重 + 一次 yield。
            let primaryStreams = locationStreams[partnerKey] ?? [:]
            let fallbackStreams = partnerKey == "partner" ? [:] : (locationStreams["partner"] ?? [:])
            let allContinuations: [UUID: AsyncStream<LocationPoint>.Continuation] =
                primaryStreams.merging(fallbackStreams) { _, new in new }
            let subscriberCount = allContinuations.count
            lock.unlock()

            Log.info("HTTPRealtime", "📍 partner_location 派发: point.userId=\(point.userId) point.lat=\(point.lat) point.lon=\(point.lon) → subscribers=\(subscriberCount) (key=\(partnerKey)+partner)")
            for cont in allContinuations.values { cont.yield(point) }

        case "pong":
            Log.debug("HTTPRealtime", "pong received")

        case "pair_success":
            Log.info("HTTPRealtime", "🎉 pair_success 收到！")
            let payload = msg["payload"] as? [String: Any] ?? [:]
            let inviteeId = payload["inviteeId"] as? String ?? "partner"
            // 更新本地状态 + 锁定 partnerKey 给后续订阅
            self.lock.lock()
            let r = self.relationship
            self.lock.unlock()
            if let rel = r {
                self.lock.lock()
                self.relationship = Relationship(
                    id: rel.id,
                    userA: rel.userA,
                    userB: inviteeId,
                    status: .active,
                    pairedAt: Date()
                )
                self.users[inviteeId] = User(id: inviteeId, displayName: "伴侣")
                // partnerKey = 对方 userId（不管我是 inviter 还是 invitee）
                let partnerKey = (rel.userA == self.userId) ? inviteeId : rel.userA
                self.actualPartnerKey = partnerKey
                self.lock.unlock()
                Log.info("HTTPRealtime", "pair_success 设置 partnerKey=\(partnerKey)")
            }
            onPairSuccess?(inviteeId)

        default:
            Log.warn("HTTPRealtime", "未处理的消息类型: \(type)")
        }
    }
}