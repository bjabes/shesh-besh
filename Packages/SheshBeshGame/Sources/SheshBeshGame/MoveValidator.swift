public enum MoveValidator {
    public static func legalMoves(for player: Player, in game: GameState) -> [MoveSequence] {
        guard case .awaitingMove(let turn) = game.phase, turn.player == player else {
            return []
        }
        return legalMoves(for: player, board: game.board, dice: turn.remainingDice)
    }

    public static func legalMoves(for player: Player, board: Board, dice: [Int]) -> [MoveSequence] {
        let validDice = dice.filter { (1...6).contains($0) }
        guard !validDice.isEmpty else { return [] }

        let rawSequences = generateSequences(
            player: player,
            board: board,
            dice: validDice
        )
        let nonEmptySequences = rawSequences.filter { !$0.moves.isEmpty }
        guard let maxMoveCount = nonEmptySequences.map(\.moves.count).max() else {
            return []
        }

        var sequences = nonEmptySequences.filter { $0.moves.count == maxMoveCount }
        if shouldApplyHigherDieRule(originalDice: validDice, maxMoveCount: maxMoveCount) {
            let higherDie = validDice.max()!
            let higherDieSequences = sequences.filter { $0.moves.first?.die == higherDie }
            if !higherDieSequences.isEmpty {
                sequences = higherDieSequences
            }
        }

        return uniqueSorted(sequences)
    }

    public static func legalFirstMoves(for player: Player, in game: GameState) -> [Move] {
        uniqueSortedMoves(legalMoves(for: player, in: game).compactMap(\.moves.first))
    }

    public static func legalFirstMoves(for player: Player, board: Board, dice: [Int]) -> [Move] {
        uniqueSortedMoves(legalMoves(for: player, board: board, dice: dice).compactMap(\.moves.first))
    }

    private static func generateSequences(
        player: Player,
        board: Board,
        dice: [Int]
    ) -> [MoveSequence] {
        let moves = legalSingleMoves(player: player, board: board, dice: dice)
        guard !moves.isEmpty else {
            return [MoveSequence(moves: [])]
        }

        var sequences: [MoveSequence] = []
        for move in moves {
            var nextBoard = board
            do {
                try nextBoard.apply(move)
            } catch {
                continue
            }
            let remainingDice = dice.removingFirst(move.die)
            let tails = generateSequences(player: player, board: nextBoard, dice: remainingDice)
            for tail in tails {
                sequences.append(MoveSequence(moves: [move] + tail.moves))
            }
        }
        return sequences
    }

    private static func legalSingleMoves(player: Player, board: Board, dice: [Int]) -> [Move] {
        let uniqueDice = Array(Set(dice)).sorted()
        let sources: [MoveSource]
        if board.barCount(for: player) > 0 {
            sources = [.bar]
        } else {
            sources = board.occupiedPoints(for: player).map { .point($0) }
        }

        var moves: [Move] = []
        for die in uniqueDice {
            for source in sources {
                guard let destination = destination(for: source, player: player, die: die, board: board) else {
                    continue
                }
                if case .point(let point) = destination, !board.canLand(on: point, player: player) {
                    continue
                }
                moves.append(Move(player: player, source: source, destination: destination, die: die))
            }
        }

        return uniqueSortedMoves(moves)
    }

    private static func destination(
        for source: MoveSource,
        player: Player,
        die: Int,
        board: Board
    ) -> MoveDestination? {
        switch source {
        case .bar:
            guard let entryPoint = player.entryPoint(for: die) else { return nil }
            return .point(entryPoint)
        case .point(let point):
            let destinationRawValue = point.rawValue + (player.movementDirection * die)
            if let destinationPoint = PointID(rawValue: destinationRawValue) {
                return .point(destinationPoint)
            }
            return board.canBearOff(player: player, from: point, die: die) ? .off : nil
        }
    }

    private static func shouldApplyHigherDieRule(originalDice: [Int], maxMoveCount: Int) -> Bool {
        originalDice.count == 2 && Set(originalDice).count == 2 && maxMoveCount == 1
    }

    private static func uniqueSorted(_ sequences: [MoveSequence]) -> [MoveSequence] {
        Array(Set(sequences)).sorted { sequenceSortKey($0) < sequenceSortKey($1) }
    }

    private static func uniqueSortedMoves(_ moves: [Move]) -> [Move] {
        Array(Set(moves)).sorted { moveSortKey($0) < moveSortKey($1) }
    }

    private static func sequenceSortKey(_ sequence: MoveSequence) -> String {
        sequence.moves.map(moveSortKey).joined(separator: "|")
    }

    private static func moveSortKey(_ move: Move) -> String {
        "\(move.player.rawValue):\(move.die):\(sourceSortKey(move.source)):\(destinationSortKey(move.destination))"
    }

    private static func sourceSortKey(_ source: MoveSource) -> String {
        switch source {
        case .bar: "00-bar"
        case .point(let point): "\(padded(point.rawValue))-point"
        }
    }

    private static func destinationSortKey(_ destination: MoveDestination) -> String {
        switch destination {
        case .off: "99-off"
        case .point(let point): "\(padded(point.rawValue))-point"
        }
    }

    private static func padded(_ rawValue: Int) -> String {
        rawValue < 10 ? "0\(rawValue)" : "\(rawValue)"
    }
}

private extension Array where Element == Int {
    func removingFirst(_ value: Int) -> [Int] {
        var copy = self
        if let index = copy.firstIndex(of: value) {
            copy.remove(at: index)
        }
        return copy
    }
}
