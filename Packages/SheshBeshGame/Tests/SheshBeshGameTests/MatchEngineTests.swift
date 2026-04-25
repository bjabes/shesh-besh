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
        try board.setPoint(point(8), owner: .white, count: 2)
        try board.setBorneOff(for: .white, count: 13)
        try board.setPoint(point(5), owner: .black, count: 1)
        try board.setBorneOff(for: .black, count: 14)

        let state = try makeMatch(board: board, player: .white, dice: [3])
        let move = Move(player: .white, source: .point(point(8)), destination: .point(point(5)), die: 3)
        let next = try MatchEngine().apply(action: .move(move), to: state)

        #expect(next.game.board.point(point(8)) == PointState(owner: .white, count: 1))
        #expect(next.game.board.point(point(5)) == PointState(owner: .white, count: 1))
        #expect(next.game.board.barCount(for: .black) == 1)
        #expect(next.game.board.totalCheckers(for: .white) == 15)
        #expect(next.game.board.totalCheckers(for: .black) == 15)
    }

    @Test("A checker can hit in the home board and continue with the second die")
    func hitAndRunInHomeBoard() throws {
        let engine = MatchEngine()
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setPoint(point(4), owner: .black, count: 1)
        try board.setBorneOff(for: .black, count: 14)

        var state = try makeMatch(board: board, player: .white, dice: [2, 3])
        let hit = Move(player: .white, source: .point(point(6)), destination: .point(point(4)), die: 2)
        let run = Move(player: .white, source: .point(point(4)), destination: .point(point(1)), die: 3)

        #expect(MatchEngine.legalActions(in: state).contains(.move(hit)))
        state = try engine.apply(action: .move(hit), to: state)

        #expect(state.game.board.barCount(for: .black) == 1)
        #expect(MatchEngine.legalActions(in: state).contains(.move(run)))
        state = try engine.apply(action: .move(run), to: state)

        #expect(state.game.board.point(point(1)) == PointState(owner: .white, count: 1))
        #expect(state.game.board.point(point(4)) == .empty)
        #expect(state.game.board.barCount(for: .white) == 0)
        #expect(state.game.board.barCount(for: .black) == 1)
        #expect(state.game.phase == .awaitingRoll(.black))
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

        #expect(next.game.board == board)
        #expect(next.game.phase == .awaitingRoll(.black))
    }

    @Test("Legal actions at roll time are exactly roll, double, and resignations")
    func legalActionsAtRollTimeArePinned() {
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        #expect(MatchEngine.legalActions(in: state) == [
            .offerDouble(.white),
            .rollDice(.white),
            .offerResignation(.white, .single),
            .offerResignation(.white, .gammon),
            .offerResignation(.white, .backgammon),
        ])
    }

    @Test("Legal actions at move time are exactly legal first moves and resignations")
    func legalActionsAtMoveTimeArePinned() throws {
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setPoint(point(19), owner: .black, count: 15)

        let state = try makeMatch(board: board, player: .white, dice: [1])
        let checkerMove = Move(player: .white, source: .point(point(6)), destination: .point(point(5)), die: 1)

        #expect(MatchEngine.legalActions(in: state) == [
            .move(checkerMove),
            .offerResignation(.white, .single),
            .offerResignation(.white, .gammon),
            .offerResignation(.white, .backgammon),
        ])
    }

    @Test("Disabling the doubling cube removes double offers")
    func disablingDoublingCubeRemovesDoubleOffers() {
        let state = MatchState(
            config: MatchConfig(targetScore: 5, usesDoublingCube: false),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        #expect(MatchEngine.legalActions(in: state) == [
            .rollDice(.white),
            .offerResignation(.white, .single),
            .offerResignation(.white, .gammon),
            .offerResignation(.white, .backgammon),
        ])
        expectInvalidAction {
            _ = try MatchEngine().apply(action: .offerDouble(.white), to: state)
        }
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
        let engine = MatchEngine(diceRoller: ScriptedDiceRoller([6, 1]))
        var state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        state = try engine.apply(action: .offerDouble(.white), to: state)
        state = try engine.apply(action: .takeDouble(.black), to: state)

        #expect(!MatchEngine.legalActions(in: state).contains(.offerDouble(.white)))

        state = try engine.apply(action: .rollDice(.white), to: state)
        state = try playFirstLegalMovesUntilRoll(from: state, using: engine)

        #expect(state.game.phase == .awaitingRoll(.black))
        #expect(MatchEngine.legalActions(in: state).contains(.offerDouble(.black)))
    }

    @Test("Doubling is unavailable once the cube reaches the configured maximum")
    func maximumCubeValueStopsFurtherDoubles() throws {
        let engine = MatchEngine()
        let state = MatchState(
            config: MatchConfig(targetScore: 7, maximumCubeValue: 4),
            game: GameState(
                board: .initial(),
                phase: .awaitingRoll(.white),
                cube: CubeState(value: 4, owner: .white)
            )
        )

        #expect(!MatchEngine.legalActions(in: state).contains(.offerDouble(.white)))
        expectInvalidAction {
            _ = try engine.apply(action: .offerDouble(.white), to: state)
        }
    }

    @Test("The taker cannot immediately redouble before their turn")
    func takerCannotImmediatelyRedouble() throws {
        let engine = MatchEngine()
        var state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        state = try engine.apply(action: .offerDouble(.white), to: state)
        state = try engine.apply(action: .takeDouble(.black), to: state)

        #expect(state.game.phase == .awaitingRoll(.white))
        #expect(state.game.cube == CubeState(value: 2, owner: .black))
        #expect(!MatchEngine.legalActions(in: state).contains(.offerDouble(.black)))
        expectInvalidAction {
            _ = try engine.apply(action: .offerDouble(.black), to: state)
        }
    }

    @Test("Crawford game disables the cube and is marked completed after the game")
    func crawfordGame() throws {
        let engine = MatchEngine(diceRoller: ScriptedDiceRoller([6, 1, 6, 1]))
        let previousResult = GameResult(winner: .black, winKind: .single, cubeValue: 1)
        var state = MatchState(
            config: .tournament(targetScore: 3),
            score: MatchScore(white: 0, black: 2),
            game: GameState(board: .initial(), phase: .gameOver(previousResult)),
            crawfordState: .availableNextGame
        )

        state = try engine.apply(action: .startNextGame, to: state)
        #expect(state.game.isCrawford)

        state = try engine.apply(action: .rollOpeningDice, to: state)
        state = try playFirstLegalMovesUntilRoll(from: state, using: engine)
        #expect(!MatchEngine.legalActions(in: state).contains(.offerDouble(.black)))

        state = try engine.apply(action: .offerResignation(.black, .single), to: state)
        state = try engine.apply(action: .acceptResignation(.white), to: state)

        #expect(state.crawfordState == .completed)

        state = try engine.apply(action: .startNextGame, to: state)
        state = try engine.apply(action: .rollOpeningDice, to: state)
        state = try playFirstLegalMovesUntilRoll(from: state, using: engine)
        #expect(!state.game.isCrawford)
        #expect(MatchEngine.legalActions(in: state).contains(.offerDouble(.black)))
    }

    @Test("The doubling cube is available again after the Crawford game")
    func cubeAvailableAfterCrawfordGameCompletes() throws {
        let engine = MatchEngine(diceRoller: ScriptedDiceRoller([6, 1, 6, 1]))
        let previousResult = GameResult(winner: .black, winKind: .single, cubeValue: 1)
        var state = MatchState(
            config: .tournament(targetScore: 4),
            score: MatchScore(white: 0, black: 3),
            game: GameState(board: .initial(), phase: .gameOver(previousResult)),
            crawfordState: .availableNextGame
        )

        state = try engine.apply(action: .startNextGame, to: state)
        #expect(state.game.isCrawford)

        state = try engine.apply(action: .rollOpeningDice, to: state)
        state = try playFirstLegalMovesUntilRoll(from: state, using: engine)
        #expect(!MatchEngine.legalActions(in: state).contains(.offerDouble(.black)))

        state = try engine.apply(action: .offerResignation(.black, .single), to: state)
        state = try engine.apply(action: .acceptResignation(.white), to: state)
        #expect(state.crawfordState == .completed)

        state = try engine.apply(action: .startNextGame, to: state)
        state = try engine.apply(action: .rollOpeningDice, to: state)
        state = try playFirstLegalMovesUntilRoll(from: state, using: engine)

        #expect(!state.game.isCrawford)
        #expect(MatchEngine.legalActions(in: state).contains(.offerDouble(.black)))
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

    @Test("Scoring matrix matches win kind multipliers across cube values")
    func scoringMatrixMatchesWinKindAndCubeValue() throws {
        let cubeValues = [1, 2, 4, 8, 16, 32, 64]
        let startingScore = MatchScore(white: 7, black: 13)

        for winner in Player.allCases {
            let loser = winner.opponent
            for winKind in WinKind.allCases {
                for cubeValue in cubeValues {
                    let expectedPoints = cubeValue * winKind.multiplier
                    let result = GameResult(winner: winner, winKind: winKind, cubeValue: cubeValue)
                    #expect(result.points == expectedPoints)

                    var state = MatchState(
                        config: .tournament(targetScore: 500),
                        score: startingScore,
                        game: GameState(
                            board: .initial(),
                            phase: .awaitingRoll(loser),
                            cube: CubeState(value: cubeValue, owner: winner)
                        )
                    )

                    state = try MatchEngine().apply(action: .offerResignation(loser, winKind), to: state)
                    state = try MatchEngine().apply(action: .acceptResignation(winner), to: state)

                    #expect(state.score.score(for: winner) == startingScore.score(for: winner) + expectedPoints)
                    #expect(state.score.score(for: loser) == startingScore.score(for: loser))
                    #expect(state.completion == nil)

                    guard case .gameOver(let scoredResult) = state.game.phase else {
                        Issue.record("Expected game over after accepted resignation")
                        continue
                    }
                    #expect(scoredResult == result)
                }
            }
        }
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

    @Test("Rejected resignation restores awaitingMove turns")
    func rejectedResignationResumesAwaitingMove() throws {
        let engine = MatchEngine()
        let board = Board.initial()
        var state = try makeMatch(board: board, player: .white, dice: [4, 1])

        state = try engine.apply(action: .offerResignation(.white, .single), to: state)
        state = try engine.apply(action: .rejectResignation(.black), to: state)

        guard case .awaitingMove(let turn) = state.game.phase else {
            Issue.record("Expected awaitingMove after resignation rejection")
            return
        }
        #expect(turn.player == .white)
        #expect(turn.remainingDice == [4, 1])
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
        #expect(next.game.board.borneOffCount(for: .white) == 15)
        guard case .gameOver(let result) = next.game.phase else {
            Issue.record("Expected game over after final checker bears off")
            return
        }
        #expect(result == GameResult(winner: .white, winKind: .backgammon, cubeValue: 1))
    }

    @Test("Bearing off the last checker classifies backgammon when the loser is on the bar")
    func finalCheckerClassifiesBackgammonFromBar() throws {
        var board = Board.empty()
        try board.setPoint(point(1), owner: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setBar(for: .black, count: 1)
        try board.setPoint(point(19), owner: .black, count: 14)

        let state = try makeMatch(board: board, player: .white, dice: [1])
        let move = Move(player: .white, source: .point(point(1)), destination: .off, die: 1)
        let next = try MatchEngine().apply(action: .move(move), to: state)

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

    @Test("Match completion is recorded when points exceed targetScore")
    func matchCompletionWhenScoreExceedsTarget() throws {
        let engine = MatchEngine()
        var state = MatchState(
            config: .tournament(targetScore: 3),
            score: MatchScore(white: 0, black: 2),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        state = try engine.apply(action: .offerResignation(.white, .gammon), to: state)
        state = try engine.apply(action: .acceptResignation(.black), to: state)

        #expect(state.score.score(for: .black) == 4)
        #expect(state.completion == MatchCompletion(winner: .black, finalScore: state.score))
    }

    @Test("A high cube backgammon completes the match when it overshoots the target")
    func highCubeBackgammonCanCompleteMatchBeyondTarget() throws {
        var board = Board.empty()
        try board.setPoint(point(1), owner: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setBar(for: .black, count: 1)
        try board.setPoint(point(19), owner: .black, count: 14)

        let state = try makeMatch(
            board: board,
            player: .white,
            dice: [1],
            config: .tournament(targetScore: 5),
            cube: CubeState(value: 4, owner: .black)
        )
        let move = Move(player: .white, source: .point(point(1)), destination: .off, die: 1)
        let next = try MatchEngine().apply(action: .move(move), to: state)

        #expect(next.score.score(for: .white) == 12)
        #expect(next.completion == MatchCompletion(winner: .white, finalScore: next.score))
        guard case .gameOver(let result) = next.game.phase else {
            Issue.record("Expected game over after final checker bears off")
            return
        }
        #expect(result == GameResult(winner: .white, winKind: .backgammon, cubeValue: 4))
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

    @Test("Crawford stays unavailable when the rule is disabled")
    func crawfordRuleDisabledKeepsStateNotReached() throws {
        let engine = MatchEngine()
        var state = MatchState(
            config: MatchConfig(targetScore: 3, usesCrawfordRule: false),
            score: MatchScore(white: 0, black: 1),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        state = try engine.apply(action: .offerResignation(.white, .single), to: state)
        state = try engine.apply(action: .acceptResignation(.black), to: state)

        #expect(state.score.score(for: .black) == 2)
        #expect(state.crawfordState == .notReached)
        #expect(state.completion == nil)
    }

    @Test("Crawford is queued when either player reaches one away")
    func crawfordIsQueuedWhenEitherPlayerReachesOneAway() throws {
        let engine = MatchEngine()
        var state = MatchState(
            config: .tournament(targetScore: 3),
            score: MatchScore(white: 2, black: 1),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )

        state = try engine.apply(action: .offerResignation(.white, .single), to: state)
        state = try engine.apply(action: .acceptResignation(.black), to: state)

        #expect(state.score.score(for: .white) == 2)
        #expect(state.score.score(for: .black) == 2)
        #expect(state.crawfordState == .availableNextGame)
    }

    @Test("Starting the next game increments gameNumber")
    func startNextGameIncrementsGameNumber() throws {
        let engine = MatchEngine()
        let state = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(
                board: .initial(),
                phase: .gameOver(GameResult(winner: .white, winKind: .single, cubeValue: 1))
            ),
            gameNumber: 3
        )

        let next = try engine.apply(action: .startNextGame, to: state)

        #expect(next.gameNumber == 4)
        #expect(next.game.phase == .awaitingOpeningRoll)
    }

    @Test("Bear-off can queue Crawford and continue to the post-Crawford game")
    func bearOffQueuesCrawfordThenMatchContinuesAfterCrawford() throws {
        let engine = MatchEngine(diceRoller: ScriptedDiceRoller([6, 1, 6, 1]))
        var board = Board.empty()
        try board.setPoint(point(1), owner: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setPoint(point(7), owner: .black, count: 14)
        try board.setBorneOff(for: .black, count: 1)

        var state = try makeMatch(
            board: board,
            player: .white,
            dice: [1],
            config: .tournament(targetScore: 4),
            score: MatchScore(white: 2, black: 0)
        )

        state = try engine.apply(
            action: .move(Move(player: .white, source: .point(point(1)), destination: .off, die: 1)),
            to: state
        )

        #expect(state.score.score(for: .white) == 3)
        #expect(state.crawfordState == .availableNextGame)

        state = try engine.apply(action: .startNextGame, to: state)
        #expect(state.gameNumber == 2)
        #expect(state.game.phase == .awaitingOpeningRoll)
        #expect(state.game.isCrawford)

        state = try engine.apply(action: .rollOpeningDice, to: state)
        state = try engine.apply(action: .offerResignation(.white, .single), to: state)
        state = try engine.apply(action: .acceptResignation(.black), to: state)

        #expect(state.score.score(for: .black) == 1)
        #expect(state.crawfordState == .completed)
        #expect(state.completion == nil)

        state = try engine.apply(action: .startNextGame, to: state)
        #expect(state.gameNumber == 3)
        #expect(!state.game.isCrawford)
        #expect(state.game.phase == .awaitingOpeningRoll)
    }
}
