import Foundation
import Observation
import SheshBeshGame

#if canImport(SheshBeshLedger)
import SheshBeshLedger
#endif

@MainActor
@Observable
public final class LedgerCoordinator {
    @ObservationIgnored private let store: any LedgerStore

    public private(set) var ledgers: [RivalLedger] = []
    public private(set) var lastErrorMessage: String?
    public private(set) var latestCompletedRecord: MatchRecord?

    public init(store: any LedgerStore) {
        self.store = store
    }

    public func refresh() async {
        do {
            let snapshot = try await store.loadAllLedgerData()
            ledgers = snapshot.rivals
                .map { rival in
                    makeLedger(
                        rival: rival,
                        records: snapshot.recordsByRival[rival.id, default: []],
                        activeMatch: snapshot.activeMatchesByRival[rival.id]
                    )
                }
                .sorted(by: Self.sortLedgers)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func startMatch(
        against rival: Rival,
        userPlays: Player,
        config: MatchConfig
    ) async throws -> ActiveMatch {
        let now = Date()
        let match = ActiveMatch(
            rivalID: rival.id,
            userPlayed: userPlays,
            state: MatchEngine.newMatch(config: config),
            startedAt: now,
            lastUpdatedAt: now
        )

        try await store.upsertRival(rival)
        try await store.saveActiveMatch(match)
        await refresh()
        return match
    }

    public func saveActiveMatch(_ match: ActiveMatch) async throws {
        var updated = match
        updated.lastUpdatedAt = Date()
        try await store.saveActiveMatch(updated)
        await refresh()
    }

    public func recordCompletion(of match: ActiveMatch) async throws {
        guard let completion = match.state.completion else {
            throw LedgerStoreError.missingMatchCompletion
        }

        let rivalPlayer = match.userPlayed.opponent
        let record = MatchRecord(
            rivalID: match.rivalID,
            userPlayed: match.userPlayed,
            winner: completion.winner == match.userPlayed ? .you : .rival,
            userScore: completion.finalScore.score(for: match.userPlayed),
            rivalScore: completion.finalScore.score(for: rivalPlayer),
            targetScore: match.state.config.targetScore,
            startedAt: match.startedAt,
            completedAt: Date(),
            finalSnapshot: match.state
        )

        try await store.appendMatchRecord(record)
        try await store.clearActiveMatch(rivalID: match.rivalID)
        latestCompletedRecord = record
        await refresh()
    }

    public func addRival(displayName: String) async throws -> Rival {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rival = Rival(displayName: trimmedName.isEmpty ? "Rival" : trimmedName)
        try await store.upsertRival(rival)
        await refresh()
        return rival
    }

    public func ledger(for rivalID: Rival.ID) -> RivalLedger? {
        ledgers.first { $0.rival.id == rivalID }
    }

    public func rival(for rivalID: Rival.ID) -> Rival? {
        ledger(for: rivalID)?.rival
    }

    public func clearError() {
        lastErrorMessage = nil
    }

    private static func sortLedgers(_ lhs: RivalLedger, _ rhs: RivalLedger) -> Bool {
        let lhsDate = lhs.lastPlayedAt ?? lhs.activeMatch?.lastUpdatedAt ?? lhs.rival.createdAt
        let rhsDate = rhs.lastPlayedAt ?? rhs.activeMatch?.lastUpdatedAt ?? rhs.rival.createdAt
        if lhsDate == rhsDate {
            return lhs.rival.displayName.localizedCaseInsensitiveCompare(rhs.rival.displayName) == .orderedAscending
        }
        return lhsDate > rhsDate
    }
}
