public struct MatchEngine: Sendable {
    private let diceRoller: any DiceRolling

    public init(diceRoller: any DiceRolling = SystemDiceRoller()) {
        self.diceRoller = diceRoller
    }

    public static func newMatch(config: MatchConfig) -> MatchState {
        MatchState(config: config)
    }

    public func legalActions(in state: MatchState) -> [MatchAction] {
        Self.legalActions(in: state)
    }

    public static func legalActions(in state: MatchState) -> [MatchAction] {
        guard state.completion == nil else { return [] }

        switch state.game.phase {
        case .awaitingOpeningRoll:
            return [.rollOpeningDice]
        case .awaitingRoll(let player):
            var actions: [MatchAction] = []
            if canOfferDouble(player, in: state) {
                actions.append(.offerDouble(player))
            }
            actions.append(.rollDice(player))
            actions.append(contentsOf: resignationActions(for: player, in: state))
            return actions
        case .awaitingMove(let turn):
            var actions = MoveValidator.legalFirstMoves(for: turn.player, in: state.game).map(MatchAction.move)
            if actions.isEmpty {
                actions.append(.passTurn(turn.player))
            }
            actions.append(contentsOf: resignationActions(for: turn.player, in: state))
            return actions
        case .awaitingCubeResponse(let offer):
            let responder = offer.offeredBy.opponent
            return [.takeDouble(responder), .dropDouble(responder)]
        case .awaitingResignationResponse(let offer):
            let responder = offer.offeredBy.opponent
            return [.acceptResignation(responder), .rejectResignation(responder)]
        case .gameOver:
            return [.startNextGame]
        }
    }

    public func apply(action: MatchAction, to state: MatchState) throws -> MatchState {
        guard state.completion == nil || action == .startNextGame else {
            throw MatchEngineError.matchAlreadyCompleted
        }

        switch action {
        case .rollOpeningDice:
            return try rollOpeningDice(in: state)
        case .rollDice(let player):
            return try rollDice(for: player, in: state)
        case .move(let move):
            return try apply(move: move, to: state)
        case .passTurn(let player):
            return try passTurn(by: player, in: state)
        case .offerDouble(let player):
            return try offerDouble(by: player, in: state)
        case .takeDouble(let player):
            return try takeDouble(by: player, in: state)
        case .dropDouble(let player):
            return try dropDouble(by: player, in: state)
        case .offerResignation(let player, let winKind):
            return try offerResignation(by: player, as: winKind, in: state)
        case .acceptResignation(let player):
            return try acceptResignation(by: player, in: state)
        case .rejectResignation(let player):
            return try rejectResignation(by: player, in: state)
        case .startNextGame:
            return try startNextGame(after: state)
        }
    }

    private func rollOpeningDice(in state: MatchState) throws -> MatchState {
        guard case .awaitingOpeningRoll = state.game.phase else {
            throw MatchEngineError.invalidAction("Opening dice can only be rolled at the start of a game.")
        }
        let whiteDie = try rollDie()
        let blackDie = try rollDie()
        guard whiteDie != blackDie else {
            let tiedRoll = DiceRoll(uncheckedDie1: whiteDie, die2: blackDie)
            var next = state
            next.game.phase = .awaitingOpeningRoll(tiedRoll: tiedRoll)
            return next
        }

        let player: Player = whiteDie > blackDie ? .white : .black
        let roll = DiceRoll(uncheckedDie1: whiteDie, die2: blackDie)
        var next = state
        next.game = Self.beginTurn(player: player, roll: roll, in: state.game)
        return next
    }

    private func rollDice(for player: Player, in state: MatchState) throws -> MatchState {
        guard case .awaitingRoll(player) = state.game.phase else {
            throw MatchEngineError.invalidAction("It is not \(player.rawValue)'s turn to roll.")
        }
        let roll = DiceRoll(uncheckedDie1: try rollDie(), die2: try rollDie())
        var next = state
        next.game = Self.beginTurn(player: player, roll: roll, in: state.game)
        return next
    }

