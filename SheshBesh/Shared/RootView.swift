import Foundation
import SwiftUI

#if canImport(SheshBeshLedger)
import SheshBeshLedger
#endif

public struct RootView: View {
    @State private var singleMatchViewModel: MatchViewModel?
    @State private var coordinator: LedgerCoordinator
    @State private var activeMatchViewModel: MatchViewModel?
    @State private var completedRecord: MatchRecord?
    @State private var routeError: String?

    public init() {
        _singleMatchViewModel = State(initialValue: nil)
        _coordinator = State(initialValue: LedgerCoordinator(store: InMemoryLedgerStore()))
    }

    public init(coordinator: LedgerCoordinator) {
        _singleMatchViewModel = State(initialValue: nil)
        _coordinator = State(initialValue: coordinator)
    }

    public init(viewModel: MatchViewModel) {
        _singleMatchViewModel = State(initialValue: viewModel)
        _coordinator = State(initialValue: LedgerCoordinator(store: InMemoryLedgerStore()))
    }

    public var body: some View {
        Group {
            if let singleMatchViewModel {
                matchView(for: singleMatchViewModel)
            } else if let activeMatchViewModel {
                matchView(for: activeMatchViewModel) {
                    self.activeMatchViewModel = nil
                }
                    .sheet(item: $completedRecord) { record in
                        MatchEndSheet(
                            record: record,
                            ledger: coordinator.ledger(for: record.rivalID),
                            onDismiss: {
                                completedRecord = nil
                                self.activeMatchViewModel = nil
                            }
                        )
                    }
            } else {
                HomeView(coordinator: coordinator, onOpenMatch: openMatch)
            }
        }
        .alert(
            "Ledger Error",
            isPresented: Binding(
                get: { routeError != nil },
                set: { isPresented in
                    if !isPresented {
                        routeError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(routeError ?? "")
        }
    }

    @ViewBuilder
    private func matchView(
        for viewModel: MatchViewModel,
        onBackToRivals: (() -> Void)? = nil
    ) -> some View {
        if viewModel.doubleOfferForLocalPlayer != nil {
            DoubleOfferSheet(viewModel: viewModel, onBackToRivals: onBackToRivals)
        } else if viewModel.isOpponentTurn {
            OpponentTurnView(viewModel: viewModel, onBackToRivals: onBackToRivals)
        } else {
            BoardView(viewModel: viewModel, onBackToRivals: onBackToRivals)
        }
    }

    private func openMatch(_ match: ActiveMatch) {
        let rival = coordinator.rival(for: match.rivalID)
        let viewModel = MatchViewModel(
            config: match.state.config,
            localPlayer: match.userPlayed,
            opponentName: rival?.displayName ?? "Rival",
            activeMatchID: match.id,
            initialState: match.state
        )

        viewModel.onStateChange = { [coordinator] state in
            let updated = ActiveMatch(
                id: match.id,
                rivalID: match.rivalID,
                userPlayed: match.userPlayed,
                state: state,
                startedAt: match.startedAt,
                lastUpdatedAt: Date()
            )
            Task {
                do {
                    try await coordinator.saveActiveMatch(updated)
                } catch {
                    routeError = error.localizedDescription
                }
            }
        }

        viewModel.onCompletion = { [coordinator] state in
            let completed = ActiveMatch(
                id: match.id,
                rivalID: match.rivalID,
                userPlayed: match.userPlayed,
                state: state,
                startedAt: match.startedAt,
                lastUpdatedAt: Date()
            )
            Task {
                do {
                    try await coordinator.recordCompletion(of: completed)
                    completedRecord = coordinator.latestCompletedRecord
                } catch {
                    routeError = error.localizedDescription
                }
            }
        }

        activeMatchViewModel = viewModel
    }
}
