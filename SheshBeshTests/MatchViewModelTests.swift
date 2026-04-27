import SheshBeshApp
import SheshBeshGame
import Testing

@Suite("Match view model")
struct MatchViewModelTests {
    @Test("default match is a one point Local AI quick match")
    @MainActor
    func defaultMatchIsLocalAIQuickMatch() {
        let viewModel = MatchViewModel(isOpponentAutoplayEnabled: false)

        #expect(viewModel.state.config.targetScore == 1)
        #expect(viewModel.localPlayer == .white)
        #expect(viewModel.opponentName == "Local AI")
    }

    @Test("opening roll is applied through the engine")
    @MainActor
    func openingRollUsesEngine() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        viewModel.rollOpeningDice()

        guard case .awaitingMove(let turn) = viewModel.state.game.phase else {
            Issue.record("Expected opening roll to begin a move turn.")
            return
        }

        #expect(turn.player == .white)
        #expect(turn.roll.die1 == 6)
        #expect(turn.roll.die2 == 1)
        #expect(viewModel.lastError == nil)
    }

    @Test("legal destinations are sourced from reducer legal actions")
    @MainActor
    func legalDestinationsComeFromEngine() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        viewModel.rollOpeningDice()

        let source = MoveSource.point(PointID(rawValue: 24)!)
        let destinations = viewModel.legalDestinations(from: source)

        #expect(destinations.contains(.point(PointID(rawValue: 18)!)))
        #expect(destinations.contains(.point(PointID(rawValue: 23)!)))
    }

    @Test("applying a point move updates board state")
    @MainActor
    func applyMoveUpdatesState() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        viewModel.rollOpeningDice()

        let moved = viewModel.applyMove(
            from: .point(PointID(rawValue: 24)!),
            to: .point(PointID(rawValue: 18)!)
        )

        #expect(moved)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 24)!).count == 1)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 18)!).owner == .white)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 18)!).count == 1)
    }

    @Test("offering resignation enters resignation response phase")
    @MainActor
    func offerResignationWhenAllowed() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        viewModel.rollOpeningDice()
        viewModel.offerResignationIfAllowed(.gammon)

        guard case .awaitingResignationResponse(let offer) = viewModel.state.game.phase else {
            Issue.record("Expected resignation response phase after resignation offer.")
            return
        }

        #expect(offer.offeredBy == .white)
        #expect(offer.winKind == .gammon)
        #expect(viewModel.lastError == nil)
    }

    @Test("invalid move is surfaced as a friendly message")
    @MainActor
    func invalidMoveMessageIsFriendly() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        viewModel.rollOpeningDice()
        viewModel.send(.move(Move(player: .white, source: .point(PointID(rawValue: 1)!), destination: .point(PointID(rawValue: 2)!), die: 1)))

        #expect(viewModel.lastError == "That move is not legal for the current dice.")
    }

    @Test("opponent double offer is exposed for the local player")
    @MainActor
    func opponentDoubleOfferIsExposedForLocalPlayer() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7),
            isOpponentAutoplayEnabled: false
        )

        advanceToOpponentRoll(viewModel)
        viewModel.send(.offerDouble(.black))

        let offer = viewModel.doubleOfferForLocalPlayer
        #expect(offer?.offeredBy == .black)
        #expect(offer?.proposedValue == 2)
        #expect(offer?.previousCubeValue == 1)
        #expect(viewModel.isLocalTurn)
    }

    @Test("taking an opponent double uses the reducer action")
    @MainActor
    func takeOpponentDoubleUsesReducerAction() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7),
            isOpponentAutoplayEnabled: false
        )

        advanceToOpponentRoll(viewModel)
        viewModel.send(.offerDouble(.black))
        viewModel.takeDoubleIfAllowed()

        #expect(viewModel.state.game.cube.value == 2)
        #expect(viewModel.state.game.cube.owner == .white)
        guard case .awaitingRoll(.black) = viewModel.state.game.phase else {
            Issue.record("Expected play to resume at the opponent's roll after taking.")
            return
        }
    }

    @Test("opening roll can hand first turn to Local AI")
    @MainActor
    func openingRollCanHandFirstTurnToLocalAI() async {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([1, 6])),
            config: .tournament(targetScore: 1),
            opponentController: LocalAIOpponent(randomIndex: { _ in 0 }),
            opponentDelay: {}
        )

        viewModel.rollOpeningDice()

        let returnedToWhite = await waitUntil {
            if case .awaitingRoll(.white) = viewModel.state.game.phase {
                return true
            }
            return false
        }

        #expect(returnedToWhite)
        #expect(viewModel.lastError == nil)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 1)!).count < 2)
        #expect(!viewModel.isOpponentThinking)
    }

    @Test("Local AI rolls and moves after local turn ends")
    @MainActor
    func localAIRollsAndMovesAfterLocalTurnEnds() async {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1, 3, 2])),
            config: .tournament(targetScore: 1),
            opponentController: LocalAIOpponent(randomIndex: { _ in 0 }),
            opponentDelay: {}
        )

        viewModel.rollOpeningDice()
        #expect(viewModel.applyMove(from: .point(PointID(rawValue: 24)!), to: .point(PointID(rawValue: 18)!)))
        #expect(viewModel.applyMove(from: .point(PointID(rawValue: 24)!), to: .point(PointID(rawValue: 23)!)))

        let returnedToWhite = await waitUntil {
            if case .awaitingRoll(.white) = viewModel.state.game.phase {
                return true
            }
            return false
        }

        #expect(returnedToWhite)
        #expect(viewModel.lastError == nil)
        #expect(viewModel.pipCount(for: .black) < 167)
    }

    @Test("Local AI passes when blocked")
    @MainActor
    func localAIPassesWhenBlocked() async throws {
        var board = Board.empty()
        try board.setPoint(PointID(rawValue: 5)!, owner: .white, count: 2)
        try board.setPoint(PointID(rawValue: 6)!, owner: .white, count: 2)
        try board.setPoint(PointID(rawValue: 24)!, owner: .white, count: 11)
        try board.setPoint(PointID(rawValue: 1)!, owner: .black, count: 14)
        try board.setBar(for: .black, count: 1)

        let roll = try DiceRoll(die1: 5, die2: 6)
        let state = MatchState(
            config: .tournament(targetScore: 1),
            game: GameState(
                board: board,
                phase: .awaitingMove(TurnState(player: .black, roll: roll, remainingDice: roll.playableDice))
            )
        )
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([1, 1])),
            initialState: state,
            opponentDelay: {}
        )

        let passed = await waitUntil {
            if case .awaitingRoll(.white) = viewModel.state.game.phase {
                return true
            }
            return false
        }

        #expect(passed)
        #expect(viewModel.lastError == nil)
        #expect(viewModel.phaseTitle == "Local AI had no legal moves")
    }

    @Test("Local AI passes after rolling blocked bar entries")
    @MainActor
    func localAIPassesAfterRollingBlockedBarEntries() async throws {
        var board = Board.empty()
        try board.setPoint(PointID(rawValue: 5)!, owner: .white, count: 2)
        try board.setPoint(PointID(rawValue: 6)!, owner: .white, count: 2)
        try board.setPoint(PointID(rawValue: 24)!, owner: .white, count: 11)
        try board.setPoint(PointID(rawValue: 1)!, owner: .black, count: 14)
        try board.setBar(for: .black, count: 1)

        let state = MatchState(
            config: .tournament(targetScore: 1),
            game: GameState(
                board: board,
                phase: .awaitingRoll(.black)
            )
        )
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([5, 6])),
            initialState: state,
            opponentDelay: {}
        )

        let passed = await waitUntil {
            if case .awaitingRoll(.white) = viewModel.state.game.phase {
                return true
            }
            return false
        }

        #expect(passed)
        #expect(viewModel.lastError == nil)
        #expect(viewModel.phaseTitle == "Local AI had no legal moves")
    }

    @Test("Local AI prefers the biggest pip reduction and breaks ties deterministically")
    @MainActor
    func localAIPipBiasedSelectionUsesDeterministicTieBreaking() throws {
        let roll = try DiceRoll(die1: 6, die2: 1)
        let state = MatchState(
            config: .tournament(targetScore: 1),
            game: GameState(
                board: .initial(),
                phase: .awaitingMove(TurnState(player: .black, roll: roll, remainingDice: roll.playableDice))
            )
        )
        let legalActions = MatchEngine.legalActions(in: state)
        let opponent = LocalAIOpponent(randomIndex: { upperBound in upperBound - 1 })

        let move = try #require(opponent.selectPipBiasedMove(
            for: .black,
            in: state,
            legalActions: legalActions,
            pipCounts: [.white: 167, .black: 167]
        ))

        #expect(move.die == 6)
        #expect(move.source == .point(PointID(rawValue: 17)!))
        #expect(move.destination == .point(PointID(rawValue: 23)!))
    }

    @Test("Local AI takes normal doubles and drops only clearly bad match-deciding doubles")
    @MainActor
    func localAICubeResponsePolicy() {
        let state = MatchState(
            config: .tournament(targetScore: 1),
            game: GameState(
                board: .initial(),
                phase: .awaitingCubeResponse(CubeOffer(offeredBy: .white, proposedValue: 2, previousCubeValue: 1))
            )
        )
        let legalActions = MatchEngine.legalActions(in: state)
        let opponent = LocalAIOpponent(randomIndex: { _ in 0 })

        #expect(opponent.action(
            as: .black,
            in: state,
            legalActions: legalActions,
            pipCounts: [.white: 120, .black: 150]
        ) == .takeDouble(.black))

        #expect(opponent.action(
            as: .black,
            in: state,
            legalActions: legalActions,
            pipCounts: [.white: 100, .black: 150]
        ) == .dropDouble(.black))
    }

    @Test("Local AI quick match can complete from automated legal play")
    @MainActor
    func localAIQuickMatchCompletesFromLegalPlay() async {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: CyclingDiceRoller()),
            config: .tournament(targetScore: 1),
            opponentController: LocalAIOpponent(randomIndex: { _ in 0 }),
            opponentDelay: {}
        )

        var actionCount = 0
        while viewModel.state.completion == nil, actionCount < 1_000 {
            actionCount += 1
            switch viewModel.state.game.phase {
            case .awaitingOpeningRoll:
                viewModel.rollOpeningDice()
            case .awaitingRoll(.white):
                viewModel.rollDiceIfAllowed()
            case .awaitingMove(let turn) where turn.player == .white:
                if let move = viewModel.legalMoves.first(where: { $0.player == .white }) {
                    viewModel.send(.move(move))
                } else {
                    viewModel.passIfAllowed()
                }
            case .awaitingCubeResponse(let offer) where offer.offeredBy.opponent == .white:
                viewModel.send(.takeDouble(.white))
            case .awaitingResignationResponse(let offer) where offer.offeredBy.opponent == .white:
                viewModel.send(.rejectResignation(.white))
            default:
                await Task.yield()
            }

            #expect(viewModel.lastError == nil)
        }

        #expect(viewModel.state.completion != nil)
        #expect(actionCount < 1_000)
    }

    @Test("completion callback fires once when match completion appears")
    @MainActor
    func completionCallbackFiresOnce() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: MatchConfig(targetScore: 1, usesDoublingCube: false)
        )
        var completionCount = 0

        viewModel.onCompletion = { _ in
            completionCount += 1
        }

        viewModel.rollOpeningDice()
        viewModel.send(.offerResignation(.white, .single))
        viewModel.send(.acceptResignation(.black))
        viewModel.rollDiceIfAllowed()

        #expect(completionCount == 1)
    }
}

@MainActor
private func advanceToOpponentRoll(_ viewModel: MatchViewModel) {
    viewModel.rollOpeningDice()
    _ = viewModel.applyMove(
        from: .point(PointID(rawValue: 24)!),
        to: .point(PointID(rawValue: 18)!)
    )
    _ = viewModel.applyMove(
        from: .point(PointID(rawValue: 24)!),
        to: .point(PointID(rawValue: 23)!)
    )
}

private final class ScriptedDiceRoller: DiceRolling, @unchecked Sendable {
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

private final class CyclingDiceRoller: DiceRolling, @unchecked Sendable {
    private let values = [6, 1, 3, 2, 5, 4, 2, 2, 6, 5, 4, 1]
    private var index = 0

    func rollDie() -> Int {
        let value = values[index % values.count]
        index += 1
        return value
    }
}

@MainActor
private func waitUntil(_ predicate: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<50 {
        if predicate() {
            return true
        }
        await Task.yield()
    }
    return predicate()
}
