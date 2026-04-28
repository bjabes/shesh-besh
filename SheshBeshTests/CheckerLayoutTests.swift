import SheshBeshApp
import SheshBeshGame
import Testing

@Suite("Checker layout")
struct CheckerLayoutTests {
    @Test("reconstructs the initial board with stable per-player identities")
    func reconstructsInitialBoard() {
        let layout = CheckerLayout.reconstructed(from: .initial())

        #expect(layout.checkerCount(for: .white) == 15)
        #expect(layout.checkerCount(for: .black) == 15)
        #expect(layout.slots[.point(point(24))]?.count == 2)
        #expect(layout.slots[.point(point(13))]?.count == 5)
        #expect(layout.slots[.point(point(8))]?.count == 3)
        #expect(layout.slots[.point(point(6))]?.count == 5)
        #expect(layout.slots[.point(point(1))]?.count == 2)
        #expect(layout.slots[.point(point(12))]?.count == 5)
        #expect(layout.slots[.point(point(17))]?.count == 3)
        #expect(layout.slots[.point(point(19))]?.count == 5)
    }

    @Test("applying a non-hit move pops the source and pushes the destination")
    func appliesNonHitMove() {
        var layout = CheckerLayout.reconstructed(from: .initial())
        let source = CheckerSlot.point(point(24))
        let destination = CheckerSlot.point(point(18))
        let movedID = layout.slots[source]?.last

        layout.apply(Move(player: .white, source: .point(point(24)), destination: .point(point(18)), die: 6))

        #expect(layout.slots[source]?.count == 1)
        #expect(layout.slots[destination]?.last == movedID)
        #expect(layout.checkerCount(for: .white) == 15)
        #expect(layout.checkerCount(for: .black) == 15)
    }

    @Test("applying a hit sends the opponent blot to the bar")
    func appliesHitMove() throws {
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 1)
        try board.setPoint(point(5), owner: .black, count: 1)
        var layout = CheckerLayout.reconstructed(from: board)

        let movedID = layout.slots[.point(point(6))]?.last
        let hitID = layout.slots[.point(point(5))]?.last
        layout.apply(Move(player: .white, source: .point(point(6)), destination: .point(point(5)), die: 1))

        #expect(layout.slots[.point(point(6))] == nil)
        #expect(layout.slots[.point(point(5))] == movedID.map { [$0] })
        #expect(layout.slots[.bar(.black)] == hitID.map { [$0] })
    }

    @Test("applying a bear-off pushes the checker to the off slot")
    func appliesBearOffMove() throws {
        var board = Board.empty()
        try board.setPoint(point(1), owner: .white, count: 1)
        var layout = CheckerLayout.reconstructed(from: board)
        let movedID = layout.slots[.point(point(1))]?.last

        layout.apply(Move(player: .white, source: .point(point(1)), destination: .off, die: 1))

        #expect(layout.slots[.point(point(1))] == nil)
        #expect(layout.slots[.off(.white)] == movedID.map { [$0] })
    }
}

private extension CheckerLayout {
    func checkerCount(for player: Player) -> Int {
        slots.values.reduce(0) { total, checkerIDs in
            total + checkerIDs.filter { $0.player == player }.count
        }
    }
}

private func point(_ rawValue: Int) -> PointID {
    PointID(rawValue: rawValue)!
}
