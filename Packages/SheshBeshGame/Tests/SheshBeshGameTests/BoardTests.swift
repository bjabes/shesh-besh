import SheshBeshGame
import Testing

@Suite("Board")
struct BoardTests {
    @Test("Initial board has standard checker placement")
    func initialBoardPlacement() {
        let board = Board.initial()

        #expect(board.point(point(24)) == PointState(owner: .white, count: 2))
        #expect(board.point(point(13)) == PointState(owner: .white, count: 5))
        #expect(board.point(point(8)) == PointState(owner: .white, count: 3))
        #expect(board.point(point(6)) == PointState(owner: .white, count: 5))

        #expect(board.point(point(1)) == PointState(owner: .black, count: 2))
        #expect(board.point(point(12)) == PointState(owner: .black, count: 5))
        #expect(board.point(point(17)) == PointState(owner: .black, count: 3))
        #expect(board.point(point(19)) == PointState(owner: .black, count: 5))

        #expect(board.totalCheckers(for: .white) == 15)
        #expect(board.totalCheckers(for: .black) == 15)
        #expect(board.isValidForGame())
    }

    @Test("Board tracks bar, borne off, and home-board status")
    func barBorneOffAndHomeStatus() throws {
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 5)
        try board.setPoint(point(3), owner: .white, count: 2)
        try board.setBorneOff(for: .white, count: 8)

        #expect(board.allCheckersAreHome(for: .white))
        #expect(board.totalCheckers(for: .white) == 15)

        try board.setBar(for: .white, count: 1)
        try board.setBorneOff(for: .white, count: 7)

        #expect(!board.allCheckersAreHome(for: .white))
        #expect(board.barCount(for: .white) == 1)
        #expect(board.totalCheckers(for: .white) == 15)
    }

    @Test("Hitting from the bar preserves both players' total checker counts")
    func totalsRemainFifteenAfterBarHit() throws {
        var board = Board.empty()
        try board.setBar(for: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setPoint(point(22), owner: .black, count: 1)
        try board.setBorneOff(for: .black, count: 14)

        try board.apply(Move(player: .white, source: .bar, destination: .point(point(22)), die: 3))

        #expect(board.point(point(22)) == PointState(owner: .white, count: 1))
        #expect(board.barCount(for: .white) == 0)
        #expect(board.barCount(for: .black) == 1)
        #expect(board.totalCheckers(for: .white) == 15)
        #expect(board.totalCheckers(for: .black) == 15)
    }
}
