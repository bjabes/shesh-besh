@testable import SheshBeshGame
import Testing

@Suite("Board internal mutations")
struct BoardInternalTests {
    @Test("Applying a move rejects missing source checkers")
    func applyRejectsNoCheckerAtSource() {
        var board = Board.empty()
        let move = Move(player: .white, source: .point(point(6)), destination: .point(point(5)), die: 1)

        expectBoardError(.noCheckerAtSource) {
            try board.apply(move)
        }
    }

    @Test("Applying a move rejects blocked destinations")
    func applyRejectsBlockedDestination() throws {
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 1)
        try board.setPoint(point(5), owner: .black, count: 2)
        let move = Move(player: .white, source: .point(point(6)), destination: .point(point(5)), die: 1)

        expectBoardError(.blockedDestination) {
            try board.apply(move)
        }
    }
}
