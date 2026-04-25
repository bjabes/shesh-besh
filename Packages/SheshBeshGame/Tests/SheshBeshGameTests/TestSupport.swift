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
