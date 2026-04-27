import Foundation
import Observation
import SheshBeshGame

@MainActor
@Observable
public final class MatchViewModel {
    private let engine: MatchEngine
    private let opponentController: LocalAIOpponent
    private let opponentDelay: @Sendable () async -> Void
    @ObservationIgnored private var opponentTask: Task<Void, Never>?

    public private(set) var state: MatchState
    public private(set) var lastError: String?
    public private(set) var legalActions: [MatchAction]
    public private(set) var legalMoves: [Move]
    public private(set) var pipCounts: [Player: Int]
    public private(set) var isOpponentThinking: Bool
    public private(set) var turnNotice: String?
    private var turnDraftSnapshots: [MatchState]

    public let localPlayer: Player
    public let opponentName: String
    public let isOpponentAutoplayEnabled: Bool
    public let activeMatchID: UUID

    @ObservationIgnored public var onStateChange: (@MainActor (MatchState) -> Void)?
    @ObservationIgnored public var onCompletion: (@MainActor (MatchState) -> Void)?

    private var didNotifyCompletion: Bool

    public init(
        engine: MatchEngine = MatchEngine(),
        config: MatchConfig = .tournament(targetScore: 1),
        localPlayer: Player = .white,
        opponentName: String = "Local AI",
        activeMatchID: UUID = UUID(),
        initialState: MatchState? = nil,
        isOpponentAutoplayEnabled: Bool = true,
        opponentController: LocalAIOpponent = LocalAIOpponent(),
        opponentDelay: @escaping @Sendable () async -> Void = {
            let nanoseconds = UInt64(Double.random(in: 0.8...1.2) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        let initialState = initialState ?? MatchEngine.newMatch(config: config)
        let initialLegalActions = engine.legalActions(in: initialState)

        self.engine = engine
        self.state = initialState
        self.localPlayer = localPlayer
        self.opponentName = opponentName
        self.isOpponentAutoplayEnabled = isOpponentAutoplayEnabled
        self.activeMatchID = activeMatchID
        self.opponentController = opponentController
        self.opponentDelay = opponentDelay
        self.isOpponentThinking = false
        self.turnNotice = nil
        self.turnDraftSnapshots = []
        self.legalActions = initialLegalActions
        self.legalMoves = initialLegalActions.compactMap { action in
            if case .move(let move) = action {
                move
            } else {
                nil
            }
        }
        self.pipCounts = Self.computePipCounts(for: initialState.game.board)
        self.didNotifyCompletion = initialState.completion != nil

        scheduleOpponentTurnIfNeeded()
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
        isTurnDraftPending || activePlayer == localPlayer
    }

    public var isOpponentTurn: Bool {
        !isTurnDraftPending && activePlayer == localPlayer.opponent
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

    public var isOpponentAutomationActive: Bool {
        guard isOpponentAutoplayEnabled else { return false }
        guard !isTurnDraftPending else { return false }
        return opponentController.canAct(
            as: localPlayer.opponent,
            in: state,
            legalActions: legalActions
        )
    }

    public var interactiveLegalMoves: [Move] {
        guard !isOpponentAutomationActive else { return [] }
        guard activePlayer == localPlayer else { return [] }
        return legalMoves
    }

    public var localScore: Int {
        state.score.score(for: localPlayer)
    }

    public var opponentScore: Int {
        state.score.score(for: localPlayer.opponent)
    }

    public var isTurnDraftPending: Bool {
        !turnDraftSnapshots.isEmpty
    }

    public var canUndoTurnMove: Bool {
        isTurnDraftPending
    }

    public var canSubmitTurn: Bool {
        guard isTurnDraftPending else { return false }

        if state.completion != nil {
            return true
        }

        switch state.game.phase {
        case .awaitingMove(let turn) where turn.player == localPlayer:
            return MoveValidator.legalFirstMoves(for: localPlayer, in: state.game).isEmpty
        default:
            return activePlayer != localPlayer
        }
    }

    public var phaseTitle: String {
        if let completion = state.completion {
            return completion.winner == localPlayer ? "You won the match" : "\(opponentName) won the match"
        }

        if isTurnDraftPending, canSubmitTurn {
            return "Ready to submit"
        }

        if isOpponentAutomationActive {
            return isOpponentThinking ? "\(opponentName) is thinking" : "\(opponentName)'s turn"
        }

        if activePlayer == localPlayer, let turnNotice {
            return turnNotice
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
        if case .move(let move) = action, shouldDraft(move) {
            applyDraft(move)
            return
        }

        apply(action, schedulesOpponent: true)
    }

    private func apply(_ action: MatchAction, schedulesOpponent: Bool) {
        do {
            let hadCompletion = state.completion != nil
            state = try engine.apply(action: action, to: state)
            lastError = nil
            turnDraftSnapshots.removeAll()
            refreshDerivedState()
            notifyStorageCallbacks(hadCompletion: hadCompletion)
            if schedulesOpponent {
                turnNotice = nil
                scheduleOpponentTurnIfNeeded()
            }
        } catch {
            lastError = friendlyErrorMessage(error)
        }
    }

    public func rollOpeningDice() {
        send(.rollOpeningDice)
    }

    public func rollDiceIfAllowed() {
        guard let player = activePlayer, player == localPlayer, containsAction(.rollDice(player)) else { return }
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
        turnDraftSnapshots.removeAll()
        didNotifyCompletion = false
        refreshDerivedState()
        onStateChange?(state)
        scheduleOpponentTurnIfNeeded()
    }

    @discardableResult
    public func applyMove(from source: MoveSource, to destination: MoveDestination) -> Bool {
        guard !isOpponentAutomationActive else {
            return false
        }
        guard let move = legalMoves.first(where: { $0.source == source && $0.destination == destination }) else {
            return false
        }
        applyDraft(move)
        return lastError == nil
    }

    public func undoLastMove() {
        guard let previousState = turnDraftSnapshots.popLast() else { return }
        state = previousState
        lastError = nil
        turnNotice = nil
        refreshDerivedState()
    }

    @discardableResult
    public func submitTurnIfAllowed() -> Bool {
        guard isTurnDraftPending else {
            lastError = "Make a move before submitting."
            return false
        }

        guard canSubmitTurn else {
            lastError = "Finish all legal moves before submitting."
            return false
        }

        let hadCompletion = turnDraftSnapshots.first?.completion != nil
        turnDraftSnapshots.removeAll()
        lastError = nil
        refreshDerivedState()
        notifyStorageCallbacks(hadCompletion: hadCompletion)
        turnNotice = nil
        scheduleOpponentTurnIfNeeded()
        return true
    }

    public func legalDestinations(from source: MoveSource) -> [MoveDestination] {
        interactiveLegalMoves.filter { $0.source == source }.map(\.destination)
    }

    public func isLegalSource(_ source: MoveSource) -> Bool {
        interactiveLegalMoves.contains { $0.source == source }
    }

    public func isLegalDestination(_ destination: MoveDestination, from source: MoveSource?) -> Bool {
        guard let source else { return false }
        return interactiveLegalMoves.contains { $0.source == source && $0.destination == destination }
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

    private func shouldDraft(_ move: Move) -> Bool {
        guard move.player == localPlayer else { return false }
        guard !isOpponentAutomationActive else { return false }
        guard case .awaitingMove(let turn) = state.game.phase, turn.player == localPlayer else {
            return false
        }
        return true
    }

    private func applyDraft(_ move: Move) {
        guard shouldDraft(move) else {
            apply(.move(move), schedulesOpponent: true)
            return
        }

        turnDraftSnapshots.append(state)
        do {
            state = try engine.apply(action: .move(move), to: state)
            lastError = nil
            turnNotice = nil
            refreshDerivedState()
        } catch {
            _ = turnDraftSnapshots.popLast()
            lastError = friendlyErrorMessage(error)
        }
    }

    private func scheduleOpponentTurnIfNeeded() {
        guard isOpponentAutomationActive else {
            isOpponentThinking = false
            return
        }
        guard opponentTask == nil else { return }

        isOpponentThinking = true
        opponentTask = Task { [weak self] in
            await self?.playOpponentUntilLocalTurn()
        }
    }

    private func playOpponentUntilLocalTurn() async {
        while !Task.isCancelled {
            guard isOpponentAutomationActive else { break }
            isOpponentThinking = true
            await opponentDelay()
            guard !Task.isCancelled else { break }

            guard let action = opponentController.action(
                as: localPlayer.opponent,
                in: state,
                legalActions: legalActions,
                pipCounts: pipCounts
            ) else {
                break
            }

            let previousState = state
            apply(action, schedulesOpponent: false)
            refreshOpponentTurnNotice(after: action, from: previousState)
        }

        isOpponentThinking = false
        opponentTask = nil
    }

    private func refreshOpponentTurnNotice(after action: MatchAction, from previousState: MatchState) {
        guard lastError == nil else { return }
        let opponent = localPlayer.opponent

        switch action {
        case .passTurn(let player) where player == opponent:
            turnNotice = "\(opponentName) had no legal moves"
        case .rollDice(let player) where player == opponent:
            if case .awaitingRoll(let previousPlayer) = previousState.game.phase,
               previousPlayer == opponent,
               activePlayer == localPlayer {
                turnNotice = "\(opponentName) had no legal moves"
            }
        default:
            break
        }
    }

    private func notifyStorageCallbacks(hadCompletion: Bool) {
        if !hadCompletion, state.completion != nil, !didNotifyCompletion {
            didNotifyCompletion = true
            onCompletion?(state)
        } else if state.completion == nil {
            onStateChange?(state)
        }
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

public struct LocalAIOpponent: Sendable {
    private let randomIndex: @Sendable (Int) -> Int

    public init(randomIndex: @escaping @Sendable (Int) -> Int = { upperBound in
        Int.random(in: 0..<upperBound)
    }) {
        self.randomIndex = randomIndex
    }

    public func canAct(
        as opponent: Player,
        in state: MatchState,
        legalActions: [MatchAction]
    ) -> Bool {
        actionKind(as: opponent, in: state, legalActions: legalActions) != nil
    }

    public func action(
        as opponent: Player,
        in state: MatchState,
        legalActions: [MatchAction],
        pipCounts: [Player: Int]
    ) -> MatchAction? {
        switch actionKind(as: opponent, in: state, legalActions: legalActions) {
        case .roll:
            return .rollDice(opponent)
        case .move:
            return selectPipBiasedMove(
                for: opponent,
                in: state,
                legalActions: legalActions,
                pipCounts: pipCounts
            ).map(MatchAction.move)
        case .pass:
            return .passTurn(opponent)
        case .cubeResponse(let offer):
            return shouldDropDouble(
                offer,
                as: opponent,
                in: state,
                pipCounts: pipCounts
            ) ? .dropDouble(opponent) : .takeDouble(opponent)
        case .resignationResponse:
            return .acceptResignation(opponent)
        case nil:
            return nil
        }
    }

    public func selectPipBiasedMove(
        for player: Player,
        in state: MatchState,
        legalActions: [MatchAction],
        pipCounts: [Player: Int]
    ) -> Move? {
        let moves = legalActions.compactMap { action -> Move? in
            if case .move(let move) = action, move.player == player {
                return move
            }
            return nil
        }
        guard !moves.isEmpty else { return nil }

        let currentPips = pipCounts[player, default: 0]
        let rankedMoves = moves.map { move in
            (move: move, projectedPips: projectedPipCount(currentPips, after: move))
        }
        guard let bestPips = rankedMoves.map(\.projectedPips).min() else { return nil }
        let bestMoves = rankedMoves.filter { $0.projectedPips == bestPips }.map(\.move)
        return bestMoves[clampedRandomIndex(upperBound: bestMoves.count)]
    }

    private enum ActionKind {
        case roll
        case move
        case pass
        case cubeResponse(CubeOffer)
        case resignationResponse
    }

    private func actionKind(
        as opponent: Player,
        in state: MatchState,
        legalActions: [MatchAction]
    ) -> ActionKind? {
        guard state.completion == nil else { return nil }

        switch state.game.phase {
        case .awaitingRoll(let player) where player == opponent:
            return legalActions.contains(.rollDice(opponent)) ? .roll : nil
        case .awaitingMove(let turn) where turn.player == opponent:
            if legalActions.contains(where: { action in
                if case .move(let move) = action {
                    return move.player == opponent
                }
                return false
            }) {
                return .move
            }
            return legalActions.contains(.passTurn(opponent)) ? .pass : nil
        case .awaitingCubeResponse(let offer) where offer.offeredBy.opponent == opponent:
            return .cubeResponse(offer)
        case .awaitingResignationResponse(let offer) where offer.offeredBy.opponent == opponent:
            return .resignationResponse
        default:
            return nil
        }
    }

    private func shouldDropDouble(
        _ offer: CubeOffer,
        as opponent: Player,
        in state: MatchState,
        pipCounts: [Player: Int]
    ) -> Bool {
        let pointsNeeded = state.config.targetScore - state.score.score(for: offer.offeredBy)
        guard offer.proposedValue >= pointsNeeded else { return false }

        let opponentPips = pipCounts[opponent, default: 0]
        let offeringPlayerPips = pipCounts[offer.offeredBy, default: 0]
        return opponentPips - offeringPlayerPips >= 50
    }

    private func projectedPipCount(_ currentPips: Int, after move: Move) -> Int {
        currentPips - sourcePips(for: move) + destinationPips(for: move)
    }

    private func sourcePips(for move: Move) -> Int {
        switch move.source {
        case .bar:
            return 25
        case .point(let point):
            return pips(from: point, for: move.player)
        }
    }

    private func destinationPips(for move: Move) -> Int {
        switch move.destination {
        case .off:
            return 0
        case .point(let point):
            return pips(from: point, for: move.player)
        }
    }

    private func pips(from point: PointID, for player: Player) -> Int {
        switch player {
        case .white:
            return point.rawValue
        case .black:
            return 25 - point.rawValue
        }
    }

    private func clampedRandomIndex(upperBound: Int) -> Int {
        min(max(randomIndex(upperBound), 0), upperBound - 1)
    }
}
