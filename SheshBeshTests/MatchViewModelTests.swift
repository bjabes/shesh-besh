import SheshBeshApp
import SheshBeshGame
import Testing

@Suite("Match view model")
struct MatchViewModelTests {
    @Test("default match is a one point Medium AI quick match")
    @MainActor
    func defaultMatchIsMediumAIQuickMatch() {
        let viewModel = MatchViewModel(isOpponentAutoplayEnabled: false)

        #expect(viewModel.state.config.targetScore == 1)
        #expect(viewModel.localPlayer == .white)
        #expect(viewModel.opponentName == "Medium AI")
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
        #expect(viewModel.isTurnDraftPending)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 24)!).count == 1)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 18)!).owner == .white)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 18)!).count == 1)
    }

    @Test("drafted checker moves do not notify storage before submit")
    @MainActor
    func draftedCheckerMovesDoNotNotifyBeforeSubmit() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7),
            isOpponentAutoplayEnabled: false
        )

        viewModel.rollOpeningDice()

        var stateChangeCount = 0
        viewModel.onStateChange = { _ in
            stateChangeCount += 1
        }

        #expect(viewModel.applyMove(from: .point(PointID(rawValue: 24)!), to: .point(PointID(rawValue: 18)!)))

        #expect(viewModel.isTurnDraftPending)
        #expect(stateChangeCount == 0)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 24)!).count == 1)
    }

    @Test("undo restores the previous drafted move state")
    @MainActor
    func undoRestoresPreviousDraftState() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7),
            isOpponentAutoplayEnabled: false
        )

        viewModel.rollOpeningDice()
        let rolledState = viewModel.state
        let rolledLayout = viewModel.checkerLayout

        #expect(viewModel.applyMove(from: .point(PointID(rawValue: 24)!), to: .point(PointID(rawValue: 18)!)))
        viewModel.undoLastMove()

        #expect(viewModel.state == rolledState)
        #expect(viewModel.checkerLayout == rolledLayout)
        #expect(!viewModel.isTurnDraftPending)
        #expect(!viewModel.canUndoTurnMove)
        #expect(viewModel.lastError == nil)
    }

    @Test("submit commits a completed local turn once")
    @MainActor
    func submitCommitsCompletedLocalTurnOnce() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7),
            isOpponentAutoplayEnabled: false
        )

        viewModel.rollOpeningDice()

        var stateChangeCount = 0
        viewModel.onStateChange = { _ in
            stateChangeCount += 1
        }

        #expect(viewModel.applyMove(from: .point(PointID(rawValue: 24)!), to: .point(PointID(rawValue: 18)!)))
        #expect(viewModel.applyMove(from: .point(PointID(rawValue: 24)!), to: .point(PointID(rawValue: 23)!)))
        #expect(viewModel.canSubmitTurn)

        #expect(viewModel.submitTurnIfAllowed())

        #expect(stateChangeCount == 1)
        #expect(!viewModel.isTurnDraftPending)
        guard case .awaitingRoll(.black) = viewModel.state.game.phase else {
            Issue.record("Expected submitted turn to pass to black's roll.")
            return
        }
    }

    @Test("submit is rejected while local legal moves remain")
    @MainActor
    func submitIsRejectedWhileMovesRemain() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7),
            isOpponentAutoplayEnabled: false
        )

        viewModel.rollOpeningDice()
        var stateChangeCount = 0
        viewModel.onStateChange = { _ in
            stateChangeCount += 1
        }

        #expect(viewModel.applyMove(from: .point(PointID(rawValue: 24)!), to: .point(PointID(rawValue: 18)!)))
        #expect(!viewModel.submitTurnIfAllowed())

        #expect(viewModel.isTurnDraftPending)
        #expect(stateChangeCount == 0)
        #expect(viewModel.lastError == "Finish all legal moves before submitting.")
    }

    @Test("game ending checker move completes only after submit and can be undone")
    @MainActor
    func gameEndingMoveCompletesOnlyAfterSubmitAndCanBeUndone() throws {
        var board = Board.empty()
        try board.setPoint(PointID(rawValue: 1)!, owner: .white, count: 1)
        try board.setPoint(PointID(rawValue: 24)!, owner: .black, count: 15)
        try board.setBorneOff(for: .white, count: 14)

        let roll = try DiceRoll(die1: 1, die2: 1)
        let state = MatchState(
            config: .tournament(targetScore: 1),
            game: GameState(
                board: board,
                phase: .awaitingMove(TurnState(player: .white, roll: roll, remainingDice: [1]))
            )
        )
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([1, 1])),
            initialState: state,
            isOpponentAutoplayEnabled: false
        )
        var completionCount = 0
        viewModel.onCompletion = { _ in
            completionCount += 1
        }

        #expect(viewModel.applyMove(from: .point(PointID(rawValue: 1)!), to: .off))
        #expect(viewModel.state.completion?.winner == .white)
        #expect(completionCount == 0)

        viewModel.undoLastMove()
        #expect(viewModel.state.completion == nil)
        #expect(!viewModel.isTurnDraftPending)

        #expect(viewModel.applyMove(from: .point(PointID(rawValue: 1)!), to: .off))
        #expect(viewModel.submitTurnIfAllowed())
        #expect(completionCount == 1)
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
        #expect(viewModel.submitTurnIfAllowed())

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

    @Test("Local AI waits for local drafted turn submission")
    @MainActor
    func localAIWaitsForDraftSubmit() async {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1, 3, 2])),
            config: .tournament(targetScore: 1),
            opponentController: LocalAIOpponent(randomIndex: { _ in 0 }),
            opponentDelay: {}
        )

        viewModel.rollOpeningDice()
        #expect(viewModel.applyMove(from: .point(PointID(rawValue: 24)!), to: .point(PointID(rawValue: 18)!)))
        #expect(viewModel.applyMove(from: .point(PointID(rawValue: 24)!), to: .point(PointID(rawValue: 23)!)))

        for _ in 0..<5 {
            await Task.yield()
        }

        #expect(viewModel.isTurnDraftPending)
        #expect(viewModel.pipCount(for: .black) == 167)
        guard case .awaitingRoll(.black) = viewModel.state.game.phase else {
            Issue.record("Expected drafted local turn to wait at black's roll before submission.")
            return
        }

        #expect(viewModel.submitTurnIfAllowed())

        let returnedToWhite = await waitUntil {
            if case .awaitingRoll(.white) = viewModel.state.game.phase {
                return true
            }
            return false
        }

        #expect(returnedToWhite)
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
        #expect(viewModel.phaseTitle == "Medium AI had no legal moves")
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
        #expect(viewModel.phaseTitle == "Medium AI had no legal moves")
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

    @Test("Easy AI picks a random legal move and ignores pip bias")
    @MainActor
    func easyAIPicksRandomLegalMove() throws {
        let roll = try DiceRoll(die1: 6, die2: 1)
        let state = MatchState(
            config: .tournament(targetScore: 1),
            game: GameState(
                board: .initial(),
                phase: .awaitingMove(TurnState(player: .black, roll: roll, remainingDice: roll.playableDice))
            )
        )
        let legalActions = MatchEngine.legalActions(in: state)
        let easy = LocalAIOpponent(difficulty: .easy, randomIndex: { _ in 0 })

        let action = try #require(easy.action(
            as: .black,
            in: state,
            legalActions: legalActions,
            pipCounts: [.white: 167, .black: 167]
        ))

        guard case .move(let move) = action else {
            Issue.record("Expected easy AI to return a move action.")
            return
        }
        #expect(move.player == .black)
        #expect(legalActions.contains(.move(move)))
    }

    @Test("Hard AI prefers hitting an exposed opponent blot")
    @MainActor
    func hardAIHitsExposedBlot() throws {
        var board = Board.initial()
        try board.setPoint(PointID(rawValue: 24)!, owner: nil, count: 0)
        try board.setPoint(PointID(rawValue: 13)!, owner: .white, count: 6)
        try board.setPoint(PointID(rawValue: 22)!, owner: .white, count: 1)
        let roll = try DiceRoll(die1: 5, die2: 2)
        let state = MatchState(
            config: .tournament(targetScore: 1),
            game: GameState(
                board: board,
                phase: .awaitingMove(TurnState(player: .black, roll: roll, remainingDice: roll.playableDice))
            )
        )
        let legalActions = MatchEngine.legalActions(in: state)
        let hard = LocalAIOpponent(difficulty: .hard, randomIndex: { _ in 0 })

        let move = try #require(hard.selectMove(
            for: .black,
            in: state,
            legalActions: legalActions,
            pipCounts: [.white: 167, .black: 167]
        ))

        #expect(move.source == .point(PointID(rawValue: 17)!))
        #expect(move.destination == .point(PointID(rawValue: 22)!))
        #expect(move.die == 5)
    }

    @Test("Hard AI difficulty drives local autoplay move selection")
    @MainActor
    func hardAIDifficultyDrivesLocalAutoplayMoveSelection() async throws {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([1, 1])),
            localPlayer: .black,
            initialState: try autoplayDifficultyProbeState(),
            aiDifficulty: .hard,
            opponentDelay: {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            },
            raceAutoplayDelay: {}
        )

        #expect(viewModel.canStartLocalAutoplay)
        viewModel.startLocalAutoplay()

        let hitBlot = await waitUntil {
            viewModel.state.game.board.barCount(for: .white) == 1
        }

        #expect(hitBlot)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 22)!).owner == .black)
        #expect(viewModel.lastError == nil)
    }

    @Test("Local autoplay respects AI difficulty without opponent automation")
    @MainActor
    func localAutoplayRespectsAIDifficultyWithoutOpponentAutomation() async throws {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([1, 1])),
            localPlayer: .black,
            initialState: try autoplayDifficultyProbeState(),
            isOpponentAutoplayEnabled: false,
            aiDifficulty: .hard,
            raceAutoplayDelay: {}
        )

        #expect(viewModel.canStartLocalAutoplay)
        viewModel.startLocalAutoplay()

        let hitBlot = await waitUntil {
            viewModel.state.game.board.barCount(for: .white) == 1
        }

        #expect(hitBlot)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 22)!).owner == .black)
        #expect(viewModel.lastError == nil)
    }

    @Test("Easy AI local autoplay keeps deterministic random selection")
    @MainActor
    func easyAILocalAutoplayKeepsDeterministicRandomSelection() async throws {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([1, 1])),
            localPlayer: .black,
            initialState: try autoplayDifficultyProbeState(),
            aiDifficulty: .easy,
            opponentController: LocalAIOpponent(difficulty: .easy, randomIndex: { _ in 0 }),
            opponentDelay: {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            },
            raceAutoplayDelay: {}
        )

        #expect(viewModel.canStartLocalAutoplay)
        viewModel.startLocalAutoplay()

        let movedQuietly = await waitUntil {
            viewModel.state.game.board.point(PointID(rawValue: 6)!).owner == .black
        }

        #expect(movedQuietly)
        #expect(viewModel.state.game.board.barCount(for: .white) == 0)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 22)!).owner == .white)
        #expect(viewModel.lastError == nil)
    }

    @Test("Race autoplay advances both players in local AI matches")
    @MainActor
    func raceAutoplayAdvancesBothPlayersInLocalAIMatches() async throws {
        let initialPips = 90
        var board = Board.empty()
        try board.setPoint(PointID(rawValue: 6)!, owner: .white, count: 15)
        try board.setPoint(PointID(rawValue: 19)!, owner: .black, count: 15)

        let state = MatchState(
            config: MatchConfig(targetScore: 5, usesDoublingCube: false),
            game: GameState(board: board, phase: .awaitingRoll(.white))
        )
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([1, 1])),
            initialState: state,
            opponentController: LocalAIOpponent(randomIndex: { _ in 0 }),
            opponentDelay: {},
            raceAutoplayDelay: {}
        )

        let bothAdvanced = await waitUntil {
            viewModel.pipCount(for: .white) < initialPips
                && viewModel.pipCount(for: .black) < initialPips
        }

        #expect(bothAdvanced)
        #expect(viewModel.lastError == nil)
    }

    @Test("Race autoplay in Game Center style matches only advances the local turn")
    @MainActor
    func raceAutoplayOnlyAdvancesLocalTurnForGameCenterStyleMatches() async throws {
        var board = Board.empty()
        try board.setPoint(PointID(rawValue: 6)!, owner: .white, count: 15)
        try board.setPoint(PointID(rawValue: 19)!, owner: .black, count: 15)

        let state = MatchState(
            config: MatchConfig(targetScore: 5, usesDoublingCube: false),
            game: GameState(board: board, phase: .awaitingRoll(.white))
        )
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([1, 1])),
            initialState: state,
            isOpponentAutoplayEnabled: false,
            raceAutoplayController: LocalAIOpponent(randomIndex: { _ in 0 }),
            raceAutoplayDelay: {}
        )
        var stateChangeCount = 0
        viewModel.onStateChange = { _ in
            stateChangeCount += 1
        }

        let handedOff = await waitUntil {
            if case .awaitingRoll(.black) = viewModel.state.game.phase {
                return true
            }
            return false
        }

        #expect(handedOff)
        #expect(viewModel.pipCount(for: .white) < 90)
        #expect(viewModel.pipCount(for: .black) == 90)
        #expect(stateChangeCount == 1)
        #expect(!viewModel.isRaceAutoplayActive)
        #expect(viewModel.lastError == nil)
    }

    @Test("Race autoplay pauses before a local double offer")
    @MainActor
    func raceAutoplayPausesBeforeLocalDoubleOffer() async throws {
        var board = Board.empty()
        try board.setPoint(PointID(rawValue: 6)!, owner: .white, count: 15)
        try board.setPoint(PointID(rawValue: 19)!, owner: .black, count: 15)

        let state = MatchState(
            config: .tournament(targetScore: 7),
            game: GameState(board: board, phase: .awaitingRoll(.white))
        )
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([1, 1])),
            initialState: state,
            isOpponentAutoplayEnabled: false,
            raceAutoplayDelay: {}
        )

        for _ in 0..<5 {
            await Task.yield()
        }

        #expect(!viewModel.isRaceAutoplayActive)
        #expect(!viewModel.canStartRaceAutoplay)
        #expect(viewModel.containsAction(.offerDouble(.white)))
        guard case .awaitingRoll(.white) = viewModel.state.game.phase else {
            Issue.record("Expected autoplay to leave the local player at the roll.")
            return
        }
    }

    @Test("Stopping race autoplay cancels automatic restart for the current game")
    @MainActor
    func stoppingRaceAutoplayCancelsAutomaticRestart() async throws {
        var board = Board.empty()
        try board.setPoint(PointID(rawValue: 6)!, owner: .white, count: 15)
        try board.setPoint(PointID(rawValue: 19)!, owner: .black, count: 15)

        let state = MatchState(
            config: MatchConfig(targetScore: 5, usesDoublingCube: false),
            game: GameState(board: board, phase: .awaitingRoll(.white))
        )
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([1, 1])),
            initialState: state
        )

        #expect(viewModel.isRaceAutoplayActive)
        viewModel.stopRaceAutoplay()
        for _ in 0..<5 {
            await Task.yield()
        }

        #expect(viewModel.isRaceAutoplayUserStopped)
        #expect(!viewModel.isRaceAutoplayActive)
        #expect(viewModel.canStartRaceAutoplay)
        guard case .awaitingRoll(.white) = viewModel.state.game.phase else {
            Issue.record("Expected stopped autoplay to leave the original turn alone.")
            return
        }
    }

    @Test("Race autoplay completion callback fires once")
    @MainActor
    func raceAutoplayCompletionCallbackFiresOnce() async throws {
        var board = Board.empty()
        try board.setPoint(PointID(rawValue: 1)!, owner: .white, count: 1)
        try board.setPoint(PointID(rawValue: 24)!, owner: .black, count: 15)
        try board.setBorneOff(for: .white, count: 14)

        let roll = try DiceRoll(die1: 1, die2: 1)
        let state = MatchState(
            config: MatchConfig(targetScore: 1, usesDoublingCube: false),
            game: GameState(
                board: board,
                phase: .awaitingMove(TurnState(player: .white, roll: roll, remainingDice: [1]))
            )
        )
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([1, 1])),
            initialState: state,
            isOpponentAutoplayEnabled: false,
            raceAutoplayDelay: {}
        )
        var completionCount = 0
        viewModel.onCompletion = { _ in
            completionCount += 1
        }

        let completed = await waitUntil {
            viewModel.state.completion != nil
        }

        #expect(completed)
        #expect(completionCount == 1)
        #expect(viewModel.lastError == nil)
    }

    @Test("Local autoplay can play a turn before the race is no-contact")
    @MainActor
    func localAutoplayCanPlayContactTurn() async {
        let state = MatchState(
            config: MatchConfig(targetScore: 5, usesDoublingCube: false),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            initialState: state,
            isOpponentAutoplayEnabled: false,
            raceAutoplayController: LocalAIOpponent(randomIndex: { _ in 0 }),
            raceAutoplayDelay: {}
        )
        var stateChangeCount = 0
        viewModel.onStateChange = { _ in
            stateChangeCount += 1
        }

        #expect(!viewModel.state.game.board.isNoContactRace)
        #expect(viewModel.canStartLocalAutoplay)
        #expect(!viewModel.canStartRaceAutoplay)
        viewModel.startLocalAutoplay()

        let handedOff = await waitUntil {
            if case .awaitingRoll(.black) = viewModel.state.game.phase {
                return true
            }
            return false
        }

        #expect(handedOff)
        #expect(viewModel.pipCount(for: .white) < 167)
        #expect(viewModel.pipCount(for: .black) == 167)
        #expect(stateChangeCount == 1)
        #expect(!viewModel.isRaceAutoplayActive)
        #expect(viewModel.lastError == nil)
    }

    @Test("Local autoplay is unavailable before a local double offer")
    @MainActor
    func localAutoplayUnavailableBeforeLocalDoubleOffer() {
        let state = MatchState(
            config: .tournament(targetScore: 7),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            initialState: state,
            isOpponentAutoplayEnabled: false,
            raceAutoplayDelay: {}
        )

        #expect(viewModel.containsAction(.offerDouble(.white)))
        #expect(!viewModel.canStartLocalAutoplay)
    }

    @Test("Local AI quick match can complete from automated legal play")
    @MainActor
    func localAIQuickMatchCompletesFromLegalPlay() async {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: CyclingDiceRoller()),
            config: .tournament(targetScore: 1),
            opponentController: LocalAIOpponent(randomIndex: { _ in 0 }),
            opponentDelay: {},
            raceAutoplayDelay: {}
        )

        var actionCount = 0
        while viewModel.state.completion == nil, actionCount < 1_000 {
            actionCount += 1
            if viewModel.isRaceAutoplayActive {
                await Task.yield()
            } else if viewModel.isTurnDraftPending, viewModel.canSubmitTurn {
                viewModel.submitTurnIfAllowed()
            } else {
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
    _ = viewModel.submitTurnIfAllowed()
}

private func autoplayDifficultyProbeState() throws -> MatchState {
    var board = Board.empty()
    try board.setPoint(PointID(rawValue: 1)!, owner: .black, count: 1)
    try board.setPoint(PointID(rawValue: 17)!, owner: .black, count: 1)
    try board.setPoint(PointID(rawValue: 22)!, owner: .white, count: 1)

    let roll = try DiceRoll(die1: 5, die2: 2)
    return MatchState(
        config: MatchConfig(targetScore: 1, usesDoublingCube: false),
        game: GameState(
            board: board,
            phase: .awaitingMove(TurnState(player: .black, roll: roll, remainingDice: [5]))
        )
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
