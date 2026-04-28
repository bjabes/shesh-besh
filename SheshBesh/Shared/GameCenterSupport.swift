#if canImport(GameKit) && canImport(UIKit)
@preconcurrency import GameKit
import Observation
import os
import SheshBeshGame
import SwiftUI
@preconcurrency import UIKit

#if canImport(SheshBeshLedger)
import SheshBeshLedger
#endif

private let gcLog = Logger(subsystem: "com.sheshbesh.gamecenter", category: "auth")

public enum GameCenterAuthState: Equatable, Sendable {
    case notStarted
    case authenticating
    case authenticated(displayName: String)
    case unauthenticated(String)

    public var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }
}

@MainActor
@Observable
public final class GameCenterSession: NSObject, @preconcurrency GKLocalPlayerListener {
    public private(set) var authState: GameCenterAuthState = .notStarted
    public private(set) var localPlayerID: String?
    public private(set) var localDisplayName: String?
    public var authenticationViewController: UIViewController?
    public var lastErrorMessage: String?
    private var authenticationAttemptID = UUID()
    private var attemptStart = Date()
    private var handlerCallCount = 0

    @ObservationIgnored public var onTurnEvent: (@MainActor (GKTurnBasedMatch, Bool) -> Void)?
    @ObservationIgnored public var onMatchEnded: (@MainActor (GKTurnBasedMatch) -> Void)?
    @ObservationIgnored public var onWantsToQuitMatch: (@MainActor (GKTurnBasedMatch) -> Void)?

    public func start() {
        trace("start() called — authState=\(self.authState), GK.isAuthenticated=\(GKLocalPlayer.local.isAuthenticated)")
        guard authState == .notStarted else {
            trace("start() skipped — not in .notStarted")
            return
        }
        beginAuthentication()
    }

    public func retry() {
        trace("retry() called — authState=\(self.authState), GK.isAuthenticated=\(GKLocalPlayer.local.isAuthenticated)")
        guard !authState.isAuthenticated, authState != .authenticating else {
            trace("retry() skipped — already authenticated or authenticating")
            return
        }
        beginAuthentication()
    }

    public var canOpenSystemSettings: Bool {
        if case .unauthenticated = authState { return true }
        return false
    }

