import SheshBeshGame
import Testing

@Suite("Move validation")
struct MoveValidatorTests {
    @Test("Initial board exposes normal checker moves")
    func initialBoardNormalMoves() {
        let firstMoves = MoveValidator.legalFirstMoves(for: .white, board: .initial(), dice: [3, 1])

        #expect(firstMoves.contains(Move(player: .white, source: .point(point(24)), destination: .point(point(21)), die: 3)))
        #expect(firstMoves.contains(Move(player: .white, source: .point(point(24)), destination: .point(point(23)), die: 1)))
    }

    @Test("Blocked points cannot be used as destinations")
    func blockedDestination() throws {
        var board = Board.empty()
        try board.setPoint(point(8), owner: .white, count: 1)
        try board.setPoint(point(5), owner: .black, count: 2)

        let firstMoves = MoveValidator.legalFirstMoves(for: .white, board: board, dice: [3])

        #expect(!firstMoves.contains(Move(player: .white, source: .point(point(8)), destination: .point(point(5)), die: 3)))
        #expect(firstMoves.isEmpty)
    }

    @Test("Bar checkers must enter before other checkers move")
    func barPriority() throws {
        var board = Board.empty()
        try board.setBar(for: .white, count: 1)
        try board.setPoint(point(8), owner: .white, count: 1)

        let firstMoves = MoveValidator.legalFirstMoves(for: .white, board: board, dice: [3])

        #expect(firstMoves == [
            Move(player: .white, source: .bar, destination: .point(point(22)), die: 3),
        ])
    }

    @Test("Move generation prefers using more dice over a larger immediate die")
    func maximumDiceUseBeatsImmediateHighDie() throws {
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 1)

        let sequences = MoveValidator.legalMoves(for: .white, board: board, dice: [1, 6])

        #expect(sequences.contains(MoveSequence(moves: [
            Move(player: .white, source: .point(point(6)), destination: .point(point(5)), die: 1),
            Move(player: .white, source: .point(point(5)), destination: .off, die: 6),
        ])))
        #expect(sequences.allSatisfy { $0.moves.count == 2 })
    }

    @Test("When only one die can be played, the higher die is forced")
    func higherDieRule() throws {
        var board = Board.empty()
        try board.setPoint(point(1), owner: .white, count: 1)

        let firstMoves = MoveValidator.legalFirstMoves(for: .white, board: board, dice: [1, 2])

        #expect(firstMoves == [
            Move(player: .white, source: .point(point(1)), destination: .off, die: 2),
        ])
    }

    @Test("Oversize bear-off requires no checker farther from home")
    func oversizeBearOff() throws {
        var blocked = Board.empty()
        try blocked.setPoint(point(6), owner: .white, count: 1)
        try blocked.setPoint(point(5), owner: .white, count: 1)

        let blockedMoves = MoveValidator.legalFirstMoves(for: .white, board: blocked, dice: [6])
        #expect(blockedMoves == [
            Move(player: .white, source: .point(point(6)), destination: .off, die: 6),
        ])

        var allowed = Board.empty()
        try allowed.setPoint(point(5), owner: .white, count: 1)

        let allowedMoves = MoveValidator.legalFirstMoves(for: .white, board: allowed, dice: [6])
        #expect(allowedMoves == [
            Move(player: .white, source: .point(point(5)), destination: .off, die: 6),
        ])
    }

    @Test("Bearing off is illegal while a checker remains outside the home board")
    func cannotBearOffWithCheckerOutsideHome() throws {
        var board = Board.empty()
        try board.setPoint(point(7), owner: .white, count: 1)
        try board.setPoint(point(5), owner: .white, count: 1)

        let firstMoves = MoveValidator.legalFirstMoves(for: .white, board: board, dice: [5])

        #expect(!firstMoves.contains(Move(player: .white, source: .point(point(5)), destination: .off, die: 5)))
        #expect(firstMoves.contains(Move(player: .white, source: .point(point(7)), destination: .point(point(2)), die: 5)))
    }

    @Test("Doubles can be played up to four times")
    func doublesUseFourMoves() throws {
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 4)

        let sequences = MoveValidator.legalMoves(for: .white, board: board, dice: [1, 1, 1, 1])

        #expect(!sequences.isEmpty)
        #expect(sequences.allSatisfy { $0.moves.count == 4 })
    }

    @Test("Black moves upward and bears off from the high board")
    func blackMovementAndBearOff() throws {
        var board = Board.empty()
        try board.setPoint(point(19), owner: .black, count: 1)
        try board.setPoint(point(20), owner: .black, count: 1)

        let blockedOversize = MoveValidator.legalFirstMoves(for: .black, board: board, dice: [6])
        #expect(blockedOversize == [
            Move(player: .black, source: .point(point(19)), destination: .off, die: 6),
        ])

        try board.setPoint(point(19), owner: nil, count: 0)
        let allowedOversize = MoveValidator.legalFirstMoves(for: .black, board: board, dice: [6])
        #expect(allowedOversize == [
            Move(player: .black, source: .point(point(20)), destination: .off, die: 6),
        ])
    }

    @Test("Black enters from the bar using the rolled die")
    func blackBarEntry() throws {
        var board = Board.empty()
        try board.setBar(for: .black, count: 1)

        let firstMoves = MoveValidator.legalFirstMoves(for: .black, board: board, dice: [4])

        #expect(firstMoves == [
            Move(player: .black, source: .bar, destination: .point(point(4)), die: 4),
        ])
    }
}
