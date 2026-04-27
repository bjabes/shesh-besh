import Foundation

public struct Rival: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var displayName: String
    public var gameCenterPlayerID: String?
    public var gameCenterDisplayName: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        gameCenterPlayerID: String? = nil,
        gameCenterDisplayName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.gameCenterPlayerID = gameCenterPlayerID
        self.gameCenterDisplayName = gameCenterDisplayName
        self.createdAt = createdAt
    }
}
