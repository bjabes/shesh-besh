#if canImport(GameKit) && canImport(UIKit)
@preconcurrency import GameKit
import Observation
import SheshBeshGame
import SwiftUI
@preconcurrency import UIKit

#if canImport(SheshBeshLedger)
import SheshBeshLedger
#endif

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
public final class GameCenterSession: NSObject, GKLocalPlayerListener {
    public private(set) var authState: GameCenterAuthState = .notStarted
    public private(set) var localPlayerID: String?
    public private(set) var localDisplayName: String?
    public var authenticationViewController: UIViewController?
    public var lastErrorMessage: String?
    private var authenticationAttemptID = UUID()

    @ObservationIgnored public var onTurnEvent: (@MainActor (GKTurnBasedMatch, Bool) -> Void)?
    @ObservationIgnored public var onMatchEnded: (@MainActor (GKTurnBasedMatch) -> Void)?

    public func authenticate() {
        let attemptID = UUID()
        authenticationAttemptID = attemptID
        authState = .authenticating
        lastErrorMessage = nil
        scheduleAuthenticationTimeout(for: attemptID)
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }

                if let viewController {
                    self.authenticationViewController = viewController
                    self.authState = .authenticating
                    return
                }

                if GKLocalPlayer.local.isAuthenticated {
                    self.authenticationViewController = nil
                    self.localPlayerID = GKLocalPlayer.local.gamePlayerID
                    self.localDisplayName = GKLocalPlayer.local.displayName
                    self.lastErrorMessage = nil
                    self.authState = .authenticated(displayName: GKLocalPlayer.local.displayName)
                    GKLocalPlayer.local.register(self)
                } else {
                    let message = self.authenticationFailureMessage(for: error)
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
            try? await Task.sleep(for: .seconds(12))

            guard let self,
                  self.authenticationAttemptID == attemptID,
                  self.authState == .authenticating,
                  self.authenticationViewController == nil,
                  !GKLocalPlayer.local.isAuthenticated
            else { return }

            let message = "Game Center did not respond. Try again or sign in from Settings."
            self.lastErrorMessage = message
            self.authState = .unauthenticated(message)
        }
    }

    public func loadMatches() async throws -> [GameCenterTurnBasedMatchBox] {
        try await withCheckedThrowingContinuation { continuation in
            GKTurnBasedMatch.loadMatches { matches, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (matches ?? []).map(GameCenterTurnBasedMatchBox.init(match:)))
                }
            }
        }
    }

    nonisolated public func player(
        _ player: GKPlayer,
        receivedTurnEventFor match: GKTurnBasedMatch,
        didBecomeActive: Bool
    ) {
        let matchBox = GameCenterTurnBasedMatchBox(match: match)
        DispatchQueue.main.async { [weak self] in
            self?.onTurnEvent?(matchBox.match, didBecomeActive)
        }
    }

    nonisolated public func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        let matchBox = GameCenterTurnBasedMatchBox(match: match)
        DispatchQueue.main.async { [weak self] in
            self?.onMatchEnded?(matchBox.match)
        }
    }
}

public final class GameCenterTurnBasedMatchBox: @unchecked Sendable, Identifiable {
    public let id: String
    public let match: GKTurnBasedMatch

    public init(match: GKTurnBasedMatch) {
        self.id = match.matchID
        self.match = match
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
        let data = try await match.loadGameData()
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
            if match.currentParticipant?.player?.gamePlayerID == localPlayerID {
                try await save(envelope: envelope, to: match)
            }
        }

