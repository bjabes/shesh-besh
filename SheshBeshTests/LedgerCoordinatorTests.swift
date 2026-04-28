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

    @Test("AI rivalry starts or resumes a Medium AI match")
    @MainActor
    func aiRivalryStartsOrResumesMatch() async throws {
        let store = InMemoryLedgerStore()
        let coordinator = LedgerCoordinator(store: store)

        let firstMatch = try await coordinator.startAIRivalry(difficulty: .medium)
        let rival = try #require(coordinator.rival(for: firstMatch.rivalID))
        let secondMatch = try await coordinator.startAIRivalry(difficulty: .medium)
        let rivals = try await store.loadRivals()

        #expect(rivals.count == 1)
        #expect(rival.displayName == "Medium AI")
        #expect(rival.gameCenterPlayerID == nil)
        #expect(firstMatch.id == secondMatch.id)
        #expect(firstMatch.userPlayed == .white)
        #expect(firstMatch.state.config.targetScore == 7)
    }

    @Test("AI rivalry creates separate rivals per difficulty")
    @MainActor
    func aiRivalryCreatesSeparateRivalsPerDifficulty() async throws {
        let store = InMemoryLedgerStore()
        let coordinator = LedgerCoordinator(store: store)

        let easyMatch = try await coordinator.startAIRivalry(difficulty: .easy)
        let mediumMatch = try await coordinator.startAIRivalry(difficulty: .medium)
        let hardMatch = try await coordinator.startAIRivalry(difficulty: .hard)

        let easyRival = try #require(coordinator.rival(for: easyMatch.rivalID))
        let mediumRival = try #require(coordinator.rival(for: mediumMatch.rivalID))
        let hardRival = try #require(coordinator.rival(for: hardMatch.rivalID))

        #expect(easyRival.displayName == "Easy AI")
        #expect(mediumRival.displayName == "Medium AI")
        #expect(hardRival.displayName == "Hard AI")
        #expect(Set([easyRival.id, mediumRival.id, hardRival.id]).count == 3)

        let resumedEasy = try await coordinator.startAIRivalry(difficulty: .easy)
        let resumedHard = try await coordinator.startAIRivalry(difficulty: .hard)
        #expect(resumedEasy.id == easyMatch.id)
        #expect(resumedHard.id == hardMatch.id)
    }

    @Test("clearing active matches preserves rivals and completed records")
    @MainActor
    func clearActiveMatchesPreservesHistory() async throws {
        let rival = Rival(displayName: "Dan")
        let record = MatchRecord(
            rivalID: rival.id,
            userPlayed: .white,
            winner: .you,
            userScore: 7,
            rivalScore: 3,
            targetScore: 7,
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 200)
        )
        let active = ActiveMatch(
            rivalID: rival.id,
            userPlayed: .black,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 7))
        )
        let store = InMemoryLedgerStore(rivals: [rival], records: [record], activeMatches: [active])
        let coordinator = LedgerCoordinator(store: store)

        await coordinator.refresh()
        try await coordinator.clearActiveMatches([active])

        #expect(try await store.loadRivals() == [rival])
        #expect(try await store.loadMatchRecords(rivalID: rival.id) == [record])
        #expect(try await store.loadActiveMatch(rivalID: rival.id) == nil)
        #expect(coordinator.ledger(for: rival.id)?.totalMatches == 1)
        #expect(coordinator.ledger(for: rival.id)?.activeMatch == nil)
    }

    @Test("clearing multiple active matches leaves unselected active matches")
    @MainActor
    func clearMultipleActiveMatches() async throws {
        let firstRival = Rival(displayName: "Dan")
        let secondRival = Rival(displayName: "Lee")
        let thirdRival = Rival(displayName: "Mira")
        let firstActive = ActiveMatch(
            rivalID: firstRival.id,
            userPlayed: .white,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 3))
        )
        let secondActive = ActiveMatch(
            rivalID: secondRival.id,
            userPlayed: .black,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 5))
        )
        let thirdActive = ActiveMatch(
            rivalID: thirdRival.id,
            userPlayed: .white,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 7))
        )
        let store = InMemoryLedgerStore(
            rivals: [firstRival, secondRival, thirdRival],
            activeMatches: [firstActive, secondActive, thirdActive]
        )
        let coordinator = LedgerCoordinator(store: store)

        await coordinator.refresh()
        try await coordinator.clearActiveMatches([firstActive, secondActive])

        #expect(try await store.loadActiveMatch(rivalID: firstRival.id) == nil)
        #expect(try await store.loadActiveMatch(rivalID: secondRival.id) == nil)
        #expect(try await store.loadActiveMatch(rivalID: thirdRival.id) == thirdActive)
        #expect(coordinator.ledger(for: thirdRival.id)?.activeMatch == thirdActive)
    }

    @Test("deleting clean rival removes the rival")
    @MainActor
    func deleteCleanRival() async throws {
        let store = InMemoryLedgerStore()
        let coordinator = LedgerCoordinator(store: store)
        let rival = try await coordinator.addRival(displayName: "Dan")

        try await coordinator.deleteRival(rival)

        #expect(try await store.loadRivals().isEmpty)
        #expect(coordinator.ledger(for: rival.id) == nil)
    }

    @Test("deleting rival with active local match clears match and rival")
    @MainActor
    func deleteRivalWithActiveLocalMatch() async throws {
        let rival = Rival(displayName: "Dan")
        let active = ActiveMatch(
            rivalID: rival.id,
            userPlayed: .white,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 7))
        )
        let store = InMemoryLedgerStore(rivals: [rival], activeMatches: [active])
        let coordinator = LedgerCoordinator(store: store)

        await coordinator.refresh()
        try await coordinator.deleteRival(rival)

        #expect(try await store.loadRivals().isEmpty)
        #expect(try await store.loadActiveMatch(rivalID: rival.id) == nil)
        #expect(coordinator.ledger(for: rival.id) == nil)
    }

    @Test("deleting rival with active Game Center match clears local match and rival")
    @MainActor
    func deleteRivalWithActiveGameCenterMatch() async throws {
        let rival = Rival(displayName: "Dan", gameCenterPlayerID: "dan-gc")
        let active = ActiveMatch(
            rivalID: rival.id,
            gameCenterMatchID: "gc-match-1",
            userPlayed: .black,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 7))
        )
        let store = InMemoryLedgerStore(rivals: [rival], activeMatches: [active])
        let coordinator = LedgerCoordinator(store: store)

        await coordinator.refresh()
        try await coordinator.deleteRival(rival)

        #expect(try await store.loadRivals().isEmpty)
        #expect(try await store.loadActiveMatch(rivalID: rival.id) == nil)
        #expect(coordinator.ledger(for: rival.id) == nil)
    }

    @Test("deleting rival with records requires explicit history deletion")
    @MainActor
    func deleteRivalWithRecordsRequiresConfirmation() async throws {
        let rival = Rival(displayName: "Dan")
        let record = completedRecord(rivalID: rival.id)
        let active = ActiveMatch(
            rivalID: rival.id,
            userPlayed: .white,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 3))
        )
        let store = InMemoryLedgerStore(rivals: [rival], records: [record], activeMatches: [active])
        let coordinator = LedgerCoordinator(store: store)

        await coordinator.refresh()
        await #expect(throws: LedgerStoreError.rivalHasHistory) {
            try await coordinator.deleteRival(rival)
        }
        #expect(try await store.loadRivals() == [rival])
        #expect(try await store.loadMatchRecords(rivalID: rival.id) == [record])
        #expect(try await store.loadActiveMatch(rivalID: rival.id) == active)

        try await coordinator.deleteRival(rival, deletingRecords: true)

        #expect(try await store.loadRivals().isEmpty)
        #expect(try await store.loadMatchRecords(rivalID: rival.id).isEmpty)
        #expect(try await store.loadActiveMatch(rivalID: rival.id) == nil)
        #expect(coordinator.ledger(for: rival.id) == nil)
    }

    @Test("refresh purges pending Game Center placeholder rivalries")
    @MainActor
    func refreshPurgesPendingGameCenterPlaceholderRivalries() async throws {
        let rival = Rival(
            displayName: "Opponent",
            gameCenterPlayerID: "pending-gc-match-1",
            gameCenterDisplayName: "Opponent"
        )
        let active = ActiveMatch(
            rivalID: rival.id,
            gameCenterMatchID: "gc-match-1",
            userPlayed: .white,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 7))
        )
        let store = InMemoryLedgerStore(rivals: [rival], activeMatches: [active])
        let coordinator = LedgerCoordinator(store: store)

        await coordinator.refresh()

        #expect(try await store.loadRivals().isEmpty)
        #expect(try await store.loadActiveMatch(rivalID: rival.id) == nil)
        #expect(coordinator.ledgers.isEmpty)
    }

    @Test("refresh preserves resolved Game Center rival named Opponent")
    @MainActor
    func refreshPreservesResolvedGameCenterRivalNamedOpponent() async throws {
        let rival = Rival(
            displayName: "Opponent",
            gameCenterPlayerID: "real-game-center-player",
            gameCenterDisplayName: "Opponent"
        )
        let active = ActiveMatch(
            rivalID: rival.id,
            gameCenterMatchID: "gc-match-1",
            userPlayed: .white,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 7))
        )
        let store = InMemoryLedgerStore(rivals: [rival], activeMatches: [active])
        let coordinator = LedgerCoordinator(store: store)

        await coordinator.refresh()

        #expect(try await store.loadRivals() == [rival])
        #expect(try await store.loadActiveMatch(rivalID: rival.id) == active)
        #expect(coordinator.ledger(for: rival.id)?.activeMatch == active)
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

private func completedRecord(rivalID: Rival.ID) -> MatchRecord {
    MatchRecord(
        rivalID: rivalID,
        userPlayed: .white,
        winner: .you,
        userScore: 7,
        rivalScore: 3,
        targetScore: 7,
        startedAt: Date(timeIntervalSince1970: 100),
        completedAt: Date(timeIntervalSince1970: 200)
    )
}
