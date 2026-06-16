import Foundation

/// 情侣 / 亲密关系绑定关系。
///
/// 配对流程：
/// 1. A 在 App 内生成 6 位配对码
/// 2. B 输入配对码
/// 3. Cloud Function 校验后写入 `status: active`
/// 4. 双方都能看到对方位置
public struct Relationship: Codable, Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public var userA: String          // User.id
    public var userB: String          // User.id
    public var status: Status
    public var pairedAt: Date
    public var dissolvedAt: Date?

    public enum Status: String, Codable, Sendable {
        case pending     // 已生成配对码，等待对方加入
        case active      // 已配对
        case dissolved   // 已解除（保留 90 天后软删）
    }

    public init(
        id: String,
        userA: String,
        userB: String,
        status: Status = .pending,
        pairedAt: Date = Date(),
        dissolvedAt: Date? = nil
    ) {
        self.id = id
        self.userA = userA
        self.userB = userB
        self.status = status
        self.pairedAt = pairedAt
        self.dissolvedAt = dissolvedAt
    }
}