    public func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func beginAuthentication() {
        let attemptID = UUID()
        authenticationAttemptID = attemptID
        attemptStart = Date()
        handlerCallCount = 0
        authState = .authenticating
        lastErrorMessage = nil

        #if targetEnvironment(simulator)
        let env = "simulator"
        #else
        let env = "device"
        #endif
        trace("beginAuthentication attempt=\(attemptID.uuidString.prefix(8)) env=\(env) bundle=\(Bundle.main.bundleIdentifier ?? "?")")

        scheduleAuthenticationTimeout(for: attemptID)
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                self.handlerCallCount += 1
                let elapsed = Date().timeIntervalSince(self.attemptStart)
                let nsErr = error as NSError?
                let elapsedStr = String(format: "%.2f", elapsed)
                let vcStr = viewController != nil ? "yes" : "nil"
                let errStr = nsErr.map { "\($0.domain):\($0.code)" } ?? "nil"
                self.trace("handler#\(self.handlerCallCount) t=\(elapsedStr)s vc=\(vcStr) err=\(errStr) isAuth=\(GKLocalPlayer.local.isAuthenticated)")

                if let viewController {
                    self.trace("→ presenting auth VC")
                    self.authenticationViewController = viewController
                    self.authState = .authenticating
                    return
                }

                if GKLocalPlayer.local.isAuthenticated {
                    self.trace("→ authenticated as \(GKLocalPlayer.local.displayName) id=\(GKLocalPlayer.local.gamePlayerID)")
                    self.authenticationViewController = nil
                    self.localPlayerID = GKLocalPlayer.local.gamePlayerID
                    self.localDisplayName = GKLocalPlayer.local.displayName
                    self.lastErrorMessage = nil
                    self.authState = .authenticated(displayName: GKLocalPlayer.local.displayName)
                    GKLocalPlayer.local.register(self)
                } else {
                    let message = self.authenticationFailureMessage(for: error)
                    self.trace("→ unauthenticated: \(message)")
                    self.authenticationViewController = nil
                    self.localPlayerID = nil
                    self.localDisplayName = nil
                    self.lastErrorMessage = message
                    self.authState = .unauthenticated(message)
                }
            }
        }
    }

    private func authenticationFailureMessage(for error: (any Error)?) -> String {
        guard let error else {
            return "Sign in to Game Center to play with friends."
        }

        let nsError = error as NSError
        let userInfoString = String(describing: nsError.userInfo)
        gcLog.error("auth failure raw error: domain=\(nsError.domain, privacy: .public) code=\(nsError.code) userInfo=\(userInfoString, privacy: .private)")

        guard nsError.domain == GKErrorDomain,
              let code = GKError.Code(rawValue: nsError.code)
        else {
            return error.localizedDescription
        }

        switch code {
        case .cancelled:
            return "Game Center sign-in was canceled or disabled. Sign in from Settings > Game Center, then try again."
        case .notAuthenticated:
            return "Game Center could not authenticate your account. Sign in from Settings > Game Center, then try again."
        default:
            return error.localizedDescription
        }
    }

    private func scheduleAuthenticationTimeout(for attemptID: UUID) {
        Task { [weak self, attemptID] in
            let pollCount = 8
            let pollInterval: Duration = .milliseconds(1500)
            for tick in 1...pollCount {
                try await Task.sleep(for: pollInterval)
                guard let self else { return }
                guard self.authenticationAttemptID == attemptID else {
                    self.trace("timeout poll bailed — attempt id changed (superseded)")
                    return
                }
                let isAuth = GKLocalPlayer.local.isAuthenticated
                let vcStr = self.authenticationViewController != nil ? "yes" : "nil"
                self.trace("poll \(tick)/\(pollCount) state=\(self.authState) vc=\(vcStr) isAuth=\(isAuth) handlers=\(self.handlerCallCount)")
                if self.authState != .authenticating || self.authenticationViewController != nil || isAuth {
                    self.trace("poll ended — state advanced")
                    return
                }
            }

            guard let self,
                  self.authenticationAttemptID == attemptID,
                  self.authState == .authenticating,
                  self.authenticationViewController == nil,
                  !GKLocalPlayer.local.isAuthenticated
            else { return }

            self.trace("timeout fired after \(pollCount) polls, handlers=\(self.handlerCallCount) — GameKit never responded")
            let message = "Game Center didn't respond. Make sure you're signed in to Game Center in Settings, then try again."
            self.lastErrorMessage = message
            self.authState = .unauthenticated(message)
        }
    }

    private func trace(_ message: String) {
        gcLog.debug("\(message, privacy: .public)")
    }

    public func loadMatches() async throws -> [GKTurnBasedMatch] {
        try await GKTurnBasedMatch.loadMatches()
    }

    public func player(
        _ player: GKPlayer,
        receivedTurnEventFor match: GKTurnBasedMatch,
        didBecomeActive: Bool
    ) {
        onTurnEvent?(match, didBecomeActive)
    }

    public func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        onMatchEnded?(match)
    }

    public func player(_ player: GKPlayer, wantsToQuitMatch match: GKTurnBasedMatch) {
        onWantsToQuitMatch?(match)
    }
}

public struct GameCenterAuthenticationSheet: UIViewControllerRepresentable {
    public let viewController: UIViewController

