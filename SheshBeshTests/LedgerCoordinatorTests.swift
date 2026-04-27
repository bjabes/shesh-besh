import SheshBeshApp
import SheshBeshGame
import SheshBeshLedger
import Testing

@Suite("Ledger coordinator")
struct LedgerCoordinatorTests {
    @Test("completed active match appends one record and clears active match")
    @MainActor
    func completionRecordsMatchAndClearsActive() async throws {
        let store = InMemoryLedgerStore()
        let coordinator = LedgerCoordinator(store: store)
        let rival = try await coordinator.addRival(displayName: "Dan")
        let active = try await coordinator.startMatch(
            against: rival,
            userPlays: .white,
            config: MatchConfig(targetScore: 1, usesDoublingCube: false)
        )

        let engine = MatchEngine(diceRoller: CompletionDiceRoller([6, 1]))
        var state = active.state
        state = try engine.apply(action: .rollOpeningDice, to: state)
        state = try engine.apply(action: .offerResignation(.white, .single), to: state)
        state = try engine.apply(action: .acceptResignation(.black), to: state)

        let completed = ActiveMatch(
            id: active.id,
            rivalID: active.rivalID,
            userPlayed: active.userPlayed,
            state: state,
            startedAt: active.startedAt,
            lastUpdatedAt: active.lastUpdatedAt
        )

        try await coordinator.saveActiveMatch(completed)
        try await coordinator.recordCompletion(of: completed)

        let records = try await store.loadMatchRecords(rivalID: rival.id)
        let record = try #require(records.first)

        #expect(records.count == 1)
        #expect(record.rivalID == rival.id)
        #expect(record.userPlayed == .white)
        #expect(record.winner == .rival)
        #expect(record.userScore == 0)
        #expect(record.rivalScore == 1)
        #expect(record.targetScore == 1)
        #expect(record.finalSnapshot == state)
        #expect(try await store.loadActiveMatch(rivalID: rival.id) == nil)
        #expect(coordinator.ledger(for: rival.id)?.rivalWins == 1)
    }
}

private final class CompletionDiceRoller: DiceRolling, @unchecked Sendable {
    private let values: [Int]
    private var index = 0

    init(_ values: [Int]) {
        self.values = values
    }

    func rollDie() -> Int {
        let value = values[index % values.count]
        index += 1
        return value
    }
}
