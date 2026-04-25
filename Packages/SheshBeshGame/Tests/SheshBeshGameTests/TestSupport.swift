import SheshBeshGame
import Testing

final class ScriptedDiceRoller: DiceRolling, @unchecked Sendable {
    private let values: [Int]
    private var index = 0

    init(_ values: [Int]) {
        self.values = values
    }

    func rollDie() -> Int {
        guard !values.isEmpty else { return 1 }
        let value = values[index % values.count]
        index += 1
        return value
    }
}

func point(_ rawValue: Int) -> PointID {
    PointID(rawValue: rawValue)!
}

func makeGame(
    board: Board,
    player: Player,
    dice: [Int],
    cube: CubeState = CubeState(),
    isCrawford: Bool = false
) throws -> GameState {
    let roll = try DiceRoll(die1: dice[0], die2: dice.count > 1 ? dice[1] : dice[0])
    return GameState(
        board: board,
        phase: .awaitingMove(TurnState(player: player, roll: roll, remainingDice: dice)),
        cube: cube,
        isCrawford: isCrawford
    )
}

func makeMatch(
    board: Board,
    player: Player,
    dice: [Int],
    config: MatchConfig = .tournament(targetScore: 5),
    score: MatchScore = MatchScore(),
    cube: CubeState = CubeState()
) throws -> MatchState {
    MatchState(
        config: config,
        score: score,
        game: try makeGame(board: board, player: player, dice: dice, cube: cube)
    )
}

func expectNoMixedPoints(_ board: Board) {
    for state in board.points {
        #expect((state.owner == nil) == (state.count == 0))
    }
}

func playFirstLegalMovesUntilRoll(
    from state: MatchState,
    using engine: MatchEngine,
    limit: Int = 4
) throws -> MatchState {
    var next = state
    for _ in 0..<limit {
        guard case .awaitingMove(let turn) = next.game.phase else { return next }
        let move = try #require(MoveValidator.legalFirstMoves(for: turn.player, in: next.game).first)
        next = try engine.apply(action: .move(move), to: next)
    }
    return next
}

func expectInvalidAction(_ body: () throws -> Void) {
    do {
        try body()
        Issue.record("Expected MatchEngineError.invalidAction")
    } catch let error as MatchEngineError {
        guard case .invalidAction(let message) = error else {
            Issue.record("Expected MatchEngineError.invalidAction, got \(error)")
            return
        }
        #expect(!message.isEmpty)
    } catch {
        Issue.record("Expected MatchEngineError.invalidAction, got \(error)")
    }
}

func expectMatchEngineError(_ expected: MatchEngineError, _ body: () throws -> Void) {
    do {
        try body()
        Issue.record("Expected \(expected)")
    } catch let error as MatchEngineError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected \(expected), got \(error)")
    }
}

func expectBoardError(_ expected: BoardError, _ body: () throws -> Void) {
    do {
        try body()
        Issue.record("Expected \(expected)")
    } catch let error as BoardError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected \(expected), got \(error)")
    }
}