    public init(viewController: UIViewController) {
        self.viewController = viewController
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        viewController
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

public struct GameCenterLoadedMatch {
    public var match: GKTurnBasedMatch
    public var envelope: GameCenterMatchEnvelope
    public var activeMatch: ActiveMatch
    public var rival: Rival
    public var localPlayerID: String

    public var localPlayer: Player {
        envelope.playerMapping.player(forGameCenterID: localPlayerID) ?? .white
    }

    public var opponentPlayer: Player {
        localPlayer.opponent
    }

    public var opponentDisplayName: String {
        envelope.playerMapping.displayName(for: opponentPlayer)
    }

    public var isLocalTurn: Bool {
        match.currentParticipant?.player?.gamePlayerID == localPlayerID
    }
}

@MainActor
public final class GameCenterMatchCoordinator {
    private let ledgerCoordinator: LedgerCoordinator

    public init(ledgerCoordinator: LedgerCoordinator) {
        self.ledgerCoordinator = ledgerCoordinator
    }

    public func load(match: GKTurnBasedMatch, targetScore: Int = 7) async throws -> GameCenterLoadedMatch {
        let localPlayerID = GKLocalPlayer.local.gamePlayerID
        let data = try await match.loadMatchData()
        let envelope: GameCenterMatchEnvelope

        if let data, !data.isEmpty {
            do {
                envelope = try Self.resolvingParticipants(
                    in: GameCenterMatchEnvelope.decoded(from: data),
                    match: match
                )
            } catch let error as GameCenterEnvelopeError {
                throw error
            } catch {
                throw GameCenterEnvelopeError.corruptMatchData
            }
        } else {
            envelope = Self.newEnvelope(
                for: match,
                localPlayerID: localPlayerID,
                targetScore: targetScore
            )
            if match.currentParticipant?.player?.gamePlayerID == localPlayerID,
               !envelope.playerMapping.hasPendingGameCenterID(for: .white),
               !envelope.playerMapping.hasPendingGameCenterID(for: .black) {
                try await save(envelope: envelope, to: match)
            }
        }

        return try await reconcileLedger(for: match, envelope: envelope, localPlayerID: localPlayerID)
    }

    public func commit(state: MatchState, for loaded: GameCenterLoadedMatch) async throws -> GameCenterLoadedMatch {
        let match = try await GKTurnBasedMatch.load(withID: loaded.match.matchID)

        guard match.currentParticipant?.player?.gamePlayerID == loaded.localPlayerID else {
            throw GameCenterCoordinatorError.notLocalPlayersTurn
        }

        var envelope = loaded.envelope
        envelope.revision += 1
        envelope.gameIndex = max(0, state.gameNumber - 1)
        envelope.state = state
        envelope.config = state.config

        let data = try validatedData(for: envelope, maximumSize: match.matchDataMaximumSize)

        if state.completion != nil {
            try await endMatch(match, envelope: envelope, data: data)
        } else if let activePlayer = activePlayer(in: state),
                  activePlayer != loaded.localPlayer {
            envelope.turnCounter += 1
            let turnData = try validatedData(for: envelope, maximumSize: match.matchDataMaximumSize)
            let nextParticipant = try participant(for: activePlayer, in: match, envelope: envelope)
            match.setLocalizableMessageWithKey(
                "%@ played a turn in %@.",
                arguments: [GKLocalPlayer.local.displayName, AppBrand.name]
            )
            try await match.endTurn(
                withNextParticipants: [nextParticipant],
                turnTimeout: GKTurnTimeoutDefault,
                match: turnData
            )
        } else {
            try await match.saveCurrentTurn(withMatch: data)
        }

        let updated = try await reconcileLedger(
            for: match,
            envelope: envelope,
            localPlayerID: loaded.localPlayerID
        )

        if state.completion != nil {
            try await ledgerCoordinator.recordCompletion(of: updated.activeMatch)
        }

        return updated
    }

    public func sendReminder(for loaded: GameCenterLoadedMatch) async throws {
        let match = try await GKTurnBasedMatch.load(withID: loaded.match.matchID)
        let nextParticipant = try participant(for: loaded.opponentPlayer, in: match, envelope: loaded.envelope)
        try await match.sendReminder(
            to: [nextParticipant],
            localizableMessageKey: "Your move in %@.",
            arguments: [AppBrand.name]
        )
    }

    public func quit(loaded: GameCenterLoadedMatch) async throws {
        let match = try await GKTurnBasedMatch.load(withID: loaded.match.matchID)
        if match.currentParticipant?.player?.gamePlayerID == loaded.localPlayerID {
            let nextParticipants = match.participants.filter { $0 != match.currentParticipant }
            try await match.participantQuitInTurn(
                with: .quit,
                nextParticipants: nextParticipants,
                turnTimeout: GKTurnTimeoutDefault,
                match: match.matchData ?? Data()
            )
        } else {
            try await match.participantQuitOutOfTurn(with: .quit)
        }
    }

    public func remove(loaded: GameCenterLoadedMatch) async throws {
        try await quit(loaded: loaded)
        let match = try await GKTurnBasedMatch.load(withID: loaded.match.matchID)
        try await match.remove()
    }

    private func reconcileLedger(
        for match: GKTurnBasedMatch,
        envelope: GameCenterMatchEnvelope,
        localPlayerID: String
    ) async throws -> GameCenterLoadedMatch {
        let localPlayer = envelope.playerMapping.player(forGameCenterID: localPlayerID) ?? .white
        let opponent = localPlayer.opponent
        let opponentID = envelope.playerMapping.gameCenterID(for: opponent)
        let opponentName = envelope.playerMapping.displayName(for: opponent)
        let isOpponentResolved = !GameCenterPlayerMapping.isPendingGameCenterID(opponentID)
        let existingActive = isOpponentResolved
            ? ledgerCoordinator.activeMatch(gameCenterMatchID: match.matchID)
            : nil
        let rival = isOpponentResolved
            ? ledgerCoordinator.rival(matchingGameCenterPlayerID: opponentID) ?? Rival(
                displayName: opponentName,
                gameCenterPlayerID: opponentID,
                gameCenterDisplayName: opponentName
            )
            : Rival(
                displayName: opponentName,
                gameCenterPlayerID: opponentID,
                gameCenterDisplayName: opponentName
            )
        let activeMatch = ActiveMatch(
            id: existingActive?.id ?? UUID(),
            rivalID: rival.id,
            gameCenterMatchID: match.matchID,
            gameIndex: envelope.gameIndex,
            userPlayed: localPlayer,
            state: envelope.state,
            startedAt: existingActive?.startedAt ?? match.creationDate,
            lastUpdatedAt: Date()
        )

        if isOpponentResolved {
            try await ledgerCoordinator.saveGameCenterMatch(activeMatch, rival: rival)
        }

        return GameCenterLoadedMatch(
            match: match,
            envelope: envelope,
            activeMatch: activeMatch,
            rival: rival,
            localPlayerID: localPlayerID
        )
    }

    private func save(envelope: GameCenterMatchEnvelope, to match: GKTurnBasedMatch) async throws {
        let data = try validatedData(for: envelope, maximumSize: match.matchDataMaximumSize)
        try await match.saveCurrentTurn(withMatch: data)
    }

    private func endMatch(
        _ match: GKTurnBasedMatch,
        envelope: GameCenterMatchEnvelope,
        data: Data
    ) async throws {
        guard let completion = envelope.state.completion else { return }
        let winnerID = envelope.playerMapping.gameCenterID(for: completion.winner)

        for participant in match.participants {
            participant.matchOutcome = participant.player?.gamePlayerID == winnerID ? .won : .lost
        }

        try await match.endMatchInTurn(withMatch: data)
    }

    private func validatedData(for envelope: GameCenterMatchEnvelope, maximumSize: Int) throws -> Data {
        let data = try envelope.encoded()
        guard data.count <= maximumSize else {
            throw GameCenterEnvelopeError.matchDataTooLarge(data.count, maximum: maximumSize)
        }
        return data
    }

    private func activePlayer(in state: MatchState) -> Player? {
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

    private func participant(
        for player: Player,
        in match: GKTurnBasedMatch,
        envelope: GameCenterMatchEnvelope
    ) throws -> GKTurnBasedParticipant {
        let playerID = envelope.playerMapping.gameCenterID(for: player)
        guard let participant = match.participants.first(where: { $0.player?.gamePlayerID == playerID }) else {
            throw GameCenterCoordinatorError.missingParticipant
        }
        return participant
    }

    private static func newEnvelope(
        for match: GKTurnBasedMatch,
        localPlayerID: String,
        targetScore: Int
    ) -> GameCenterMatchEnvelope {
        let opponent = match.participants.first { participant in
            guard let playerID = participant.player?.gamePlayerID else { return false }
            return playerID != localPlayerID
        }
        let opponentID = opponent?.player?.gamePlayerID ?? "\(GameCenterPlayerMapping.pendingPlayerIDPrefix)\(match.matchID)"
        let opponentName = opponent?.player?.displayName ?? "Opponent"
        let config = MatchConfig.tournament(targetScore: targetScore)

        return GameCenterMatchEnvelope(
            gameCenterMatchID: match.matchID,
            playerMapping: GameCenterPlayerMapping(
                whitePlayerID: localPlayerID,
                blackPlayerID: opponentID,
                whiteDisplayName: GKLocalPlayer.local.displayName,
                blackDisplayName: opponentName
            ),
            config: config,
            state: MatchEngine.newMatch(config: config)
        )
    }

    private static func resolvingParticipants(
        in envelope: GameCenterMatchEnvelope,
        match: GKTurnBasedMatch
    ) -> GameCenterMatchEnvelope {
        var envelope = envelope
        let participants = match.participants.compactMap(\.player)

        if envelope.playerMapping.whitePlayerID.hasPrefix("pending-"),
           let white = participants.first(where: { $0.gamePlayerID != envelope.playerMapping.blackPlayerID }) {
            envelope.playerMapping.whitePlayerID = white.gamePlayerID
            envelope.playerMapping.whiteDisplayName = white.displayName
        }

        if envelope.playerMapping.blackPlayerID.hasPrefix("pending-"),
           let black = participants.first(where: { $0.gamePlayerID != envelope.playerMapping.whitePlayerID }) {
            envelope.playerMapping.blackPlayerID = black.gamePlayerID
            envelope.playerMapping.blackDisplayName = black.displayName
        }

        return envelope
    }
}

public enum GameCenterCoordinatorError: Error, LocalizedError, Sendable {
    case missingParticipant
    case notLocalPlayersTurn

    public var errorDescription: String? {
        switch self {
        case .missingParticipant:
            "Game Center has not resolved the opponent for this match yet."
        case .notLocalPlayersTurn:
            "This Game Center match is not currently your turn."
        }
    }
}

public struct GameCenterMatchmakerSheet: UIViewControllerRepresentable {
    public let targetScore: Int
    public let onMatchFound: @MainActor (GKTurnBasedMatch, Int) -> Void
    public let onCancel: @MainActor () -> Void
    public let onError: @MainActor (Error) -> Void

    public init(
        targetScore: Int,
        onMatchFound: @escaping @MainActor (GKTurnBasedMatch, Int) -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.targetScore = targetScore
        self.onMatchFound = onMatchFound
        self.onCancel = onCancel
        self.onError = onError
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIViewController(context: Context) -> GKTurnBasedMatchmakerViewController {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
        request.inviteMessage = "Play a \(targetScore)-point \(AppBrand.name) match."

        let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
        controller.turnBasedMatchmakerDelegate = context.coordinator
        controller.showExistingMatches = true
        return controller
    }

    public func updateUIViewController(_ uiViewController: GKTurnBasedMatchmakerViewController, context: Context) {}

    @MainActor
    public final class Coordinator: NSObject, @preconcurrency GKTurnBasedMatchmakerViewControllerDelegate {
        private let parent: GameCenterMatchmakerSheet

        init(parent: GameCenterMatchmakerSheet) {
            self.parent = parent
        }

        @MainActor
        public func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
            viewController.dismiss(animated: true)
            parent.onCancel()
        }

        @MainActor
        public func turnBasedMatchmakerViewController(
            _ viewController: GKTurnBasedMatchmakerViewController,
            didFailWithError error: any Error
        ) {
            viewController.dismiss(animated: true)
            parent.onError(error)
        }

        @MainActor
        public func turnBasedMatchmakerViewController(
            _ viewController: GKTurnBasedMatchmakerViewController,
            didFind match: GKTurnBasedMatch
        ) {
            viewController.dismiss(animated: true)
            parent.onMatchFound(match, parent.targetScore)
        }
    }
}

public struct GameCenterHomeView: View {
    public let session: GameCenterSession
    public let ledgerCoordinator: LedgerCoordinator
    public let matchCoordinator: GameCenterMatchCoordinator
    public let onOpenLocalMatch: (ActiveMatch) -> Void
    public let onOpenMatch: (GameCenterLoadedMatch) -> Void

    @State private var matches: [GameCenterLoadedMatch] = []
    @State private var isLoadingMatches = false
    @State private var isWorking = false
    @State private var isShowingRemoveAllConfirmation = false
    @State private var isShowingMatchmaker = false
    @State private var deletionRequest: RivalryDeletionRequest?
    @State private var selectedTargetScore = 7
    @State private var localError: String?

    public init(
        session: GameCenterSession,
        ledgerCoordinator: LedgerCoordinator,
        matchCoordinator: GameCenterMatchCoordinator,
        onOpenLocalMatch: @escaping (ActiveMatch) -> Void,
        onOpenMatch: @escaping (GameCenterLoadedMatch) -> Void
    ) {
        self.session = session
        self.ledgerCoordinator = ledgerCoordinator
        self.matchCoordinator = matchCoordinator
        self.onOpenLocalMatch = onOpenLocalMatch
        self.onOpenMatch = onOpenMatch
    }

    public var body: some View {
        ZStack {
            LedgerBackground()
                .ignoresSafeArea()

            List {
                header
                    .ledgerListRow(top: 18, bottom: 18)
                RivalryLaunchActions(
                    primaryTitle: "Practice vs AI",
                    primarySystemImage: "cpu",
                    secondaryTitle: "Invite Friend",
                    secondarySystemImage: "person.badge.plus",
                    onPrimary: startAIRivalry,
                    onSecondary: startGameCenterInvite
                )
                .ledgerListRow(bottom: activeMatches.count > 0 ? 18 : 14)

                if activeMatches.count > 0 {
                    RemoveAllMatchesButton(
                        activeMatchCount: activeMatches.count,
                        isDisabled: isWorking,
                        action: { isShowingRemoveAllConfirmation = true }
                    )
                    .ledgerListRow(bottom: 18)
                }

                if !session.authState.isAuthenticated {
                    authPanel
                        .ledgerListRow(bottom: 18)
                }

                if ledgerCoordinator.ledgers.isEmpty {
                    EmptyGameCenterLedgerView()
                        .ledgerListRow(bottom: 28)
                } else {
                    RivalryStack(
                        ledgers: ledgerCoordinator.ledgers,
                        onStart: startMatch,
                        onResume: resumeMatch,
                        onDelete: requestDelete
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .task {
            await refresh()
        }
        .onChange(of: session.authState) {
            Task { await refresh() }
        }
        .sheet(item: authenticationBinding) { controller in
            GameCenterAuthenticationSheet(viewController: controller.viewController)
        }
        .sheet(isPresented: $isShowingMatchmaker) {
            GameCenterMatchmakerSheet(
                targetScore: selectedTargetScore,
                onMatchFound: { match, targetScore in
                    Task { await loadAndOpen(match: match, targetScore: targetScore) }
                },
                onCancel: {},
                onError: { error in localError = error.localizedDescription }
            )
        }
        .alert("Remove All Matches?", isPresented: $isShowingRemoveAllConfirmation) {
            Button("Remove All Matches", role: .destructive) {
                removeAllActiveMatches()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removeAllConfirmationMessage)
        }
        .alert("Delete Rivalry?", isPresented: deletionConfirmationBinding) {
            if let request = deletionRequest {
                Button("Delete Rivalry", role: .destructive) {
                    deleteRival(request.ledger, deletingRecords: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let request = deletionRequest {
                Text(deleteConfirmationMessage(for: request.ledger))
            }
        }
        .alert(
            "Game Center Error",
            isPresented: Binding(
                get: { localError != nil || session.lastErrorMessage != nil || ledgerCoordinator.lastErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        localError = nil
                        session.lastErrorMessage = nil
                        ledgerCoordinator.clearError()
                    }
                }
            )
        ) {
            if session.canOpenSystemSettings && session.lastErrorMessage != nil {
                Button("Open Settings") {
                    session.openSystemSettings()
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(localError ?? session.lastErrorMessage ?? ledgerCoordinator.lastErrorMessage ?? "")
        }
    }

    private var activeMatches: [ActiveMatch] {
        ledgerCoordinator.ledgers.compactMap(\.activeMatch)
    }

    private var localActiveMatches: [ActiveMatch] {
        activeMatches.filter { $0.gameCenterMatchID == nil }
    }

    private var gameCenterActiveMatches: [ActiveMatch] {
        activeMatches.filter { $0.gameCenterMatchID != nil }
    }

    private var loadedMatchesByID: [String: GameCenterLoadedMatch] {
        Dictionary(matches.map { ($0.match.matchID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var removeAllConfirmationMessage: String {
        var parts: [String] = []
        if gameCenterActiveMatches.count > 0 {
            parts.append("forfeit \(matchPhrase(gameCenterActiveMatches.count)) in Game Center")
        }
        if localActiveMatches.count > 0 {
            parts.append("clear \(matchPhrase(localActiveMatches.count)) locally")
        }

        let action = parts.isEmpty ? "remove active matches" : parts.joined(separator: " and ")
        return "This will \(action). Completed rivalry history stays."
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding {
            deletionRequest != nil
        } set: { isPresented in
            if !isPresented {
                deletionRequest = nil
            }
        }
    }

    private func deleteConfirmationMessage(for ledger: RivalLedger) -> String {
        "This rivalry has \(ledger.totalMatches) completed \(ledger.totalMatches == 1 ? "match" : "matches"). Delete anyway?"
    }

    private var authenticationBinding: Binding<AuthenticationController?> {
        Binding {
            session.authenticationViewController.map(AuthenticationController.init(viewController:))
        } set: { value in
            if value == nil {
                session.authenticationViewController = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rivalries")
                .font(LedgerTheme.displayFont(size: 34, weight: .bold))
                .foregroundStyle(LedgerTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text("AI practice and Game Center matches")
                .font(LedgerTheme.uiFont(size: 14, weight: .semibold))
                .foregroundStyle(LedgerTheme.mutedInk)
                .textCase(.uppercase)
                .tracking(0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(authTitle)
                .font(LedgerTheme.displayFont(size: 24, weight: .bold))
                .foregroundStyle(LedgerTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            if !session.authState.isAuthenticated {
                Button {
                    session.retry()
                } label: {
                    ThemedButtonLabel(
                        title: authButtonTitle,
                        systemImage: "person.crop.circle.badge.checkmark",
                        foregroundStyle: .white
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(LedgerTheme.rust)
                .disabled(session.authState == .authenticating)
                .accessibilityIdentifier("game-center-sign-in")

                if session.canOpenSystemSettings {
                    Button {
                        session.openSystemSettings()
                    } label: {
                        ThemedButtonLabel(
                            title: "Open Settings",
                            systemImage: "gearshape",
                            foregroundStyle: LedgerTheme.coffee
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("game-center-open-settings")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LedgerTheme.cream, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(LedgerTheme.brass.opacity(0.72), lineWidth: 1)
        )
    }

    private var authTitle: String {
        switch session.authState {
        case .notStarted:
            "Sign in to Game Center"
        case .authenticating:
            "Connecting to Game Center"
        case .authenticated(let displayName):
            "Signed in as \(displayName)"
        case .unauthenticated:
            "Sign in to Game Center"
        }
    }

    private var authButtonTitle: String {
        session.authState == .authenticating ? "Connecting" : "Sign in"
    }

    private func refresh() async {
        await ledgerCoordinator.refresh()
        guard session.authState.isAuthenticated else { return }
        isLoadingMatches = true
        defer { isLoadingMatches = false }

        do {
            let gameCenterMatches = try await session.loadMatches()
            var loaded: [GameCenterLoadedMatch] = []
            for match in gameCenterMatches {
                loaded.append(try await matchCoordinator.load(match: match, targetScore: selectedTargetScore))
            }
            matches = loaded.sorted { lhs, rhs in
                if lhs.isLocalTurn != rhs.isLocalTurn {
                    return lhs.isLocalTurn
                }
                return lhs.match.creationDate > rhs.match.creationDate
            }
        } catch {
            localError = error.localizedDescription
        }
    }

    private func startAIRivalry(difficulty: AIDifficulty) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                onOpenLocalMatch(try await ledgerCoordinator.startAIRivalry(difficulty: difficulty))
            } catch {
                localError = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func removeAllActiveMatches() {
        guard !isWorking else { return }

        let localMatchesToClear = localActiveMatches
        let gameCenterMatchesToRemove = gameCenterActiveMatches
        guard !localMatchesToClear.isEmpty || !gameCenterMatchesToRemove.isEmpty else { return }

        isWorking = true
        Task {
            defer { isWorking = false }

            var failureMessages: [String] = []

            do {
                if !localMatchesToClear.isEmpty {
                    try await ledgerCoordinator.clearActiveMatches(localMatchesToClear)
                }
            } catch {
                failureMessages.append("Local matches could not be cleared: \(error.localizedDescription)")
            }

            guard !gameCenterMatchesToRemove.isEmpty else {
                localError = failureMessages.first
                return
            }

            await refresh()
            let loadedByID = loadedMatchesByID
            var failedGameCenterCount = 0
            var successfullyRemoved: [ActiveMatch] = []

            for activeMatch in gameCenterMatchesToRemove {
                guard let gameCenterMatchID = activeMatch.gameCenterMatchID,
                      let loaded = loadedByID[gameCenterMatchID] else {
                    failedGameCenterCount += 1
                    continue
                }

                do {
                    try await matchCoordinator.remove(loaded: loaded)
                    successfullyRemoved.append(activeMatch)
                } catch {
                    failedGameCenterCount += 1
                }
            }

            if !successfullyRemoved.isEmpty {
                do {
                    try await ledgerCoordinator.clearActiveMatches(successfullyRemoved)
                } catch {
                    failureMessages.append(
                        "\(successfullyRemoved.count) forfeited Game Center \(successfullyRemoved.count == 1 ? "match" : "matches") could not be cleared locally: \(error.localizedDescription)"
                    )
                }
            }

            await refresh()

            if failedGameCenterCount > 0 {
                failureMessages.append("\(failedGameCenterCount) Game Center \(failedGameCenterCount == 1 ? "match" : "matches") could not be forfeited. Those matches were left active.")
            }

            localError = failureMessages.isEmpty ? nil : failureMessages.joined(separator: "\n")
        }
    }

    private func requestDelete(_ ledger: RivalLedger) {
        guard !isWorking else { return }
        if ledger.totalMatches > 0 {
            deletionRequest = RivalryDeletionRequest(ledger: ledger)
        } else {
            deleteRival(ledger, deletingRecords: false)
        }
    }

    private func deleteRival(_ ledger: RivalLedger, deletingRecords: Bool) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }

            do {
                if let gameCenterMatchID = ledger.activeMatch?.gameCenterMatchID {
                    await refresh()
                    if let loaded = loadedMatchesByID[gameCenterMatchID] {
                        try await matchCoordinator.remove(loaded: loaded)
                    }
                }

                try await ledgerCoordinator.deleteRival(ledger.rival, deletingRecords: deletingRecords)
                await refresh()
                localError = nil
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func startGameCenterInvite() {
        guard session.authState.isAuthenticated else {
            session.retry()
            return
        }
        isShowingMatchmaker = true
    }

    private func startMatch(for ledger: RivalLedger) {
        if ledger.rival.gameCenterPlayerID != nil {
            startGameCenterInvite()
        } else {
            startLocalMatch(for: ledger)
        }
    }

    private func startLocalMatch(for ledger: RivalLedger) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                let match = try await ledgerCoordinator.startMatch(
                    against: ledger.rival,
                    userPlays: ledger.totalMatches.isMultiple(of: 2) ? .white : .black,
                    config: .tournament(targetScore: 7)
                )
                onOpenLocalMatch(match)
            } catch {
                localError = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func resumeMatch(_ match: ActiveMatch) {
        guard let gameCenterMatchID = match.gameCenterMatchID else {
            onOpenLocalMatch(match)
            return
        }

        if let loaded = matches.first(where: { $0.match.matchID == gameCenterMatchID }) {
            onOpenMatch(loaded)
            return
        }

        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            await refresh()
            if let loaded = matches.first(where: { $0.match.matchID == gameCenterMatchID }) {
                onOpenMatch(loaded)
            } else {
                localError = "This Game Center match is not available right now."
            }
        }
    }

    private func loadAndOpen(match: GKTurnBasedMatch, targetScore: Int) async {
        do {
            let loaded = try await matchCoordinator.load(match: match, targetScore: targetScore)
            onOpenMatch(loaded)
        } catch {
            localError = error.localizedDescription
        }
    }

    private func matchPhrase(_ count: Int) -> String {
        "\(count) active \(count == 1 ? "match" : "matches")"
    }
}

private struct EmptyGameCenterLedgerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start a rivalry")
                .font(LedgerTheme.displayFont(size: 26, weight: .bold))
                .foregroundStyle(LedgerTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text("Practice against AI now, or invite a friend through Game Center.")
                .font(LedgerTheme.uiFont(size: 15))
                .foregroundStyle(LedgerTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LedgerTheme.cream, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(LedgerTheme.brass.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct AuthenticationController: Identifiable {
    let viewController: UIViewController
    var id: ObjectIdentifier { ObjectIdentifier(viewController) }
}
#endif
