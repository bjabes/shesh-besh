import Foundation

public struct RivalLedger: Equatable, Sendable {
    public let rival: Rival
    public let userWins: Int
    public let rivalWins: Int
    public let totalMatches: Int
    public let currentStreak: Streak
    public let lastPlayedAt: Date?
    public let activeMatch: ActiveMatch?

    public init(
        rival: Rival,
        userWins: Int,
        rivalWins: Int,
        totalMatches: Int,
        currentStreak: Streak,
        lastPlayedAt: Date?,
        activeMatch: ActiveMatch?
    ) {
        self.rival = rival
        self.userWins = userWins
        self.rivalWins = rivalWins
        self.totalMatches = totalMatches
        self.currentStreak = currentStreak
        self.lastPlayedAt = lastPlayedAt
        self.activeMatch = activeMatch
    }
}

public struct Streak: Equatable, Sendable {
    public let holder: MatchOutcome
    public let count: Int

    public init(holder: MatchOutcome, count: Int) {
        self.holder = holder
        self.count = count
    }

    public static let none = Streak(holder: .you, count: 0)
}
