import SheshBeshGame
import Testing

@Suite("Move notation")
struct MoveNotationTests {
    // MARK: Empty / trivial

    @Test("Empty move list renders as empty string")
    func emptyMoves() {
        #expect(MoveNotation.format([], from: .white) == "")
        #expect(MoveNotation.format([], from: .black) == "")
    }

    // MARK: Single moves

    @Test("Single point-to-point move renders source/destination")
    func singlePointMove() {
        let move = applied(.white, from: 13, to: 8, die: 5)
        #expect(MoveNotation.format([move], from: .white) == "13/8")
    }

    @Test("Single move with hit appends asterisk to destination")
    func singleHit() {
        let move = applied(.white, from: 13, to: 7, die: 6, hit: true)
        #expect(MoveNotation.format([move], from: .white) == "13/7*")
    }

    @Test("Bar entry renders with bar/N")
    func barEntry() {
        let move = appliedBar(.white, to: 22, die: 3)
        #expect(MoveNotation.format([move], from: .white) == "bar/22")
    }

    @Test("Bar entry with hit renders bar/N*")
    func barEntryWithHit() {
        let move = appliedBar(.white, to: 22, die: 3, hit: true)
        #expect(MoveNotation.format([move], from: .white) == "bar/22*")
    }

    @Test("Bear-off renders source/off")
    func bearOff() {
        let move = appliedBearOff(.white, from: 5, die: 5)
        #expect(MoveNotation.format([move], from: .white) == "5/off")
    }

    // MARK: Multiple unrelated moves

    @Test("Two unrelated moves are space-separated")
    func twoUnrelatedMoves() {
        let moves = [
            applied(.white, from: 24, to: 18, die: 6),
            applied(.white, from: 24, to: 23, die: 1),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "24/18 24/23")
    }

    @Test("Bar entry followed by an unrelated move stays as two parts")
    func barPlusUnrelatedMove() {
        let moves = [
            appliedBar(.white, to: 22, die: 3),
            applied(.white, from: 17, to: 9, die: 8),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "bar/22 17/9")
    }

    @Test("Two bear-offs render as separate parts")
    func twoBearOffs() {
        let moves = [
            appliedBearOff(.white, from: 5, die: 5),
            appliedBearOff(.white, from: 2, die: 2),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "5/off 2/off")
    }

    // MARK: Chains

    @Test("Two-step single-checker chain merges intermediate point")
    func chainPointToPoint() {
        let moves = [
            applied(.white, from: 13, to: 7, die: 6),
            applied(.white, from: 7, to: 5, die: 2),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "13/7/5")
    }

    @Test("Chain with hit at the intermediate point keeps the asterisk")
    func chainWithMidHit() {
        let moves = [
            applied(.white, from: 13, to: 7, die: 6, hit: true),
            applied(.white, from: 7, to: 5, die: 2),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "13/7*/5")
    }

    @Test("Chain with hits at every step asterisks each point")
    func chainWithEveryStepHit() {
        let moves = [
            applied(.white, from: 13, to: 7, die: 6, hit: true),
            applied(.white, from: 7, to: 5, die: 2, hit: true),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "13/7*/5*")
    }

    @Test("Chain ending in bear-off shows /off as final segment")
    func chainEndingInBearOff() {
        let moves = [
            applied(.white, from: 5, to: 3, die: 2),
            appliedBearOff(.white, from: 3, die: 3),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "5/3/off")
    }

    @Test("Three-step chain across three different dice")
    func threeStepChain() {
        let moves = [
            applied(.white, from: 24, to: 22, die: 2),
            applied(.white, from: 22, to: 20, die: 2),
            applied(.white, from: 20, to: 18, die: 2),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "24/22/20/18")
    }

    @Test("Bar entry chained into a follow-up move renders bar/A/B")
    func barEntryChain() {
        let moves = [
            appliedBar(.white, to: 22, die: 3),
            applied(.white, from: 22, to: 16, die: 6),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "bar/22/16")
    }

    @Test("Bar entry with hit then chain renders bar/N*/M")
    func barEntryHitThenChain() {
        let moves = [
            appliedBar(.white, to: 22, die: 3, hit: true),
            applied(.white, from: 22, to: 16, die: 6),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "bar/22*/16")
    }