    private func apply(move: Move, to state: MatchState) throws -> MatchState {
        guard case .awaitingMove(let turn) = state.game.phase else {
            throw MatchEngineError.invalidAction("Moves can only be applied while a turn is awaiting checker movement.")
        }
        guard move.player == turn.player else {
            throw MatchEngineError.illegalMove(move)
        }

        let legalMoves = MoveValidator.legalFirstMoves(for: turn.player, in: state.game)
        guard legalMoves.contains(move) else {
            throw MatchEngineError.illegalMove(move)
        }

        var next = state
        try next.game.board.apply(move)

        if next.game.board.borneOffCount(for: move.player) == 15 {
            return Self.finishGame(winner: move.player, board: next.game.board, in: next)
        }

        let remainingDice = turn.remainingDice.removingFirst(move.die)
        if remainingDice.isEmpty {
            next.game.phase = .awaitingRoll(turn.player.opponent)
        } else {
            let nextTurn = TurnState(player: turn.player, roll: turn.roll, remainingDice: remainingDice)
            next.game.phase = .awaitingMove(nextTurn)
            if MoveValidator.legalFirstMoves(for: turn.player, in: next.game).isEmpty {
                next.game.phase = .awaitingRoll(turn.player.opponent)
            }
        }

        return next
    }

    private func passTurn(by player: Player, in state: MatchState) throws -> MatchState {
        guard case .awaitingMove(let turn) = state.game.phase, turn.player == player else {
            throw MatchEngineError.invalidAction("\(player.rawValue) has no turn to pass.")
        }
        guard MoveValidator.legalMoves(for: player, in: state.game).isEmpty else {
            throw MatchEngineError.invalidAction("\(player.rawValue) still has legal moves.")
        }

        var next = state
        next.game.phase = .awaitingRoll(player.opponent)
        return next
    }

    private func offerDouble(by player: Player, in state: MatchState) throws -> MatchState {
        guard Self.canOfferDouble(player, in: state) else {
            throw MatchEngineError.invalidAction("\(player.rawValue) cannot offer a double now.")
        }
        var next = state
        let proposedValue = min(state.game.cube.value * 2, state.config.maximumCubeValue)
        next.game.phase = .awaitingCubeResponse(
            CubeOffer(
                offeredBy: player,
                proposedValue: proposedValue,
                previousCubeValue: state.game.cube.value
            )
        )
        return next
    }

    private func takeDouble(by player: Player, in state: MatchState) throws -> MatchState {
        guard case .awaitingCubeResponse(let offer) = state.game.phase, player == offer.offeredBy.opponent else {
            throw MatchEngineError.invalidAction("\(player.rawValue) cannot take a double now.")
        }

        var next = state
        next.game.cube = state.game.cube.doubled(to: offer.proposedValue, owner: player)
        next.game.phase = .awaitingRoll(offer.offeredBy)
        return next
    }

    private func dropDouble(by player: Player, in state: MatchState) throws -> MatchState {
        guard case .awaitingCubeResponse(let offer) = state.game.phase, player == offer.offeredBy.opponent else {
            throw MatchEngineError.invalidAction("\(player.rawValue) cannot drop a double now.")
        }

        let result = GameResult(
            winner: offer.offeredBy,
            winKind: .single,
            cubeValue: offer.previousCubeValue
        )
        return Self.finishGame(with: result, in: state)
    }

    private func offerResignation(by player: Player, as winKind: WinKind, in state: MatchState) throws -> MatchState {
        let resumePhase: ResumablePhase
        switch state.game.phase {
        case .awaitingRoll(player):
            resumePhase = .awaitingRoll(player)
        case .awaitingMove(let turn) where turn.player == player:
            resumePhase = .awaitingMove(turn)
        default:
            throw MatchEngineError.invalidAction("\(player.rawValue) cannot resign now.")
        }
        guard Self.legalResignationWinKinds(for: player, in: state).contains(winKind) else {
            throw MatchEngineError.invalidAction("\(player.rawValue) cannot offer a \(winKind.rawValue) resignation now.")
        }

        var next = state
        next.game.phase = .awaitingResignationResponse(
            ResignationOffer(offeredBy: player, winKind: winKind, resumePhase: resumePhase)
        )
        return next
    }

    private func acceptResignation(by player: Player, in state: MatchState) throws -> MatchState {
        guard case .awaitingResignationResponse(let offer) = state.game.phase, player == offer.offeredBy.opponent else {
            throw MatchEngineError.invalidAction("\(player.rawValue) cannot accept a resignation now.")
        }
        let result = GameResult(
            winner: player,
            winKind: offer.winKind,
            cubeValue: state.game.cube.value
        )
        return Self.finishGame(with: result, in: state)
    }