        return try await reconcileLedger(for: match, envelope: envelope, localPlayerID: localPlayerID)
    }

    public func commit(state: MatchState, for loaded: GameCenterLoadedMatch) async throws -> GameCenterLoadedMatch {
        guard loaded.match.currentParticipant?.player?.gamePlayerID == loaded.localPlayerID else {
            throw GameCenterCoordinatorError.notLocalPlayersTurn
        }

        var envelope = loaded.envelope
        envelope.revision += 1
        envelope.gameIndex = max(0, state.gameNumber - 1)
        envelope.state = state
        envelope.config = state.config

        let data = try validatedData(for: envelope, maximumSize: loaded.match.matchDataMaximumSize)

        if state.completion != nil {
            try await endMatch(loaded.match, envelope: envelope, data: data)
        } else if let activePlayer = activePlayer(in: state),
                  activePlayer != loaded.localPlayer {
            envelope.turnCounter += 1
            let turnData = try validatedData(for: envelope, maximumSize: loaded.match.matchDataMaximumSize)
            let nextParticipant = try participant(for: activePlayer, in: loaded.match, envelope: envelope)
            try await loaded.match.endTurn(to: nextParticipant, data: turnData)
        } else {
            try await loaded.match.saveCurrentTurnData(data)
        }

        let updated = try await reconcileLedger(
            for: loaded.match,
            envelope: envelope,
            localPlayerID: loaded.localPlayerID
        )

        if state.completion != nil {
            try await ledgerCoordinator.recordCompletion(of: updated.activeMatch)
        }

        return updated
    }

    public func sendReminder(for loaded: GameCenterLoadedMatch) async throws {
        let nextParticipant = try participant(for: loaded.opponentPlayer, in: loaded.match, envelope: loaded.envelope)
        try await loaded.match.sendGameCenterReminder(to: nextParticipant)
    }

    private func reconcileLedger(
        for match: GKTurnBasedMatch,
        envelope: GameCenterMatchEnvelope,
        localPlayerID: String
    ) async throws -> GameCenterLoadedMatch {
        await ledgerCoordinator.refresh()

        let localPlayer = envelope.playerMapping.player(forGameCenterID: localPlayerID) ?? .white
        let opponent = localPlayer.opponent
        let opponentID = envelope.playerMapping.gameCenterID(for: opponent)
        let opponentName = envelope.playerMapping.displayName(for: opponent)

        let rival = ledgerCoordinator.rival(matchingGameCenterPlayerID: opponentID)
            ?? Rival(
                displayName: opponentName,
                gameCenterPlayerID: opponentID,
                gameCenterDisplayName: opponentName
            )
        let existingActive = ledgerCoordinator.activeMatch(gameCenterMatchID: match.matchID)
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

        try await ledgerCoordinator.saveGameCenterMatch(activeMatch, rival: rival)

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
        try await match.saveCurrentTurnData(data)
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

        try await match.endMatch(data: data)
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
        let opponentID = opponent?.player?.gamePlayerID ?? "pending-\(match.matchID)"
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
        request.inviteMessage = "Play a \(targetScore)-point Shesh Besh match."

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
    @State private var isShowingMatchmaker = false
    @State private var isSelectingTargetScore = false
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

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    RivalryLaunchActions(
                        primaryTitle: "Practice vs AI",
                        primarySystemImage: "cpu",
                        secondaryTitle: "Invite Friend",
                        secondarySystemImage: "person.badge.plus",
                        onPrimary: startAIRivalry,
                        onSecondary: startGameCenterInvite
                    )

                    if !session.authState.isAuthenticated {
                        authPanel
                    }

                    if ledgerCoordinator.ledgers.isEmpty {
                        EmptyGameCenterLedgerView()
                    } else {
                        RivalryStack(
                            ledgers: ledgerCoordinator.ledgers,
                            onStart: startMatch,
                            onResume: resumeMatch,
                            startTitle: startTitle,
                            startSystemImage: startSystemImage
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
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
        .confirmationDialog("Match length", isPresented: $isSelectingTargetScore) {
            Button("7 points") {
                selectedTargetScore = 7
                isShowingMatchmaker = true
            }
            Button("11 points") {
                selectedTargetScore = 11
                isShowingMatchmaker = true
            }
            Button("Cancel", role: .cancel) {}
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
            Button("OK", role: .cancel) {}
        } message: {
            Text(localError ?? session.lastErrorMessage ?? ledgerCoordinator.lastErrorMessage ?? "")
        }
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
                    session.authenticate()
                } label: {
                    Label(authButtonTitle, systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(LedgerTheme.rust)
                .disabled(session.authState == .authenticating)
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
            let matchBoxes = try await session.loadMatches()
            var gameCenterMatches: [GKTurnBasedMatch] = []
            for box in matchBoxes {
                let match = box.match
                let status = match.status
                if status == .open || status == .matching || status == .ended {
                    gameCenterMatches.append(match)
                }
            }
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

    private func startAIRivalry() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                let rival: Rival
                if let existingRival = ledgerCoordinator.ledgers
                    .map(\.rival)
                    .first(where: { $0.gameCenterPlayerID == nil && $0.displayName == "Random Dan" }) {
                    rival = existingRival
                } else {
                    rival = try await ledgerCoordinator.addRival(displayName: "Random Dan")
                }
                let match: ActiveMatch
                if let activeMatch = ledgerCoordinator.ledger(for: rival.id)?.activeMatch {
                    match = activeMatch
                } else {
                    match = try await ledgerCoordinator.startMatch(
                        against: rival,
                        userPlays: .white,
                        config: .tournament(targetScore: 1)
                    )
                }
                onOpenLocalMatch(match)
            } catch {
                localError = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func startGameCenterInvite() {
        guard session.authState.isAuthenticated else {
            session.authenticate()
            return
        }
        isSelectingTargetScore = true
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

        Task {
            await refresh()
            if let loaded = matches.first(where: { $0.match.matchID == gameCenterMatchID }) {
                onOpenMatch(loaded)
            } else {
                localError = "This Game Center match is not available right now."
            }
        }
    }

    private func startTitle(for ledger: RivalLedger) -> String {
        ledger.rival.gameCenterPlayerID == nil ? "Start match" : "Invite again"
    }

    private func startSystemImage(for ledger: RivalLedger) -> String {
        ledger.rival.gameCenterPlayerID == nil ? "play.fill" : "person.badge.plus"
    }

    private func loadAndOpen(match: GKTurnBasedMatch, targetScore: Int) async {
        do {
            let loaded = try await matchCoordinator.load(match: match, targetScore: targetScore)
            onOpenMatch(loaded)
        } catch {
            localError = error.localizedDescription
        }
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

            Text("Practice against Random Dan now, or invite a friend through Game Center.")
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
    let id = UUID()
    let viewController: UIViewController
}

@MainActor
private extension GKTurnBasedMatch {
    func loadGameData() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            loadMatchData { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    func saveCurrentTurnData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            saveCurrentTurn(withMatch: data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func endTurn(to participant: GKTurnBasedParticipant, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            endTurn(
                withNextParticipants: [participant],
                turnTimeout: GKTurnTimeoutDefault,
                match: data
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func endMatch(data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            endMatchInTurn(withMatch: data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private extension GKTurnBasedMatch {
    @MainActor
    func sendGameCenterReminder(to participant: GKTurnBasedParticipant) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sendReminder(
                to: [participant],
                localizableMessageKey: "Your move in Shesh Besh.",
                arguments: []
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#endif