    // MARK: Doubles grouping

    @Test("Doubles with all four checkers playing the same move group as (4)")
    func doublesAllSame() {
        let moves = Array(repeating: applied(.white, from: 6, to: 4, die: 2), count: 4)
        #expect(MoveNotation.format(moves, from: .white) == "6/4(4)")
    }

    @Test("Doubles split into two distinct moves group each as (2)")
    func doublesTwoPairs() {
        let moves = [
            applied(.white, from: 6, to: 4, die: 2),
            applied(.white, from: 6, to: 4, die: 2),
            applied(.white, from: 13, to: 11, die: 2),
            applied(.white, from: 13, to: 11, die: 2),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "6/4(2) 13/11(2)")
    }

    @Test("Wikipedia example: 6/4(3) 13/11 for a 2-2 roll")
    func doublesThreePlusOne() {
        let moves = [
            applied(.white, from: 6, to: 4, die: 2),
            applied(.white, from: 6, to: 4, die: 2),
            applied(.white, from: 6, to: 4, die: 2),
            applied(.white, from: 13, to: 11, die: 2),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "6/4(3) 13/11")
    }

    @Test("Identical moves interleaved with another move still collapse")
    func identicalMovesNonAdjacentCollapse() {
        let moves = [
            applied(.white, from: 6, to: 4, die: 2),
            applied(.white, from: 13, to: 11, die: 2),
            applied(.white, from: 6, to: 4, die: 2),
            applied(.white, from: 6, to: 4, die: 2),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "6/4(3) 13/11")
    }

    @Test("Doubles with one chain and a separate paired move")
    func doublesChainPlusPair() {
        let moves = [
            applied(.white, from: 24, to: 22, die: 2),
            applied(.white, from: 22, to: 20, die: 2),
            applied(.white, from: 13, to: 11, die: 2),
            applied(.white, from: 13, to: 11, die: 2),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "24/22/20 13/11(2)")
    }

    @Test("Repeated identical chain collapses across the full chain")
    func repeatedChainCollapses() {
        let moves = [
            applied(.white, from: 13, to: 11, die: 2),
            applied(.white, from: 11, to: 9, die: 2),
            applied(.white, from: 13, to: 11, die: 2),
            applied(.white, from: 11, to: 9, die: 2),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "13/11/9(2)")
    }

    @Test("Doubles 1-1 from the bar with four entries collapses")
    func doublesAllBarEntries() {
        let moves = Array(repeating: appliedBar(.white, to: 24, die: 1), count: 4)
        #expect(MoveNotation.format(moves, from: .white) == "bar/24(4)")
    }

    @Test("Doubles bear-off pairs collapse into N/off(N)")
    func doublesBearOffsCollapse() {
        let moves = [
            appliedBearOff(.white, from: 2, die: 2),
            appliedBearOff(.white, from: 2, die: 2),
            appliedBearOff(.white, from: 1, die: 2),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "2/off(2) 1/off")
    }

    // MARK: Player perspective (per-player numbering)

    @Test("Black moves render from Black's perspective (25 - rawValue)")
    func blackPerspectiveBasicMove() {
        // Black moves rawValue 12 → 18 (moves "+6" toward black's home).
        // From black's view: 13 → 7 (each player numbers 24 farthest, 1 home).
        let move = applied(.black, from: 12, to: 18, die: 6)
        #expect(MoveNotation.format([move], from: .black) == "13/7")
    }

    @Test("Black opening 6-1 renders as 24/18 13/12 from black's perspective")
    func blackOpeningRendersInBlackNumbering() {
        let moves = [
            applied(.black, from: 1, to: 7, die: 6),   // black's 24/18
            applied(.black, from: 12, to: 13, die: 1), // black's 13/12
        ]
        #expect(MoveNotation.format(moves, from: .black) == "24/18 13/12")
    }

    @Test("Black bar entry uses black's home-side numbering")
    func blackBarEntry() {
        // Black enters from bar onto rawValue=3 (3 = die value).
        // Black's view of rawValue=3 is 25-3 = 22.
        let move = appliedBar(.black, to: 3, die: 3)
        #expect(MoveNotation.format([move], from: .black) == "bar/22")
    }

