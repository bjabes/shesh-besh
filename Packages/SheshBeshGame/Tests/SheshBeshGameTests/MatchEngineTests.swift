import SheshBeshGame
import Testing

@Suite("Match engine")
struct MatchEngineTests {
    @Test("Opening roll rerolls ties and starts the higher die")
    func openingRoll() throws {
        let engine = MatchEngine(diceRoller: ScriptedDiceRoller([3, 3, 6, 2]))
        var state = MatchEngine.newMatch(config: .tournament(targetScore: 5))

        state = try engine.apply(action: .rollOpeningDice, to: state)
        #expect(state.game.phase == .awaitingOpeningRoll)

        state = try engine.apply(action: .rollOpeningDice, to: state)
        guard case .awaitingMove(let turn) = state.game.phase else {
            Issue.record("Expected white to be awaiting checker movement")
            return
        }

        #expect(turn.player == .white)
        #expect(turn.roll.die1 == 6)
        #expect(turn.roll.die2 == 2)
        #expect(turn.remainingDice == [6, 2])
    }

    @Test("Applying a hit moves the blot to the bar")
    func hitMovesBlotToBar() throws {
        var board = Board.empty()
        try board.setPoint(point(8), owner: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setPoint(point(5), owner: .black, count: 1)
        try board.setBorneOff(for: .black, count: 14)

        let state = try makeMatch(board: board, player: .white, dice: [3])
        let move = Move(player: .white, source: .point(point(8)), destination: .point(point(5)), die: 3)
        let next = try MatchEngine().apply(action: .move(move), to: state)

        #expect(next.game.board.point(point(5)) == PointState(owner: .white, count: 1))
        #expect(next.game.board.barCount(for: .black) == 1)
        #expect(next.game.board.totalCheckers(for: .white) == 15)
        #expect(next.game.board.totalCheckers(for: .black) == 15)
    }

    @Test("A roll with no legal moves automatically passes the turn")
    func automaticPass() throws {
        var board = Board.empty()
        try board.setBar(for: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setPoint(point(24), owner: .black, count: 2)
        try board.setPoint(point(23), owner: .black, count: 2)
        try board.setBorneOff(for: .black, count: 11)

        let engine = MatchEngine(diceRoller: ScriptedDiceRoller([1, 2]))
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: board, phase: .awaitingRoll(.white))
        )
        let next = try engine.apply(action: .rollDice(.white), to: state)

        #expect(next.game.phase == .awaitingRoll(.black))
    }

    @Test("Double take assigns cube ownership to the taker")
    func doubleTake() throws {
        let engine = MatchEngine()
        var state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        state = try engine.apply(action: .offerDouble(.white), to: state)
        state = try engine.apply(action: .takeDouble(.black), to: state)

        #expect(state.game.cube == CubeState(value: 2, owner: .black))
        #expect(state.game.phase == .awaitingRoll(.white))
    }

    @Test("Dropping a double awards the previous cube value")
    func dropDoubleAwardsPreviousCubeValue() throws {
        let engine = MatchEngine()
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(
                board: .initial(),
                phase: .awaitingRoll(.white),
                cube: CubeState(value: 2, owner: .white)
            )
        )

        let offered = try engine.apply(action: .offerDouble(.white), to: state)
        let dropped = try engine.apply(action: .dropDouble(.black), to: offered)

