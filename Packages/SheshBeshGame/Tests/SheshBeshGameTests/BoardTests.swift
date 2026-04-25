import Foundation
import SheshBeshGame
import Testing

@Suite("Board")
struct BoardTests {
    @Test("Point IDs reject values outside the board")
    func pointIDRejectsOutOfRangeRawValues() {
        #expect(PointID(rawValue: 0) == nil)
        #expect(PointID(rawValue: 25) == nil)
        #expect(PointID(rawValue: -1) == nil)
    }

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

        let state = try makeMatch(board: board, player: .white, dice: [3])
        let move = Move(player: .white, source: .bar, destination: .point(point(22)), die: 3)
        let next = try MatchEngine().apply(action: .move(move), to: state)
        board = next.game.board

        #expect(board.point(point(22)) == PointState(owner: .white, count: 1))
        #expect(board.barCount(for: .white) == 0)
        #expect(board.barCount(for: .black) == 1)
        #expect(board.totalCheckers(for: .white) == 15)
        #expect(board.totalCheckers(for: .black) == 15)
    }

    @Test("Board initializer rejects invalid point counts")
    func initializerRejectsInvalidPointCounts() {
        expectBoardError(.invalidPointCount) {
            _ = try Board(points: Array(repeating: .empty, count: 23))
        }
        expectBoardError(.invalidPointCount) {
            _ = try Board(points: Array(repeating: .empty, count: 25))
        }
    }

    @Test("Board initializer rejects negative checker counts")
    func initializerRejectsNegativeCheckerCounts() {
        let points = Array(repeating: PointState.empty, count: 24)

        expectBoardError(.negativeCheckerCount) {
            _ = try Board(points: points, whiteBar: -1)
        }
        expectBoardError(.negativeCheckerCount) {
            _ = try Board(points: points, blackBar: -1)
        }
        expectBoardError(.negativeCheckerCount) {
            _ = try Board(points: points, whiteBorneOff: -1)
        }
        expectBoardError(.negativeCheckerCount) {
            _ = try Board(points: points, blackBorneOff: -1)
        }
    }

    @Test("Set point rejects mismatched owner and count")
    func setPointRejectsInvalidOccupancy() throws {
        var board = Board.empty()

        expectBoardError(.invalidPointOccupancy) {
            try board.setPoint(point(1), owner: nil, count: 1)
        }
        expectBoardError(.invalidPointOccupancy) {
            try board.setPoint(point(1), owner: .white, count: 0)
        }
    }

    @Test("Game validity rejects malformed checker totals")
    func isValidForGameRejectsWrongTotals() throws {
        var board = Board.empty()
        try board.setPoint(point(1), owner: .white, count: 14)
        try board.setPoint(point(24), owner: .black, count: 15)

        #expect(!board.isValidForGame())
    }

    @Test("Game validity rejects malformed point ownership")
    func isValidForGameRejectsInvalidPointOccupancy() throws {
        let pointsJSON = ([#"{"owner":"white","count":0}"#] + Array(repeating: #"{"count":0}"#, count: 23))
            .joined(separator: ",")
        let json = """
        {
          "points": [\(pointsJSON)],
          "whiteBar": 0,
          "blackBar": 0,
          "whiteBorneOff": 15,
          "blackBorneOff": 15
        }
        """
        let board = try JSONDecoder().decode(Board.self, from: Data(json.utf8))

        #expect(!board.isValidForGame())
    }

    @Test("Game validity rejects negative decoded counts")
    func isValidForGameRejectsNegativeCounts() throws {
        let pointsJSON = Array(repeating: #"{"count":0}"#, count: 24).joined(separator: ",")
        let json = """
        {
          "points": [\(pointsJSON)],
          "whiteBar": -1,
          "blackBar": 0,
          "whiteBorneOff": 15,
          "blackBorneOff": 15
        }
        """
        let board = try JSONDecoder().decode(Board.self, from: Data(json.utf8))

        #expect(!board.isValidForGame())
    }
}