    @Test("Black bear-off renders source from black perspective")
    func blackBearOff() {
        // Black bears off from rawValue=20 (their 5-point: 25-20=5).
        let move = appliedBearOff(.black, from: 20, die: 5)
        #expect(MoveNotation.format([move], from: .black) == "5/off")
    }

    @Test("Black hit shows asterisk after black-perspective destination")
    func blackHit() {
        // Black moves rawValue 17 → 23 hitting white blot.
        // Black's view: (25-17)/(25-23)* = 8/2*.
        let move = applied(.black, from: 17, to: 23, die: 6, hit: true)
        #expect(MoveNotation.format([move], from: .black) == "8/2*")
    }

    @Test("Black chain with hit reads naturally in black numbering")
    func blackChainWithHit() {
        // rawValue 12 → 18 → 23, with hit at 18. Black's view: 13/7*/2.
        let moves = [
            applied(.black, from: 12, to: 18, die: 6, hit: true),
            applied(.black, from: 18, to: 23, die: 5),
        ]
        #expect(MoveNotation.format(moves, from: .black) == "13/7*/2")
    }

    // MARK: Cross-perspective rendering (the local-player-relative rule)

    @Test("Black move rendered from white perspective uses raw point numbers")
    func blackMoveFromWhitePerspective() {
        // Black plays rawValue 12 → 18 hitting at 18. From white's view those
        // points stay 12 and 18 (white perspective == rawValue numbering).
        let move = applied(.black, from: 12, to: 18, die: 6, hit: true)
        #expect(MoveNotation.format([move], from: .white) == "12/18*")
    }

    @Test("White move rendered from black perspective inverts to 25 - rawValue")
    func whiteMoveFromBlackPerspective() {
        // White plays rawValue 24 → 18. From black's view those points become
        // 1 and 7. So the same move reads as "1/7" to the black-side observer.
        let move = applied(.white, from: 24, to: 18, die: 6)
        #expect(MoveNotation.format([move], from: .black) == "1/7")
    }

    @Test("Bar and off labels are perspective-independent")
    func barAndOffAreIndependent() {
        let barEntry = appliedBar(.black, to: 3, die: 3)
        #expect(MoveNotation.format([barEntry], from: .white) == "bar/3")
        #expect(MoveNotation.format([barEntry], from: .black) == "bar/22")

        let bearOff = appliedBearOff(.black, from: 20, die: 5)
        #expect(MoveNotation.format([bearOff], from: .white) == "20/off")
        #expect(MoveNotation.format([bearOff], from: .black) == "5/off")
    }

    @Test("Same move sequence renders consistently for chained black move from either perspective")
    func chainCoherentFromBothPerspectives() {
        let moves = [
            applied(.black, from: 12, to: 18, die: 6, hit: true),
            applied(.black, from: 18, to: 23, die: 5),
        ]
        #expect(MoveNotation.format(moves, from: .white) == "12/18*/23")
        #expect(MoveNotation.format(moves, from: .black) == "13/7*/2")
    }
}

@Suite("Move notation driven by the engine")
struct EngineDrivenMoveNotationTests {
    // MARK: Standard opening rolls

    @Test("White 6-1 opening from initial board renders 24/18 24/23")
    func whiteOpening_6_1() throws {
        var state = try makeMatch(board: .initial(), player: .white, dice: [6, 1])
        state = try playMoves(
            [
                Move(player: .white, source: .point(point(24)), destination: .point(point(18)), die: 6),
                Move(player: .white, source: .point(point(24)), destination: .point(point(23)), die: 1),
            ],
            on: state
        )
        #expect(notation(from: state, perspective: .white) == "24/18 24/23")
    }

