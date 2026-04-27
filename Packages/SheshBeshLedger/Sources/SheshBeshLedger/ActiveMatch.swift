import Foundation
import SheshBeshGame

public struct ActiveMatch: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let rivalID: Rival.ID
    public let gameCenterMatchID: String?
    public let gameIndex: Int
    public let userPlayed: Player
    public var state: MatchState
    public let startedAt: Date
    public var lastUpdatedAt: Date

    public init(
        id: UUID = UUID(),
        rivalID: Rival.ID,
        gameCenterMatchID: String? = nil,
        gameIndex: Int = 0,
        userPlayed: Player,
        state: MatchState,
        startedAt: Date = Date(),
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.rivalID = rivalID
        self.gameCenterMatchID = gameCenterMatchID
        self.gameIndex = gameIndex
        self.userPlayed = userPlayed
        self.state = state
        self.startedAt = startedAt
        self.lastUpdatedAt = lastUpdatedAt
    }
}