        #expect(dropped.score.score(for: .white) == 2)
        guard case .gameOver(let result) = dropped.game.phase else {
            Issue.record("Expected game over after dropped double")
            return
        }
        #expect(result == GameResult(winner: .white, winKind: .single, cubeValue: 2))
    }

    @Test("Only the cube owner can redouble after a take")
    func onlyCubeOwnerCanRedouble() throws {
        let engine = MatchEngine()
        var state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        state = try engine.apply(action: .offerDouble(.white), to: state)
        state = try engine.apply(action: .takeDouble(.black), to: state)

        #expect(!MatchEngine.legalActions(in: state).contains(.offerDouble(.white)))

        state.game.phase = .awaitingRoll(.black)
        #expect(MatchEngine.legalActions(in: state).contains(.offerDouble(.black)))
    }

    @Test("Crawford game disables the cube and is marked completed after the game")
    func crawfordGame() throws {
        let engine = MatchEngine()
        let previousResult = GameResult(winner: .white, winKind: .single, cubeValue: 1)
        var state = MatchState(
            config: .tournament(targetScore: 3),
            score: MatchScore(white: 2, black: 0),
            game: GameState(board: .initial(), phase: .gameOver(previousResult)),
            crawfordState: .availableNextGame
        )

        state = try engine.apply(action: .startNextGame, to: state)
        #expect(state.game.isCrawford)

        state.game.phase = .awaitingRoll(.white)
        #expect(!MatchEngine.legalActions(in: state).contains(.offerDouble(.white)))

        state = try engine.apply(action: .offerResignation(.white, .single), to: state)
        state = try engine.apply(action: .acceptResignation(.black), to: state)

        #expect(state.crawfordState == .completed)

        state = try engine.apply(action: .startNextGame, to: state)
        state.game.phase = .awaitingRoll(.white)
        #expect(!state.game.isCrawford)
        #expect(MatchEngine.legalActions(in: state).contains(.offerDouble(.white)))
    }

    @Test("Accepted resignation scores the offered result")
    func resignationScoring() throws {
        let engine = MatchEngine()
        var state = MatchState(
            config: .tournament(targetScore: 7),
            game: GameState(
                board: .initial(),
                phase: .awaitingRoll(.white),
                cube: CubeState(value: 2, owner: .black)
            )
        )

        state = try engine.apply(action: .offerResignation(.white, .gammon), to: state)
        state = try engine.apply(action: .acceptResignation(.black), to: state)

        #expect(state.score.score(for: .black) == 4)
        guard case .gameOver(let result) = state.game.phase else {
            Issue.record("Expected game over after accepted resignation")
            return
        }
        #expect(result == GameResult(winner: .black, winKind: .gammon, cubeValue: 2))
    }

    @Test("Rejected resignation resumes the previous phase")
    func rejectedResignationResumesPlay() throws {
        let engine = MatchEngine()
        var state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        state = try engine.apply(action: .offerResignation(.white, .single), to: state)
        state = try engine.apply(action: .rejectResignation(.black), to: state)

        #expect(state.game.phase == .awaitingRoll(.white))
    }

    @Test("Bearing off the last checker classifies backgammon")
    func bearingOffLastCheckerEndsGame() throws {
        var board = Board.empty()
        try board.setPoint(point(1), owner: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setPoint(point(2), owner: .black, count: 1)
        try board.setPoint(point(19), owner: .black, count: 14)

        let state = try makeMatch(
            board: board,
            player: .white,
            dice: [1],
            config: .tournament(targetScore: 7)
        )
        let move = Move(player: .white, source: .point(point(1)), destination: .off, die: 1)
        let next = try MatchEngine().apply(action: .move(move), to: state)

        #expect(next.score.score(for: .white) == 3)
        guard case .gameOver(let result) = next.game.phase else {
            Issue.record("Expected game over after final checker bears off")
            return
        }
        #expect(result == GameResult(winner: .white, winKind: .backgammon, cubeValue: 1))
    }

    @Test("Bearing off the last checker classifies single and gammon wins")
    func finalCheckerClassifiesSingleAndGammon() throws {
        var singleBoard = Board.empty()
        try singleBoard.setPoint(point(1), owner: .white, count: 1)
        try singleBoard.setBorneOff(for: .white, count: 14)
        try singleBoard.setPoint(point(7), owner: .black, count: 14)
        try singleBoard.setBorneOff(for: .black, count: 1)

        var state = try makeMatch(board: singleBoard, player: .white, dice: [1])
        var next = try MatchEngine().apply(
            action: .move(Move(player: .white, source: .point(point(1)), destination: .off, die: 1)),
            to: state
        )

        guard case .gameOver(let singleResult) = next.game.phase else {
            Issue.record("Expected game over for single win")
            return
        }
        #expect(singleResult.winKind == .single)

        var gammonBoard = Board.empty()
        try gammonBoard.setPoint(point(1), owner: .white, count: 1)
        try gammonBoard.setBorneOff(for: .white, count: 14)
        try gammonBoard.setPoint(point(7), owner: .black, count: 15)

        state = try makeMatch(board: gammonBoard, player: .white, dice: [1])
        next = try MatchEngine().apply(
            action: .move(Move(player: .white, source: .point(point(1)), destination: .off, die: 1)),
            to: state
        )

        guard case .gameOver(let gammonResult) = next.game.phase else {
            Issue.record("Expected game over for gammon win")
            return
        }
        #expect(gammonResult.winKind == .gammon)
    }

    @Test("Match completion is recorded when the target score is reached")
    func matchCompletion() throws {
        let engine = MatchEngine()
        var state = MatchState(
            config: .tournament(targetScore: 3),
            game: GameState(
                board: .initial(),
                phase: .awaitingRoll(.white),
                cube: CubeState(value: 2, owner: .black)
            )
        )

        state = try engine.apply(action: .offerResignation(.white, .gammon), to: state)
        state = try engine.apply(action: .acceptResignation(.black), to: state)

        #expect(state.completion == MatchCompletion(winner: .black, finalScore: state.score))
        #expect(MatchEngine.legalActions(in: state).isEmpty)
    }

    @Test("A player who is one point away triggers Crawford for the next game")
    func crawfordIsQueuedAtOneAway() throws {
        let engine = MatchEngine()
        var state = MatchState(
            config: .tournament(targetScore: 2),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        state = try engine.apply(action: .offerResignation(.white, .single), to: state)
        state = try engine.apply(action: .acceptResignation(.black), to: state)

        #expect(state.score.score(for: .black) == 1)
        #expect(state.crawfordState == .availableNextGame)
    }
}
