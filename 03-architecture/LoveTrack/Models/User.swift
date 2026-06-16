import Foundation

// MARK: - User

/// 单个用户（"我"和"伴侣"两端共用）。
///
/// Firebase Auth 集成后，`id` 与 `Auth.auth().currentUser?.uid` 一一对应。
public struct User: Codable, Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public var displayName: String
    public var avatarURL: URL?
    public var deviceModel: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        displayName: String,
        avatarURL: URL? = nil,
        deviceModel: String = "iPhone",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.deviceModel = deviceModel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