    @Test("Black 6-1 opening (bar point) rendered from both perspectives")
    func blackOpening_6_1_BarPoint() throws {
        var state = try makeMatch(board: .initial(), player: .black, dice: [6, 1])
        // Black plays the bar-point opening: rawValue 12→18 (die 6) and 17→18 (die 1).
        // From black perspective those are 13/7 and 8/7. From white view: rawValues.
        state = try playMoves(
            [
                Move(player: .black, source: .point(point(12)), destination: .point(point(18)), die: 6),
                Move(player: .black, source: .point(point(17)), destination: .point(point(18)), die: 1),
            ],
            on: state
        )
        #expect(notation(from: state, perspective: .white) == "12/18 17/18")
        #expect(notation(from: state, perspective: .black) == "13/7 8/7")
    }

    // MARK: Doubles collapse

    @Test("2-2 doubles played as four 6/4 collapses to 6/4(4)")
    func doubles_2_2_AllSame() throws {
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 4)
        try board.setPoint(point(13), owner: .white, count: 11)
        try board.setPoint(point(19), owner: .black, count: 15)

        var state = try makeMatch(board: board, player: .white, dice: [2, 2, 2, 2])
        let move = Move(player: .white, source: .point(point(6)), destination: .point(point(4)), die: 2)
        state = try playMoves(Array(repeating: move, count: 4), on: state)

