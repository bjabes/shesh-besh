import Foundation
import Observation
import SheshBeshGame
import SwiftUI

public enum AIDifficulty: String, CaseIterable, Codable, Sendable {
    case easy
    case medium
    case hard

    public var rivalDisplayName: String {
        switch self {
        case .easy: "Easy AI"
        case .medium: "Medium AI"
        case .hard: "Hard AI"
        }
    }

    public var menuLabel: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }

    public static func fromRivalDisplayName(_ name: String) -> AIDifficulty? {
        AIDifficulty.allCases.first { $0.rivalDisplayName == name }
    }
}

@MainActor
@Observable
public final class MatchViewModel {
    private static let checkerMoveAnimation = Animation.spring(response: 0.32, dampingFraction: 0.82)

    private let engine: MatchEngine
    private let opponentController: LocalAIOpponent
    private let opponentDelay: @Sendable () async -> Void
    private let raceAutoplayController: LocalAIOpponent
    private let raceAutoplayDelay: @Sendable () async -> Void
    @ObservationIgnored private var opponentTask: Task<Void, Never>?
    @ObservationIgnored private var raceAutoplayTask: Task<Void, Never>?

    public private(set) var state: MatchState
    public private(set) var checkerLayout: CheckerLayout
    public private(set) var lastError: String?
    public private(set) var legalActions: [MatchAction]
    public private(set) var legalMoves: [Move]
    public private(set) var pipCounts: [Player: Int]
    public private(set) var isOpponentThinking: Bool
    public private(set) var isRaceAutoplayActive: Bool
    public private(set) var isRaceAutoplayUserStopped: Bool
    public private(set) var turnNotice: String?
    private var turnDraftSnapshots: [(state: MatchState, layout: CheckerLayout)]
    private var isLocalAutoplayRequested: Bool
    private var isBatchingRaceAutoplayCallbacks: Bool
    private var raceAutoplayNeedsStateChange: Bool
    private var raceAutoplayNeedsCompletion: Bool

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
        opponentName: String = "Medium AI",
        activeMatchID: UUID = UUID(),
        initialState: MatchState? = nil,
        isOpponentAutoplayEnabled: Bool = true,
        aiDifficulty: AIDifficulty = .medium,
        opponentController: LocalAIOpponent? = nil,
        raceAutoplayController: LocalAIOpponent? = nil,
        opponentDelay: @escaping @Sendable () async -> Void = {
            let nanoseconds = UInt64(Double.random(in: 0.8...1.2) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        raceAutoplayDelay: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    ) {
        let initialState = initialState ?? MatchEngine.newMatch(config: config)
        let initialLegalActions = engine.legalActions(in: initialState)

        self.engine = engine
        self.state = initialState
        self.checkerLayout = CheckerLayout.reconstructed(from: initialState.game.board)
        self.localPlayer = localPlayer
        self.opponentName = opponentName
        self.isOpponentAutoplayEnabled = isOpponentAutoplayEnabled
        self.activeMatchID = activeMatchID
        let resolvedOpponentController = opponentController ?? LocalAIOpponent(difficulty: aiDifficulty)
        self.opponentController = resolvedOpponentController
        self.opponentDelay = opponentDelay
        self.raceAutoplayController = raceAutoplayController
            ?? (isOpponentAutoplayEnabled ? resolvedOpponentController : LocalAIOpponent(difficulty: aiDifficulty))
        self.raceAutoplayDelay = raceAutoplayDelay
        self.isOpponentThinking = false
        self.isRaceAutoplayActive = false
        self.isRaceAutoplayUserStopped = false
        self.turnNotice = nil
        self.turnDraftSnapshots = []
        self.isLocalAutoplayRequested = false
        self.isBatchingRaceAutoplayCallbacks = false
        self.raceAutoplayNeedsStateChange = false
        self.raceAutoplayNeedsCompletion = false
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

        scheduleAutomationIfNeeded()
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
        guard !isRaceAutoplayActive else { return false }
        guard !isTurnDraftPending else { return false }
        return opponentController.canAct(
            as: localPlayer.opponent,
            in: state,
            legalActions: legalActions
        )
    }

    public var interactiveLegalMoves: [Move] {
        guard !isRaceAutoplayActive else { return [] }
        guard !isOpponentAutomationActive else { return [] }
        guard activePlayer == localPlayer else { return [] }
        return legalMoves
    }

    public var canStartRaceAutoplay: Bool {
        raceAutoplayTask == nil && isRaceAutoplayEligible(ignoresUserStopped: true)
    }

    public var canStartLocalAutoplay: Bool {
        raceAutoplayTask == nil && isLocalAutoplayEligible()
    }

    public var autoplayStatusText: String {
        isLocalAutoplayRequested ? "Autoplaying turn..." : "Autoplaying race..."
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

        return activePlayer != localPlayer
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

        if isRaceAutoplayActive {
            return isLocalAutoplayRequested ? "Autoplaying turn" : "Autoplaying race"
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
            let nextState = try engine.apply(action: action, to: state)
            let applyStateChanges = {
                self.state = nextState
                if case .move(let move) = action {
                    self.checkerLayout.apply(move)
                } else if action == .startNextGame {
                    self.checkerLayout = CheckerLayout.reconstructed(from: nextState.game.board)
                    self.isRaceAutoplayUserStopped = false
                }
                self.lastError = nil
                self.turnDraftSnapshots.removeAll()
                self.refreshDerivedState()
            }

            if case .move = action {
                withAnimation(Self.checkerMoveAnimation, applyStateChanges)
            } else {
                applyStateChanges()
            }

            queueOrNotifyStorageCallbacks(hadCompletion: hadCompletion)
            if schedulesOpponent {
                turnNotice = nil
                scheduleAutomationIfNeeded()
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
        let nextState = MatchEngine.newMatch(config: state.config)
        state = nextState
        checkerLayout = CheckerLayout.reconstructed(from: nextState.game.board)
        lastError = nil
        turnDraftSnapshots.removeAll()
        isLocalAutoplayRequested = false
        isRaceAutoplayUserStopped = false
        didNotifyCompletion = false
        refreshDerivedState()
        onStateChange?(state)
        scheduleAutomationIfNeeded()
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
        guard let snapshot = turnDraftSnapshots.popLast() else { return }
        withAnimation(Self.checkerMoveAnimation) {
            state = snapshot.state
            checkerLayout = snapshot.layout
            lastError = nil
            turnNotice = nil
            refreshDerivedState()
        }
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

        turnDraftSnapshots.removeAll()
        lastError = nil
        refreshDerivedState()
        notifyStorageCallbacks(hadCompletion: false)
        turnNotice = nil
        scheduleAutomationIfNeeded()
        return true
    }

    public func startRaceAutoplay() {
        isLocalAutoplayRequested = false
        isRaceAutoplayUserStopped = false
        scheduleRaceAutoplayIfNeeded()
    }

    public func startLocalAutoplay() {
        guard isLocalAutoplayEligible() else {
            isLocalAutoplayRequested = false
            return
        }
        isLocalAutoplayRequested = true
        isRaceAutoplayUserStopped = false
        scheduleAutoplayTaskIfNeeded()
    }

    public func stopRaceAutoplay() {
        isRaceAutoplayUserStopped = true
        isLocalAutoplayRequested = false
        raceAutoplayTask?.cancel()
        raceAutoplayTask = nil
        isRaceAutoplayActive = false
        flushRaceAutoplayCallbacks()
        scheduleOpponentTurnIfNeeded()
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

        turnDraftSnapshots.append((state: state, layout: checkerLayout))
        do {
            let nextState = try engine.apply(action: .move(move), to: state)
            withAnimation(Self.checkerMoveAnimation) {
                state = nextState
                checkerLayout.apply(move)
                lastError = nil
                turnNotice = nil
                refreshDerivedState()
            }
        } catch {
            _ = turnDraftSnapshots.popLast()
            lastError = friendlyErrorMessage(error)
        }
    }

    private func scheduleAutomationIfNeeded() {
        scheduleRaceAutoplayIfNeeded()
        scheduleOpponentTurnIfNeeded()
    }

    private func scheduleRaceAutoplayIfNeeded() {
        guard raceAutoplayTask == nil else { return }
        guard isRaceAutoplayEligible(ignoresUserStopped: false) else { return }

        isLocalAutoplayRequested = false
        scheduleAutoplayTaskIfNeeded()
    }

    private func scheduleAutoplayTaskIfNeeded() {
        guard raceAutoplayTask == nil else { return }
        guard isAutoplayEligible() else { return }

        isOpponentThinking = false
        isRaceAutoplayActive = true
        raceAutoplayTask = Task { [weak self] in
            await self?.playRaceAutoplayUntilBlocked()
        }
    }

    private func isAutoplayEligible() -> Bool {
        isLocalAutoplayRequested
            ? isLocalAutoplayEligible()
            : isRaceAutoplayEligible(ignoresUserStopped: false)
    }

    private func isLocalAutoplayEligible() -> Bool {
        guard state.completion == nil else { return false }
        guard !isTurnDraftPending else { return false }

        switch state.game.phase {
        case .awaitingRoll(let player) where player == localPlayer:
            guard !legalActions.contains(.offerDouble(localPlayer)) else { return false }
            return legalActions.contains(.rollDice(localPlayer))
        case .awaitingMove(let turn) where turn.player == localPlayer:
            if legalActions.contains(where: { action in
                if case .move(let move) = action {
                    return move.player == localPlayer
                }
                return false
            }) {
                return true
            }
            return legalActions.contains(.passTurn(localPlayer))
        default:
            return false
        }
    }

    private func isRaceAutoplayEligible(ignoresUserStopped: Bool) -> Bool {
        if !ignoresUserStopped, isRaceAutoplayUserStopped {
            return false
        }
        guard state.completion == nil else { return false }
        guard state.game.board.isNoContactRace else { return false }
        guard !isTurnDraftPending else { return false }

        switch state.game.phase {
        case .awaitingRoll(let player):
            guard player == localPlayer || isOpponentAutoplayEnabled else { return false }
            if player == localPlayer, legalActions.contains(.offerDouble(localPlayer)) {
                return false
            }
            return legalActions.contains(.rollDice(player))
        case .awaitingMove(let turn):
            guard turn.player == localPlayer || isOpponentAutoplayEnabled else { return false }
            if legalActions.contains(where: { action in
                if case .move(let move) = action {
                    return move.player == turn.player
                }
                return false
            }) {
                return true
            }
            return legalActions.contains(.passTurn(turn.player))
        default:
            return false
        }
    }

    private func playRaceAutoplayUntilBlocked() async {
        isBatchingRaceAutoplayCallbacks = true

        while !Task.isCancelled {
            guard isAutoplayEligible() else { break }
            guard let action = autoplayAction() else { break }

            await raceAutoplayDelay()
            guard !Task.isCancelled else { break }
            guard isAutoplayEligible() else { break }

            apply(action, schedulesOpponent: false)
            if lastError != nil { break }
        }

        isBatchingRaceAutoplayCallbacks = false
        isRaceAutoplayActive = false
        isLocalAutoplayRequested = false
        raceAutoplayTask = nil
        flushRaceAutoplayCallbacks()

        if !Task.isCancelled {
            scheduleAutomationIfNeeded()
        }
    }

    private func autoplayAction() -> MatchAction? {
        isLocalAutoplayRequested ? localAutoplayAction() : raceAutoplayAction()
    }

    private func localAutoplayAction() -> MatchAction? {
        switch state.game.phase {
        case .awaitingRoll(let player) where player == localPlayer:
            guard !legalActions.contains(.offerDouble(localPlayer)) else { return nil }
            return legalActions.contains(.rollDice(localPlayer)) ? .rollDice(localPlayer) : nil
        case .awaitingMove(let turn) where turn.player == localPlayer:
            if let move = raceAutoplayMove(for: localPlayer) {
                return .move(move)
            }
            return legalActions.contains(.passTurn(localPlayer)) ? .passTurn(localPlayer) : nil
        default:
            return nil
        }
    }

    private func raceAutoplayAction() -> MatchAction? {
        switch state.game.phase {
        case .awaitingRoll(let player):
            guard player == localPlayer || isOpponentAutoplayEnabled else { return nil }
            guard !(player == localPlayer && legalActions.contains(.offerDouble(localPlayer))) else {
                return nil
            }
            return legalActions.contains(.rollDice(player)) ? .rollDice(player) : nil
        case .awaitingMove(let turn):
            guard turn.player == localPlayer || isOpponentAutoplayEnabled else { return nil }
            if let move = raceAutoplayMove(for: turn.player) {
                return .move(move)
            }
            return legalActions.contains(.passTurn(turn.player)) ? .passTurn(turn.player) : nil
        default:
            return nil
        }
    }

    private func raceAutoplayMove(for player: Player) -> Move? {
        raceAutoplayController.selectMove(
            for: player,
            in: state,
            legalActions: legalActions,
            pipCounts: pipCounts
        )
    }

    private func scheduleOpponentTurnIfNeeded() {
        guard raceAutoplayTask == nil else {
            isOpponentThinking = false
            return
        }
        guard !isRaceAutoplayEligible(ignoresUserStopped: false) else {
            isOpponentThinking = false
            return
        }
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
            if isRaceAutoplayEligible(ignoresUserStopped: false) {
                scheduleRaceAutoplayIfNeeded()
                break
            }
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

    private func queueOrNotifyStorageCallbacks(hadCompletion: Bool) {
        guard isBatchingRaceAutoplayCallbacks else {
            notifyStorageCallbacks(hadCompletion: hadCompletion)
            return
        }

        if !hadCompletion, state.completion != nil {
            raceAutoplayNeedsCompletion = true
        } else if state.completion == nil {
            raceAutoplayNeedsStateChange = true
        }
    }

    private func flushRaceAutoplayCallbacks() {
        let shouldNotifyCompletion = raceAutoplayNeedsCompletion && state.completion != nil
        let shouldNotifyStateChange = raceAutoplayNeedsStateChange && state.completion == nil
        raceAutoplayNeedsCompletion = false
        raceAutoplayNeedsStateChange = false

        if shouldNotifyCompletion {
            notifyCompletionIfNeeded()
        } else if shouldNotifyStateChange {
            onStateChange?(state)
        }
    }

    private func notifyStorageCallbacks(hadCompletion: Bool) {
        if !hadCompletion, state.completion != nil {
            notifyCompletionIfNeeded()
        } else if state.completion == nil {
            onStateChange?(state)
        }
    }

    private func notifyCompletionIfNeeded() {
        guard !didNotifyCompletion else { return }
        didNotifyCompletion = true
        onCompletion?(state)
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
    private static let hitBonus = 50
    private static let pointBonus = 15
    private static let innerPointBonus = 25
    private static let blotPenalty = 20
    private static let homeBlotPenalty = 10

    public let difficulty: AIDifficulty
    private let randomIndex: @Sendable (Int) -> Int

    public init(
        difficulty: AIDifficulty = .medium,
        randomIndex: @escaping @Sendable (Int) -> Int = { upperBound in
            Int.random(in: 0..<upperBound)
        }
    ) {
        self.difficulty = difficulty
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
            return selectMove(
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

    public func selectMove(
        for player: Player,
        in state: MatchState,
        legalActions: [MatchAction],
        pipCounts: [Player: Int]
    ) -> Move? {
        let moves = legalMoves(for: player, in: legalActions)
        guard !moves.isEmpty else { return nil }

        switch difficulty {
        case .easy:
            return moves[clampedRandomIndex(upperBound: moves.count)]
        case .medium:
            return selectPipBiasedMove(
                for: player,
                moves: moves,
                pipCounts: pipCounts
            )
        case .hard:
            return selectHeuristicMove(
                for: player,
                in: state,
                moves: moves,
                pipCounts: pipCounts
            )
        }
    }

    public func selectPipBiasedMove(
        for player: Player,
        in state: MatchState,
        legalActions: [MatchAction],
        pipCounts: [Player: Int]
    ) -> Move? {
        let moves = legalMoves(for: player, in: legalActions)
        guard !moves.isEmpty else { return nil }
        return selectPipBiasedMove(for: player, moves: moves, pipCounts: pipCounts)
    }

    private func selectPipBiasedMove(
        for player: Player,
        moves: [Move],
        pipCounts: [Player: Int]
    ) -> Move? {
        let currentPips = pipCounts[player, default: 0]
        let rankedMoves = moves.map { move in
            (move: move, projectedPips: projectedPipCount(currentPips, after: move))
        }
        guard let bestPips = rankedMoves.map(\.projectedPips).min() else { return nil }
        let bestMoves = rankedMoves.filter { $0.projectedPips == bestPips }.map(\.move)
        return bestMoves[clampedRandomIndex(upperBound: bestMoves.count)]
    }

    private func selectHeuristicMove(
        for player: Player,
        in state: MatchState,
        moves: [Move],
        pipCounts: [Player: Int]
    ) -> Move? {
        let currentPips = pipCounts[player, default: 0]
        let board = state.game.board
        let scored = moves.map { move -> (move: Move, score: Int) in
            let projected = projectedPipCount(currentPips, after: move)
            var score = currentPips - projected
            score += hitScore(for: move, on: board, player: player)
            score += pointMakingScore(for: move, on: board, player: player)
            score -= sourceBlotPenalty(for: move, on: board, player: player)
            score -= destinationBlotPenalty(for: move, on: board, player: player)
            return (move, score)
        }
        guard let bestScore = scored.map(\.score).max() else { return nil }
        let bestMoves = scored.filter { $0.score == bestScore }.map(\.move)
        return bestMoves[clampedRandomIndex(upperBound: bestMoves.count)]
    }

    private func legalMoves(for player: Player, in legalActions: [MatchAction]) -> [Move] {
        legalActions.compactMap { action -> Move? in
            if case .move(let move) = action, move.player == player {
                return move
            }
            return nil
        }
    }

    private func hitScore(for move: Move, on board: Board, player: Player) -> Int {
        guard case .point(let dest) = move.destination else { return 0 }
        let state = board.point(dest)
        return state.owner == player.opponent && state.count == 1 ? Self.hitBonus : 0
    }

    private func pointMakingScore(for move: Move, on board: Board, player: Player) -> Int {
        guard case .point(let dest) = move.destination else { return 0 }
        let state = board.point(dest)
        guard state.owner == player, state.count == 1 else { return 0 }
        return player.homeBoard.contains(dest.rawValue) ? Self.innerPointBonus : Self.pointBonus
    }

    private func sourceBlotPenalty(for move: Move, on board: Board, player: Player) -> Int {
        guard case .point(let src) = move.source else { return 0 }
        let state = board.point(src)
        guard state.owner == player, state.count == 2 else { return 0 }
        return player.homeBoard.contains(src.rawValue) ? Self.homeBlotPenalty : Self.blotPenalty
    }

    private func destinationBlotPenalty(for move: Move, on board: Board, player: Player) -> Int {
        guard case .point(let dest) = move.destination else { return 0 }
        let state = board.point(dest)
        let landingAlone: Bool
        if state.owner == nil {
            landingAlone = true
        } else if state.owner == player.opponent && state.count == 1 {
            landingAlone = true
        } else {
            landingAlone = false
        }
        guard landingAlone else { return 0 }
        return player.homeBoard.contains(dest.rawValue) ? Self.homeBlotPenalty : Self.blotPenalty
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
        if difficulty == .easy { return false }
        let pointsNeeded = state.config.targetScore - state.score.score(for: offer.offeredBy)
        guard offer.proposedValue >= pointsNeeded else { return false }

        let opponentPips = pipCounts[opponent, default: 0]
        let offeringPlayerPips = pipCounts[offer.offeredBy, default: 0]
        let dropThreshold = difficulty == .hard ? 40 : 50
        return opponentPips - offeringPlayerPips >= dropThreshold
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
