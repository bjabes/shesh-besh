import Foundation
import SheshBeshGame
import SheshBeshLedger
import Testing

@Suite("Ledger aggregation")
struct LedgerAggregationTests {
    @Test("empty ledger has no totals or last played date")
    func emptyLedger() {
        let rival = Rival(id: UUID(), displayName: "Dan", createdAt: date(0))

        let ledger = makeLedger(rival: rival, records: [], activeMatch: nil)

        #expect(ledger.userWins == 0)
        #expect(ledger.rivalWins == 0)
        #expect(ledger.totalMatches == 0)
        #expect(ledger.currentStreak == .none)
        #expect(ledger.lastPlayedAt == nil)
        #expect(ledger.activeMatch == nil)
    }

    @Test("active match is attached without changing completed totals")
    func activeMatchWithoutRecords() {
        let rival = Rival(id: UUID(), displayName: "Dan", createdAt: date(0))
        let activeMatch = ActiveMatch(
            rivalID: rival.id,
            userPlayed: .white,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 7)),
            startedAt: date(1),
            lastUpdatedAt: date(2)
        )

        let ledger = makeLedger(rival: rival, records: [], activeMatch: activeMatch)

        #expect(ledger.totalMatches == 0)
        #expect(ledger.currentStreak.count == 0)
        #expect(ledger.lastPlayedAt == nil)
        #expect(ledger.activeMatch == activeMatch)
    }

    @Test("single record produces one-match streak")
    func singleRecord() {
        let rival = Rival(id: UUID(), displayName: "Dan", createdAt: date(0))
        let record = makeRecord(rivalID: rival.id, winner: .you, completedAt: date(4))

        let ledger = makeLedger(rival: rival, records: [record], activeMatch: nil)

        #expect(ledger.userWins == 1)
        #expect(ledger.rivalWins == 0)
        #expect(ledger.totalMatches == 1)
        #expect(ledger.currentStreak == Streak(holder: .you, count: 1))
        #expect(ledger.lastPlayedAt == date(4))
    }

    @Test("alternating wins produce a one-match current streak")
    func alternatingWins() {
        let rival = Rival(id: UUID(), displayName: "Dan", createdAt: date(0))
        let records = [
            makeRecord(rivalID: rival.id, winner: .you, completedAt: date(1)),
            makeRecord(rivalID: rival.id, winner: .rival, completedAt: date(2)),
            makeRecord(rivalID: rival.id, winner: .you, completedAt: date(3)),
        ]

        let ledger = makeLedger(rival: rival, records: records, activeMatch: nil)

        #expect(ledger.userWins == 2)
        #expect(ledger.rivalWins == 1)
        #expect(ledger.currentStreak == Streak(holder: .you, count: 1))
    }

    @Test("input records are sorted before streak derivation")
    func sortsOutOfOrderRecords() {
        let rival = Rival(id: UUID(), displayName: "Dan", createdAt: date(0))
        let records = [
            makeRecord(rivalID: rival.id, winner: .rival, completedAt: date(1)),
            makeRecord(rivalID: rival.id, winner: .you, completedAt: date(4)),
            makeRecord(rivalID: rival.id, winner: .you, completedAt: date(3)),
            makeRecord(rivalID: rival.id, winner: .rival, completedAt: date(2)),
        ]

        let ledger = makeLedger(rival: rival, records: records, activeMatch: nil)

        #expect(ledger.currentStreak == Streak(holder: .you, count: 2))
        #expect(ledger.lastPlayedAt == date(4))
    }

    @Test("records and active matches for other rivals are ignored")
    func filtersMixedRivalInput() {
        let rival = Rival(id: UUID(), displayName: "Dan", createdAt: date(0))
        let otherRival = Rival(id: UUID(), displayName: "Maya", createdAt: date(0))
        let activeMatch = ActiveMatch(
            rivalID: otherRival.id,
            userPlayed: .white,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 7))
        )
        let records = [
            makeRecord(rivalID: rival.id, winner: .you, completedAt: date(1)),
            makeRecord(rivalID: otherRival.id, winner: .rival, completedAt: date(2)),
        ]

        let ledger = makeLedger(rival: rival, records: records, activeMatch: activeMatch)

        #expect(ledger.userWins == 1)
        #expect(ledger.rivalWins == 0)
        #expect(ledger.totalMatches == 1)
        #expect(ledger.activeMatch == nil)
    }
}

private func makeRecord(
    rivalID: Rival.ID,
    winner: MatchOutcome,
    completedAt: Date
) -> MatchRecord {
    MatchRecord(
        rivalID: rivalID,
        userPlayed: .white,
        winner: winner,
        userScore: winner == .you ? 7 : 3,
        rivalScore: winner == .you ? 3 : 7,
        targetScore: 7,
        startedAt: completedAt.addingTimeInterval(-600),
        completedAt: completedAt
    )
}

private func date(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000 + offset)
}
