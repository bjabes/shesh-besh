import Foundation

public func makeLedger(
    rival: Rival,
    records: [MatchRecord],
    activeMatch: ActiveMatch?
) -> RivalLedger {
    let relevantRecords = records.filter { $0.rivalID == rival.id }
    let sortedRecords = relevantRecords.sorted { lhs, rhs in
        if lhs.completedAt == rhs.completedAt {
            return lhs.startedAt > rhs.startedAt
        }
        return lhs.completedAt > rhs.completedAt
    }

    let userWins = relevantRecords.filter { $0.winner == .you }.count
    let rivalWins = relevantRecords.filter { $0.winner == .rival }.count
    let activeMatch = activeMatch?.rivalID == rival.id ? activeMatch : nil

    return RivalLedger(
        rival: rival,
        userWins: userWins,
        rivalWins: rivalWins,
        totalMatches: relevantRecords.count,
        currentStreak: currentStreak(in: sortedRecords),
        lastPlayedAt: sortedRecords.first?.completedAt,
        activeMatch: activeMatch
    )
}

private func currentStreak(in records: [MatchRecord]) -> Streak {
    guard let first = records.first else { return .none }

    var count = 0
    for record in records {
        guard record.winner == first.winner else { break }
        count += 1
    }

    return Streak(holder: first.winner, count: count)
}
