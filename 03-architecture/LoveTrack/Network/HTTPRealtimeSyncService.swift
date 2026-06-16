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

        print("[HTTPRealtime] POST \(req.url?.absoluteString ?? "?") body=\(body)")

        do {
            let (data, resp) = try await session.data(for: req)
            print("[HTTPRealtime] got response, status=\((resp as? HTTPURLResponse)?.statusCode ?? 0)")
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
            print("[HTTPRealtime] bind OK: code=\(serverCode) userId=\(inviter.id)")

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
            print("[HTTPRealtime] URLError: \(urlError.code.rawValue) - \(urlError.localizedDescription)")
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
        lock.unlock()

        print("[HTTPRealtime] pair OK: \(inviterId) ↔ \(invitee.id)")
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
            self.lock.lock()
            var dict = self.locationStreams[userId] ?? [:]
            dict[id] = cont
            self.locationStreams[userId] = dict
            let initial = self.latestPartnerLocation[userId]
            self.lock.unlock()
            if let p = initial { cont.yield(p) }
            cont.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.locationStreams[userId]?.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    public func fetchTrackSegment(userId: String, date: Date) async throws -> TrackSegment? {
        // MVP 不实现后端轨迹拉取
        return nil
    }

    // MARK: - WebSocket

    /// 在 App 启动时提前连 WS（不依赖配对）
    public func bootstrapConnect() async {
        print("[HTTPRealtime] bootstrapConnect called")
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
        print("[HTTPRealtime] WebSocket connecting to \(url.absoluteString)")
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
            print("[HTTPRealtime] WebSocket error: \(error.localizedDescription)")
            isConnected = false
        }
    }

    private func handleServerMessage(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = msg["type"] as? String else {
            return
        }

        switch type {
        case "partner_location":
            guard let payload = msg["payload"] as? [String: Any],
                  let lat = payload["lat"] as? Double,
                  let lng = payload["lng"] as? Double else { return }
            let batteryLevel = payload["battery"] as? Double ?? 1.0
            let ts = payload["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
            let timestamp = Date(timeIntervalSince1970: ts / 1000)

            let point = LocationPoint(
                userId: "partner",
                lat: lat,
                lon: lng,
                altitude: 0,
                horizontalAccuracy: 0,
                verticalAccuracy: 0,
                speed: -1,
                course: -1,
                timestamp: timestamp,
                battery: BatteryInfo(level: batteryLevel, isCharging: false, isLowPower: false),
                source: .gps,
                sessionId: ""
            )
            lock.lock()
            latestPartnerLocation["partner"] = point
            let streams = locationStreams["partner"] ?? [:]
            lock.unlock()
            for cont in streams.values { cont.yield(point) }

        case "pong":
            print("[HTTPRealtime] pong received")

        case "pair_success":
            print("[HTTPRealtime] pair_success received!")
            let payload = msg["payload"] as? [String: Any] ?? [:]
            let inviteeId = payload["inviteeId"] as? String ?? "partner"
            // 更新本地状态
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
                self.lock.unlock()
            }
            onPairSuccess?(inviteeId)

        default:
            break
        }
    }
}