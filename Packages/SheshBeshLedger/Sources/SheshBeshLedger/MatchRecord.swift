import Foundation
import SheshBeshGame

public struct MatchRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let rivalID: Rival.ID
    public let userPlayed: Player
    public let winner: MatchOutcome
    public let userScore: Int
    public let rivalScore: Int
    public let targetScore: Int
    public let startedAt: Date
    public let completedAt: Date
    public let finalSnapshot: MatchState?

    public init(
        id: UUID = UUID(),
        rivalID: Rival.ID,
        userPlayed: Player,
        winner: MatchOutcome,
        userScore: Int,
        rivalScore: Int,
        targetScore: Int,
        startedAt: Date,
        completedAt: Date,
        finalSnapshot: MatchState? = nil
    ) {
        self.id = id
        self.rivalID = rivalID
        self.userPlayed = userPlayed
        self.winner = winner
        self.userScore = userScore
        self.rivalScore = rivalScore
        self.targetScore = targetScore
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.finalSnapshot = finalSnapshot
    }
}
