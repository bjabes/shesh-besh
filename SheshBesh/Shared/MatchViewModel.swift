import Foundation
import Observation
import SheshBeshGame

@MainActor
@Observable
public final class MatchViewModel {
    private let engine: MatchEngine

    public private(set) var state: MatchState
    public private(set) var lastError: String?

    public let localPlayer: Player
    public let opponentName: String

    public init(
        engine: MatchEngine = MatchEngine(),
        config: MatchConfig = .tournament(targetScore: 7),
        localPlayer: Player = .white,
        opponentName: String = "Dan"
    ) {
        self.engine = engine
        self.state = MatchEngine.newMatch(config: config)
        self.localPlayer = localPlayer
        self.opponentName = opponentName
    }

    public var legalActions: [MatchAction] {
        engine.legalActions(in: state)
    }

    public var legalMoves: [Move] {
        legalActions.compactMap { action in
            if case .move(let move) = action {
                move
            } else {
                nil
            }
        }
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

    public var localScore: Int {
        state.score.score(for: localPlayer)
    }

    public var opponentScore: Int {
        state.score.score(for: localPlayer.opponent)
    }

    public var phaseTitle: String {
        switch state.game.phase {
        case .awaitingOpeningRoll(let tiedRoll):
            tiedRoll == nil ? "Opening roll" : "Tie. Roll again"
        case .awaitingRoll(let player):
            player == localPlayer ? "Your turn" : "\(opponentName)'s turn"
        case .awaitingMove(let turn):
            turn.player == localPlayer ? "Your turn" : "\(opponentName)'s turn"
        case .awaitingCubeResponse(let offer):
            offer.offeredBy == localPlayer ? "Double offered" : "\(opponentName) offers double"
        case .awaitingResignationResponse(let offer):
            offer.offeredBy == localPlayer ? "Resignation offered" : "\(opponentName) offered to resign"
        case .gameOver(let result):
            result.winner == localPlayer ? "You won game \(state.gameNumber)" : "\(opponentName) won game \(state.gameNumber)"
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
        } catch {
            lastError = String(describing: error)
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

    public func passIfAllowed() {
        guard containsAction(.passTurn(localPlayer)) else { return }
        send(.passTurn(localPlayer))
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
        let board = state.game.board
        let boardPips = board.points.enumerated().reduce(0) { total, item in
            let rawPoint = item.offset + 1
            let point = item.element
            guard point.owner == player else { return total }
            let distance = player == .white ? rawPoint : 25 - rawPoint
            return total + (distance * point.count)
        }
        return boardPips + board.barCount(for: player) * 25
    }
}
