import SheshBeshGame
import Testing

@Suite("Match engine errors")
struct MatchEngineErrorTests {
    @Test("Dice roll initializer rejects invalid dice values")
    func diceRollInitializerRejectsInvalidValues() {
        expectMatchEngineError(.invalidDiceValue) {
            _ = try DiceRoll(die1: 0, die2: 4)
        }
        expectMatchEngineError(.invalidDiceValue) {
            _ = try DiceRoll(die1: 3, die2: 7)
        }
    }

    @Test("Opening roll rejects invalid dice values")
    func openingRollRejectsInvalidDiceValues() {
        let engine = MatchEngine(diceRoller: ScriptedDiceRoller([0, 4]))
        let state = MatchEngine.newMatch(config: .tournament(targetScore: 5))

        expectMatchEngineError(.invalidDiceValue) {
            _ = try engine.apply(action: .rollOpeningDice, to: state)
        }
    }

    @Test("Rolling dice rejects invalid dice values")
    func turnRollRejectsInvalidDiceValues() {
        let engine = MatchEngine(diceRoller: ScriptedDiceRoller([3, 7]))
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        expectMatchEngineError(.invalidDiceValue) {
            _ = try engine.apply(action: .rollDice(.white), to: state)
        }
    }

    @Test("Opening roll is rejected outside the opening phase")
    func openingRollOutsideOpeningPhaseThrowsInvalidAction() {
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        expectInvalidAction {
            _ = try MatchEngine().apply(action: .rollOpeningDice, to: state)
        }
    }

    @Test("Rolling is rejected for the wrong player")
    func wrongPlayerRollThrowsInvalidAction() {
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        expectInvalidAction {
            _ = try MatchEngine().apply(action: .rollDice(.black), to: state)
        }
    }

    @Test("Rolling is rejected during checker movement")
    func rollDuringMovePhaseThrowsInvalidAction() throws {
        let state = try makeMatch(board: .initial(), player: .white, dice: [4, 1])

        expectInvalidAction {
            _ = try MatchEngine().apply(action: .rollDice(.white), to: state)
        }
    }

    @Test("Moves are rejected outside checker movement")
    func moveOutsideMovePhaseThrowsInvalidAction() {
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )
        let move = Move(player: .white, source: .point(point(24)), destination: .point(point(21)), die: 3)

        expectInvalidAction {
            _ = try MatchEngine().apply(action: .move(move), to: state)
        }
    }

    @Test("Illegal moves report the rejected move")
    func illegalMoveReportsRejectedMove() throws {
        let state = try makeMatch(board: .initial(), player: .white, dice: [3, 1])
        let move = Move(player: .white, source: .point(point(24)), destination: .point(point(20)), die: 4)

        expectMatchEngineError(.illegalMove(move)) {
            _ = try MatchEngine().apply(action: .move(move), to: state)
        }
    }

    @Test("Opponent moves during a turn report the rejected move")
    func opponentMoveReportsRejectedMove() throws {
        let state = try makeMatch(board: .initial(), player: .white, dice: [3, 1])
        let move = Move(player: .black, source: .point(point(1)), destination: .point(point(4)), die: 3)

        expectMatchEngineError(.illegalMove(move)) {
            _ = try MatchEngine().apply(action: .move(move), to: state)
        }
    }

    @Test("Cube responses are rejected when no cube offer is pending")
    func cubeResponsesWithoutOfferThrowInvalidAction() {
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        expectInvalidAction {
            _ = try MatchEngine().apply(action: .takeDouble(.black), to: state)
        }
        expectInvalidAction {
            _ = try MatchEngine().apply(action: .dropDouble(.black), to: state)
        }
    }

    @Test("Cube responses are rejected for the offering player")
    func cubeResponsesFromOffererThrowInvalidAction() throws {
        let engine = MatchEngine()
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )
        let offered = try engine.apply(action: .offerDouble(.white), to: state)

        expectInvalidAction {
            _ = try engine.apply(action: .takeDouble(.white), to: offered)
        }
        expectInvalidAction {
            _ = try engine.apply(action: .dropDouble(.white), to: offered)
        }
    }

    @Test("Double offers are rejected when the player cannot offer")
    func unavailableDoubleOfferThrowsInvalidAction() {
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(
                board: .initial(),
                phase: .awaitingRoll(.white),
                cube: CubeState(value: 2, owner: .black)
            )
        )

        expectInvalidAction {
            _ = try MatchEngine().apply(action: .offerDouble(.white), to: state)
        }
    }

    @Test("Double offers are rejected during checker movement")
    func doubleOfferDuringMovePhaseThrowsInvalidAction() throws {
        let state = try makeMatch(board: .initial(), player: .white, dice: [4, 1])

        expectInvalidAction {
            _ = try MatchEngine().apply(action: .offerDouble(.white), to: state)
        }
    }

    @Test("Resignation offers are rejected outside roll and move phases")
    func resignationOfferOutsidePlayablePhaseThrowsInvalidAction() {
        let state = MatchEngine.newMatch(config: .tournament(targetScore: 5))

        expectInvalidAction {
            _ = try MatchEngine().apply(action: .offerResignation(.white, .single), to: state)
        }
    }

    @Test("Resignation responses are rejected when no resignation is pending")
    func resignationResponsesWithoutOfferThrowInvalidAction() {
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        expectInvalidAction {
            _ = try MatchEngine().apply(action: .acceptResignation(.black), to: state)
        }
        expectInvalidAction {
            _ = try MatchEngine().apply(action: .rejectResignation(.black), to: state)
        }
    }

    @Test("Resignation responses are rejected for the offering player")
    func resignationResponsesFromOffererThrowInvalidAction() throws {
        let engine = MatchEngine()
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )
        let offered = try engine.apply(action: .offerResignation(.white, .single), to: state)

        expectInvalidAction {
            _ = try engine.apply(action: .acceptResignation(.white), to: offered)
        }
        expectInvalidAction {
            _ = try engine.apply(action: .rejectResignation(.white), to: offered)
        }
    }

    @Test("Starting the next game is rejected before game over")
    func startNextGameBeforeGameOverThrowsInvalidAction() {
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        expectInvalidAction {
            _ = try MatchEngine().apply(action: .startNextGame, to: state)
        }
    }

    @Test("Actions after match completion throw matchAlreadyCompleted")
    func actionsAfterMatchCompletionThrowMatchAlreadyCompleted() {
        let state = MatchState(
            config: .tournament(targetScore: 1),
            score: MatchScore(white: 1, black: 0),
            game: GameState(
                board: .initial(),
                phase: .gameOver(GameResult(winner: .white, winKind: .single, cubeValue: 1))
            ),
            completion: MatchCompletion(winner: .white, finalScore: MatchScore(white: 1, black: 0))
        )

        expectMatchEngineError(.matchAlreadyCompleted) {
            _ = try MatchEngine().apply(action: .rollOpeningDice, to: state)
        }
        expectMatchEngineError(.matchAlreadyCompleted) {
            _ = try MatchEngine().apply(action: .startNextGame, to: state)
        }
    }
}