    private func rejectResignation(by player: Player, in state: MatchState) throws -> MatchState {
        guard case .awaitingResignationResponse(let offer) = state.game.phase, player == offer.offeredBy.opponent else {
            throw MatchEngineError.invalidAction("\(player.rawValue) cannot reject a resignation now.")
        }
        var next = state
        next.game.phase = offer.resumePhase.gamePhase
        return next
    }

    private func startNextGame(after state: MatchState) throws -> MatchState {
        guard state.completion == nil else {
            throw MatchEngineError.matchAlreadyCompleted
        }
        guard case .gameOver = state.game.phase else {
            throw MatchEngineError.invalidAction("A new game can only start after the current game is over.")
        }

        var next = state
        next.gameNumber += 1
        let isCrawford = next.config.usesCrawfordRule && next.crawfordState == .availableNextGame
        next.crawfordState = isCrawford ? .active : next.crawfordState
        next.game = GameState(
            board: .initial(),
            phase: .awaitingOpeningRoll(),
            cube: CubeState(),
            isCrawford: isCrawford
        )
        return next
    }

    private func rollDie() throws -> Int {
        let die = diceRoller.rollDie()
        guard (1...6).contains(die) else { throw MatchEngineError.invalidDiceValue }
        return die
    }

    private static func beginTurn(player: Player, roll: DiceRoll, in game: GameState) -> GameState {
        var next = game
        next.phase = .awaitingMove(
            TurnState(player: player, roll: roll, remainingDice: roll.playableDice)
        )
        if MoveValidator.legalFirstMoves(for: player, in: next).isEmpty {
            next.phase = .awaitingRoll(player.opponent)
        }
        return next
    }

    private static func finishGame(winner: Player, board: Board, in state: MatchState) -> MatchState {
        let loser = winner.opponent
        let winKind: WinKind
        if board.borneOffCount(for: loser) > 0 {
            winKind = .single
        } else if board.hasCheckerOnBarOrInHomeBoard(of: winner, loser: loser) {
            winKind = .backgammon
        } else {
            winKind = .gammon
        }
        let result = GameResult(winner: winner, winKind: winKind, cubeValue: state.game.cube.value)
        return finishGame(with: result, in: state)
    }

    private static func finishGame(with result: GameResult, in state: MatchState) -> MatchState {
        var next = state
        next.game.phase = .gameOver(result)
        next.score.add(scoredMatchPoints(for: result, in: state), to: result.winner)

        if next.score.score(for: result.winner) >= next.config.targetScore {
            next.completion = MatchCompletion(winner: result.winner, finalScore: next.score)
            return next
        }

        if next.crawfordState == .active {
            next.crawfordState = .completed
        } else if next.config.usesCrawfordRule,
                  next.crawfordState == .notReached,
                  Player.allCases.contains(where: { next.score.score(for: $0) == next.config.targetScore - 1 }) {
            next.crawfordState = .availableNextGame
        }

        return next
    }

    private static func canOfferDouble(_ player: Player, in state: MatchState) -> Bool {
        guard state.config.usesDoublingCube else { return false }
        guard !state.game.isCrawford else { return false }
        guard case .awaitingRoll(player) = state.game.phase else { return false }
        guard state.game.cube.value < state.config.maximumCubeValue else { return false }
        guard !isCubeDead(for: player, in: state) else { return false }
        return state.game.cube.owner == nil || state.game.cube.owner == player
    }

    private static func resignationActions(for player: Player, in state: MatchState) -> [MatchAction] {
        legalResignationWinKinds(for: player, in: state).map { .offerResignation(player, $0) }
    }

    private static func legalResignationWinKinds(for player: Player, in state: MatchState) -> [WinKind] {
        let winner = player.opponent
        let pointsNeeded = max(0, state.config.targetScore - state.score.score(for: winner))
        let fittingKinds = WinKind.allCases.filter { state.game.cube.value * $0.multiplier <= pointsNeeded }
        return fittingKinds.isEmpty ? [.single] : fittingKinds
    }

    private static func isCubeDead(for player: Player, in state: MatchState) -> Bool {
        state.score.score(for: player) + state.game.cube.value >= state.config.targetScore
    }

    private static func scoredMatchPoints(for result: GameResult, in state: MatchState) -> Int {
        let pointsNeeded = max(0, state.config.targetScore - state.score.score(for: result.winner))
        return min(result.points, pointsNeeded)
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