        #expect(notation(from: state, perspective: .white) == "6/4(4)")
    }

    @Test("2-2 doubles split into 6/4(3) 13/11 matches the Wikipedia example")
    func doubles_2_2_ThreePlusOne() throws {
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 3)
        try board.setPoint(point(13), owner: .white, count: 12)
        try board.setPoint(point(19), owner: .black, count: 15)

        var state = try makeMatch(board: board, player: .white, dice: [2, 2, 2, 2])
        let sixToFour = Move(player: .white, source: .point(point(6)), destination: .point(point(4)), die: 2)
        let thirteenToEleven = Move(player: .white, source: .point(point(13)), destination: .point(point(11)), die: 2)
        state = try playMoves(
            Array(repeating: sixToFour, count: 3) + [thirteenToEleven],
            on: state
        )

        #expect(notation(from: state, perspective: .white) == "6/4(3) 13/11")
    }

    @Test("2-2 doubles split as 6/4(2) 13/11(2) collapses each pair")
    func doubles_2_2_TwoPairs() throws {
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 2)
        try board.setPoint(point(13), owner: .white, count: 13)
        try board.setPoint(point(19), owner: .black, count: 15)

        var state = try makeMatch(board: board, player: .white, dice: [2, 2, 2, 2])
        let sixToFour = Move(player: .white, source: .point(point(6)), destination: .point(point(4)), die: 2)
        let thirteenToEleven = Move(player: .white, source: .point(point(13)), destination: .point(point(11)), die: 2)
        state = try playMoves(
            [sixToFour, sixToFour, thirteenToEleven, thirteenToEleven],
            on: state
        )

        #expect(notation(from: state, perspective: .white) == "6/4(2) 13/11(2)")
    }

    @Test("Identical moves interleaved still collapse into a single grouped term")
    func interleavedMovesCollapse() throws {
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 3)
        try board.setPoint(point(13), owner: .white, count: 12)
        try board.setPoint(point(19), owner: .black, count: 15)

        var state = try makeMatch(board: board, player: .white, dice: [2, 2, 2, 2])
        let sixToFour = Move(player: .white, source: .point(point(6)), destination: .point(point(4)), die: 2)
        let thirteenToEleven = Move(player: .white, source: .point(point(13)), destination: .point(point(11)), die: 2)
        state = try playMoves(
            [sixToFour, thirteenToEleven, sixToFour, sixToFour],
            on: state
        )

        // Wikipedia keeps the same canonical result regardless of submission order.
        #expect(notation(from: state, perspective: .white) == "6/4(3) 13/11")
    }

    // MARK: Hits and chains

    @Test("6-2 chain through a hit on the bar point renders 13/7*/5")
    func sixTwoChainWithHit() throws {
        var board = Board.empty()
        try board.setPoint(point(13), owner: .white, count: 1)
        try board.setPoint(point(24), owner: .white, count: 14)
        try board.setPoint(point(7), owner: .black, count: 1)
        try board.setPoint(point(1), owner: .black, count: 14)

        var state = try makeMatch(board: board, player: .white, dice: [6, 2])
        state = try playMoves(
            [
                Move(player: .white, source: .point(point(13)), destination: .point(point(7)), die: 6),
                Move(player: .white, source: .point(point(7)), destination: .point(point(5)), die: 2),
            ],
            on: state
        )

        #expect(notation(from: state, perspective: .white) == "13/7*/5")
    }

    @Test("Single move that hits a blot adds an asterisk to the destination")
    func singleHitMove() throws {
        var board = Board.empty()
        try board.setPoint(point(8), owner: .white, count: 1)
        try board.setPoint(point(24), owner: .white, count: 14)
        try board.setPoint(point(5), owner: .black, count: 1)
        try board.setPoint(point(1), owner: .black, count: 14)

        var state = try makeMatch(board: board, player: .white, dice: [3])
        state = try playMoves(
            [Move(player: .white, source: .point(point(8)), destination: .point(point(5)), die: 3)],
            on: state
        )

        #expect(notation(from: state, perspective: .white) == "8/5*")
    }

    // MARK: Bar entry

    @Test("Bar entry that hits a blot reads bar/N*")
    func barEntryWithHit() throws {
        var board = Board.empty()
        try board.setBar(for: .white, count: 1)
        try board.setPoint(point(24), owner: .white, count: 14)
        try board.setPoint(point(22), owner: .black, count: 1)
        try board.setPoint(point(1), owner: .black, count: 14)

        var state = try makeMatch(board: board, player: .white, dice: [3])
        state = try playMoves(
            [Move(player: .white, source: .bar, destination: .point(point(22)), die: 3)],
            on: state
        )

        #expect(notation(from: state, perspective: .white) == "bar/22*")
    }

    @Test("1-1 doubles entering all four checkers from the bar collapses to bar/24(4)")
    func doubles_1_1_FourBarEntries() throws {
        var board = Board.empty()
        try board.setBar(for: .white, count: 4)
        try board.setPoint(point(13), owner: .white, count: 11)
        try board.setPoint(point(1), owner: .black, count: 15)

        var state = try makeMatch(board: board, player: .white, dice: [1, 1, 1, 1])
        let entry = Move(player: .white, source: .bar, destination: .point(point(24)), die: 1)
        state = try playMoves(Array(repeating: entry, count: 4), on: state)

        #expect(notation(from: state, perspective: .white) == "bar/24(4)")
    }

    // MARK: Bear-off

    @Test("Two-step chain ending in bear-off renders 5/3/off")
    func bearOffChain() throws {
        var board = Board.empty()
        try board.setPoint(point(5), owner: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setPoint(point(7), owner: .black, count: 14)
        try board.setBorneOff(for: .black, count: 1)

        var state = try makeMatch(board: board, player: .white, dice: [2, 3])
        state = try playMoves(
            [
                Move(player: .white, source: .point(point(5)), destination: .point(point(3)), die: 2),
                Move(player: .white, source: .point(point(3)), destination: .off, die: 3),
            ],
            on: state
        )

        // Bear-off on the final segment ends the game; previousTurn isn't captured
        // from a game-ending move, so the chain still lives in currentTurnMoves.
        let liveMoves = state.currentTurnMoves
        #expect(MoveNotation.format(liveMoves, from: .white) == "5/3/off")
    }

    @Test("Single bear-off renders source/off")
    func singleBearOff() throws {
        var board = Board.empty()
        try board.setPoint(point(5), owner: .white, count: 1)
        try board.setPoint(point(2), owner: .white, count: 1)
        try board.setBorneOff(for: .white, count: 13)
        try board.setPoint(point(7), owner: .black, count: 14)
        try board.setBorneOff(for: .black, count: 1)

        var state = try makeMatch(board: board, player: .white, dice: [5, 2])
        state = try playMoves(
            [
                Move(player: .white, source: .point(point(5)), destination: .off, die: 5),
                Move(player: .white, source: .point(point(2)), destination: .off, die: 2),
            ],
            on: state
        )

        // Same as above — final move ends the game, so read from currentTurnMoves.
        let liveMoves = state.currentTurnMoves
        #expect(MoveNotation.format(liveMoves, from: .white) == "5/off 2/off")
    }

    // MARK: Skipped turns

    @Test("Auto-skipped roll (no moves played) renders empty notation")
    func autoSkippedRollHasEmptyNotation() throws {
        var board = Board.empty()
        try board.setBar(for: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setPoint(point(24), owner: .black, count: 2)
        try board.setPoint(point(23), owner: .black, count: 2)
        try board.setBorneOff(for: .black, count: 11)

        let engine = MatchEngine(diceRoller: ScriptedDiceRoller([1, 2]))
        let initial = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: board, phase: .awaitingRoll(.white))
        )
        let next = try engine.apply(action: .rollDice(.white), to: initial)

        let previous = try #require(next.previousTurn)
        #expect(previous.wasSkipped)
        #expect(MoveNotation.format(previous.moves, from: .white) == "")
    }

    @Test("Mid-turn auto-skip notation only includes moves that actually played")
    func midTurnAutoSkipKeepsPlayedMoves() throws {
        // White on 6 with one checker, black blockade on 4 makes the second
        // die unplayable. The first move (6→5) plays; the rest auto-skip.
        var board = Board.empty()
        try board.setPoint(point(6), owner: .white, count: 1)
        try board.setBorneOff(for: .white, count: 14)
        try board.setPoint(point(4), owner: .black, count: 2)
        try board.setBorneOff(for: .black, count: 13)

        var state = try makeMatch(board: board, player: .white, dice: [1, 1, 1, 1])
        state = try playMoves(
            [Move(player: .white, source: .point(point(6)), destination: .point(point(5)), die: 1)],
            on: state
        )

        #expect(notation(from: state, perspective: .white) == "6/5")
    }

    // MARK: Local-player perspective consistency

    @Test("Black opponent's hit-and-run reads naturally on white's screen")
    func blackHitChainOnWhiteScreen() throws {
        // White local. Black plays rawValue 12→18 hitting white blot at 18,
        // then 18→23. From white perspective those numbers stay raw.
        var board = Board.empty()
        try board.setPoint(point(12), owner: .black, count: 1)
        try board.setPoint(point(1), owner: .black, count: 14)
        try board.setPoint(point(18), owner: .white, count: 1)
        try board.setPoint(point(24), owner: .white, count: 14)

        var state = try makeMatch(board: board, player: .black, dice: [6, 5])
        state = try playMoves(
            [
                Move(player: .black, source: .point(point(12)), destination: .point(point(18)), die: 6),
                Move(player: .black, source: .point(point(18)), destination: .point(point(23)), die: 5),
            ],
            on: state
        )

        #expect(notation(from: state, perspective: .white) == "12/18*/23")
        #expect(notation(from: state, perspective: .black) == "13/7*/2")
    }
}

