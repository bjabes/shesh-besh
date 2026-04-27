import Foundation
import Observation
import SheshBeshGame

@MainActor
@Observable
public final class MatchViewModel {
    private let engine: MatchEngine

    public private(set) var state: MatchState
    public private(set) var lastError: String?
    public private(set) var legalActions: [MatchAction]
    public private(set) var legalMoves: [Move]
    public private(set) var pipCounts: [Player: Int]

    public let localPlayer: Player
    public let opponentName: String

    public init(
        engine: MatchEngine = MatchEngine(),
        config: MatchConfig = .tournament(targetScore: 7),
        localPlayer: Player = .white,
        opponentName: String = "Dan"
    ) {
        let initialState = MatchEngine.newMatch(config: config)
        let initialLegalActions = engine.legalActions(in: initialState)

        self.engine = engine
        self.state = initialState
        self.localPlayer = localPlayer
        self.opponentName = opponentName
        self.legalActions = initialLegalActions
        self.legalMoves = initialLegalActions.compactMap { action in
            if case .move(let move) = action {
                move
            } else {
                nil
            }
        }
        self.pipCounts = Self.computePipCounts(for: initialState.game.board)
    }

    public var activePlayer: Player? {
        switch state.game.phase {
        case .awaitingOpeningRoll:
            nil
        case .awaitingRoll(let player):
            player
        case .awaitingMove(let turn):
            turn.player
        case .awaitingCubeResponse(let offer):
            offer.offeredBy.opponent
        case .awaitingResignationResponse(let offer):
            offer.offeredBy.opponent
        case .gameOver:
            nil
        }
    }

    public var isLocalTurn: Bool {
        activePlayer == localPlayer
    }

    public var isOpponentTurn: Bool {
        activePlayer == localPlayer.opponent
    }

    public var currentCubeOffer: CubeOffer? {
        if case .awaitingCubeResponse(let offer) = state.game.phase {
            return offer
        }
        return nil
    }

    public var doubleOfferForLocalPlayer: CubeOffer? {
        guard let offer = currentCubeOffer, offer.offeredBy.opponent == localPlayer else {
            return nil
        }
        return offer
    }

    public var localScore: Int {
        state.score.score(for: localPlayer)
    }

    public var opponentScore: Int {
        state.score.score(for: localPlayer.opponent)
    }

    public var phaseTitle: String {
        if let completion = state.completion {
            return completion.winner == localPlayer ? "You won the match" : "\(opponentName) won the match"
        }

        switch state.game.phase {
        case .awaitingOpeningRoll(let tiedRoll):
            return tiedRoll == nil ? "Opening roll" : "Tie. Roll again"
        case .awaitingRoll(let player):
            return player == localPlayer ? "Your turn" : "\(opponentName)'s turn"
        case .awaitingMove(let turn):
            return turn.player == localPlayer ? "Your turn" : "\(opponentName)'s turn"
        case .awaitingCubeResponse(let offer):
            return offer.offeredBy == localPlayer ? "Double offered" : "\(opponentName) offers double"
        case .awaitingResignationResponse(let offer):
            let description = winKindText(offer.winKind)
            return offer.offeredBy == localPlayer ? "Resignation offered (\(description))" : "\(opponentName) offered to resign (\(description))"
        case .gameOver(let result):
            return result.winner == localPlayer ? "You won game \(state.gameNumber)" : "\(opponentName) won game \(state.gameNumber)"
        }
    }

    public func displayName(for player: Player) -> String {
        player == localPlayer ? "You" : opponentName
    }

    public func containsAction(_ action: MatchAction) -> Bool {
        legalActions.contains(action)
    }

    public func send(_ action: MatchAction) {
        do {
            state = try engine.apply(action: action, to: state)
            lastError = nil
            refreshDerivedState()
        } catch {
            lastError = friendlyErrorMessage(error)
        }
    }

    public func rollOpeningDice() {
        send(.rollOpeningDice)
    }

    public func rollDiceIfAllowed() {
        guard let player = activePlayer, containsAction(.rollDice(player)) else { return }
        send(.rollDice(player))
    }

    public func offerDoubleIfAllowed() {
        guard containsAction(.offerDouble(localPlayer)) else { return }
        send(.offerDouble(localPlayer))
    }

    public func takeDoubleIfAllowed() {
        guard containsAction(.takeDouble(localPlayer)) else { return }
        send(.takeDouble(localPlayer))
    }

    public func dropDoubleIfAllowed() {
        guard containsAction(.dropDouble(localPlayer)) else { return }
        send(.dropDouble(localPlayer))
    }

    public func offerResignationIfAllowed(_ winKind: WinKind) {
        guard containsAction(.offerResignation(localPlayer, winKind)) else { return }
        send(.offerResignation(localPlayer, winKind))
    }

    public func passIfAllowed() {
        guard containsAction(.passTurn(localPlayer)) else { return }
        send(.passTurn(localPlayer))
    }

    public func restartMatch() {
        state = MatchEngine.newMatch(config: state.config)
        lastError = nil
        refreshDerivedState()
    }

    @discardableResult
    public func applyMove(from source: MoveSource, to destination: MoveDestination) -> Bool {
        guard let move = legalMoves.first(where: { $0.source == source && $0.destination == destination }) else {
            return false
        }
        send(.move(move))
        return lastError == nil
    }

    public func legalDestinations(from source: MoveSource) -> [MoveDestination] {
        legalMoves.filter { $0.source == source }.map(\.destination)
    }

    public func isLegalSource(_ source: MoveSource) -> Bool {
        legalMoves.contains { $0.source == source }
    }

    public func isLegalDestination(_ destination: MoveDestination, from source: MoveSource?) -> Bool {
        guard let source else { return false }
        return legalMoves.contains { $0.source == source && $0.destination == destination }
    }

    public func pipCount(for player: Player) -> Int {
        pipCounts[player, default: 0]
    }

    private func refreshDerivedState() {
        legalActions = engine.legalActions(in: state)
        legalMoves = legalActions.compactMap { action in
            if case .move(let move) = action {
                move
            } else {
                nil
            }
        }
        pipCounts = Self.computePipCounts(for: state.game.board)
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        guard let engineError = error as? MatchEngineError else {
            return error.localizedDescription
        }

        switch engineError {
        case .invalidDiceValue:
            return "The dice roll was invalid. Please roll again."
        case .invalidAction(let reason):
            return reason
        case .illegalMove:
            return "That move is not legal for the current dice."
        case .matchAlreadyCompleted:
            return "The match is already complete. Start a new match to continue."
        }
    }

    private static func computePipCounts(for board: Board) -> [Player: Int] {
        var white = 0
        var black = 0

        for (offset, point) in board.points.enumerated() {
            let rawPoint = offset + 1
            switch point.owner {
            case .white:
                white += rawPoint * point.count
            case .black:
                black += (25 - rawPoint) * point.count
            case nil:
                continue
            }
        }
        white += board.barCount(for: .white) * 25
        black += board.barCount(for: .black) * 25
        return [.white: white, .black: black]
    }

    private func winKindText(_ winKind: WinKind) -> String {
        switch winKind {
        case .single: return "single"
        case .gammon: return "gammon"
        case .backgammon: return "backgammon"
        }
    }
}
