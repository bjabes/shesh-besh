import Foundation
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

    @Test("refresh recovers completed active match after relaunch")
    @MainActor
    func refreshFinalizesCompletedActiveMatch() async throws {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let completedAt = Date(timeIntervalSinceReferenceDate: 1_100)
        let rival = Rival(displayName: "Dan")
        let state = MatchState(
            config: MatchConfig(targetScore: 1, usesDoublingCube: false),
            score: MatchScore(white: 1, black: 0),
            game: GameState(phase: .gameOver(GameResult(winner: .white, winKind: .single, cubeValue: 1))),
            completion: MatchCompletion(winner: .white, finalScore: MatchScore(white: 1, black: 0))
        )
        let active = ActiveMatch(
            rivalID: rival.id,
            userPlayed: .white,
            state: state,
            startedAt: startedAt,
            lastUpdatedAt: completedAt
        )
        let store = InMemoryLedgerStore(rivals: [rival], activeMatches: [active])
        let coordinator = LedgerCoordinator(store: store)

        await coordinator.refresh()

        let records = try await store.loadMatchRecords(rivalID: rival.id)
        let record = try #require(records.first)

        #expect(records.count == 1)
        #expect(record.winner == MatchOutcome.you)
        #expect(record.userScore == 1)
        #expect(record.rivalScore == 0)
        #expect(record.completedAt == completedAt)
        #expect(record.finalSnapshot == state)
        #expect(try await store.loadActiveMatch(rivalID: rival.id) == nil)
        #expect(coordinator.ledger(for: rival.id)?.userWins == 1)
    }

    @Test("Game Center completion is idempotent by match ID and game index")
    @MainActor
    func gameCenterCompletionIsIdempotent() async throws {
        let store = InMemoryLedgerStore()
        let coordinator = LedgerCoordinator(store: store)
        let rival = Rival(displayName: "Dan", gameCenterPlayerID: "dan-gc")
        let state = MatchState(
            config: MatchConfig(targetScore: 1, usesDoublingCube: false),
            score: MatchScore(white: 1, black: 0),
            game: GameState(phase: .gameOver(GameResult(winner: .white, winKind: .single, cubeValue: 1))),
            completion: MatchCompletion(winner: .white, finalScore: MatchScore(white: 1, black: 0))
        )
        let active = ActiveMatch(
            rivalID: rival.id,
            gameCenterMatchID: "gc-match-1",
            gameIndex: 0,
            userPlayed: .white,
            state: state
        )

        try await coordinator.saveGameCenterMatch(active, rival: rival)
        try await coordinator.recordCompletion(of: active)
        try await coordinator.recordCompletion(of: active)

        let records = try await store.loadMatchRecords(rivalID: rival.id)

        #expect(records.count == 1)
        #expect(records.first?.gameCenterMatchID == "gc-match-1")
        #expect(records.first?.gameIndex == 0)
    }

    @Test("AI rivalry starts or resumes a Local AI quick match")
    @MainActor
    func aiRivalryStartsOrResumesQuickMatch() async throws {
        let store = InMemoryLedgerStore()
        let coordinator = LedgerCoordinator(store: store)

        let firstMatch = try await coordinator.startAIRivalry()
        let rival = try #require(coordinator.rival(for: firstMatch.rivalID))
        let secondMatch = try await coordinator.startAIRivalry()
        let rivals = try await store.loadRivals()

        #expect(rivals.count == 1)
        #expect(rival.displayName == "Local AI")
        #expect(rival.gameCenterPlayerID == nil)
        #expect(firstMatch.id == secondMatch.id)
        #expect(firstMatch.userPlayed == .white)
        #expect(firstMatch.state.config.targetScore == 1)
    }

    @Test("AI rivalry renames legacy Random Dan rival to Local AI")
    @MainActor
    func aiRivalryRenamesLegacyRandomDanRival() async throws {
        let legacyRival = Rival(displayName: "Random Dan")
        let store = InMemoryLedgerStore(rivals: [legacyRival])
        let coordinator = LedgerCoordinator(store: store)

        let match = try await coordinator.startAIRivalry()
        let rivals = try await store.loadRivals()

        #expect(rivals.count == 1)
        #expect(rivals.first?.id == legacyRival.id)
        #expect(rivals.first?.displayName == "Local AI")
        #expect(match.rivalID == legacyRival.id)
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