// MARK: - Engine-driven helpers

private func playMoves(_ moves: [Move], on state: MatchState) throws -> MatchState {
    var next = state
    let engine = MatchEngine()
    for move in moves {
        next = try engine.apply(action: .move(move), to: next)
    }
    return next
}

private func notation(from state: MatchState, perspective: Player) -> String {
    guard let previous = state.previousTurn else { return "<no previousTurn>" }
    return MoveNotation.format(previous.moves, from: perspective)
}

// MARK: - Helpers

private func applied(
    _ player: Player,
    from source: Int,
    to destination: Int,
    die: Int,
    hit: Bool = false
) -> AppliedMove {
    AppliedMove(
        move: Move(
            player: player,
            source: .point(point(source)),
            destination: .point(point(destination)),
            die: die
        ),
        didHit: hit
    )
}

private func appliedBar(
    _ player: Player,
    to destination: Int,
    die: Int,
    hit: Bool = false
) -> AppliedMove {
    AppliedMove(
        move: Move(
            player: player,
            source: .bar,
            destination: .point(point(destination)),
            die: die
        ),
        didHit: hit
    )
}

private func appliedBearOff(
    _ player: Player,
    from source: Int,
    die: Int
) -> AppliedMove {
    AppliedMove(
        move: Move(
            player: player,
            source: .point(point(source)),
            destination: .off,
            die: die
        )
    )
}
