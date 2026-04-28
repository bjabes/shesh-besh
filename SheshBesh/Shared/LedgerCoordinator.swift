import Foundation
import Observation
import SheshBeshGame

#if canImport(SheshBeshLedger)
import SheshBeshLedger
#endif

@MainActor
@Observable
public final class LedgerCoordinator {
    private static let standardAIMatchConfig = MatchConfig.tournament(targetScore: 7)

    @ObservationIgnored private let store: any LedgerStore

    public private(set) var ledgers: [RivalLedger] = []
    public private(set) var lastErrorMessage: String?
    public private(set) var latestCompletedRecord: MatchRecord?

    public init(store: any LedgerStore) {
        self.store = store
    }

    public func refresh() async {
        do {
            let snapshot = try await reconciledSnapshot()
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
        config: MatchConfig,
        gameCenterMatchID: String? = nil,
        gameIndex: Int = 0,
        initialState: MatchState? = nil
    ) async throws -> ActiveMatch {
        let now = Date()
        let match = ActiveMatch(
            rivalID: rival.id,
            gameCenterMatchID: gameCenterMatchID,
            gameIndex: gameIndex,
            userPlayed: userPlays,
            state: initialState ?? MatchEngine.newMatch(config: config),
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

    public func clearActiveMatches(_ matches: [ActiveMatch]) async throws {
        for match in matches {
            try await store.clearActiveMatch(rivalID: match.rivalID)
        }
        await refresh()
    }

    public func deleteRival(_ rival: Rival, deletingRecords: Bool = false) async throws {
        let records = try await store.loadMatchRecords(rivalID: rival.id)
        guard deletingRecords || records.isEmpty else {
            throw LedgerStoreError.rivalHasHistory
        }

        if try await store.loadActiveMatch(rivalID: rival.id) != nil {
            try await store.clearActiveMatch(rivalID: rival.id)
        }
        if deletingRecords {
            try await store.deleteMatchRecords(rivalID: rival.id)
        }
        try await store.deleteRival(id: rival.id)
        await refresh()
    }

    public func recordCompletion(of match: ActiveMatch) async throws {
        let record = try makeRecord(from: match, completedAt: Date())
        try await store.saveActiveMatch(match)
        try await appendRecordIfNeeded(record, for: match)
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

    public func startAIRivalry(difficulty: AIDifficulty) async throws -> ActiveMatch {
        await refresh()

        let rival: Rival
        if let existingRival = ledgers
            .map(\.rival)
            .first(where: { Self.isStandardAIRival($0, difficulty: difficulty) }) {
            rival = existingRival
        } else {
            rival = Rival(displayName: difficulty.rivalDisplayName)
            try await store.upsertRival(rival)
            await refresh()
        }

        if let activeMatch = ledger(for: rival.id)?.activeMatch {
            return activeMatch
        }

        return try await startMatch(
            against: rival,
            userPlays: .white,
            config: Self.standardAIMatchConfig
        )
    }

    public func ledger(for rivalID: Rival.ID) -> RivalLedger? {
        ledgers.first { $0.rival.id == rivalID }
    }

    #if DEBUG
    /// Synchronously seeds the cached ledgers. Used by UI test scenes to
    /// surface views (like the match-end sheet) that read ledger data before
    /// any async `refresh()` would normally complete.
    public func seedLedgersForUITests(_ ledgers: [RivalLedger]) {
        self.ledgers = ledgers
    }
    #endif

    public func rival(for rivalID: Rival.ID) -> Rival? {
        ledger(for: rivalID)?.rival
    }

    public func rival(matchingGameCenterPlayerID playerID: String) -> Rival? {
        ledgers
            .map(\.rival)
            .first { $0.gameCenterPlayerID == playerID }
    }

    public func activeMatch(gameCenterMatchID: String) -> ActiveMatch? {
        ledgers
            .compactMap(\.activeMatch)
            .first { $0.gameCenterMatchID == gameCenterMatchID }
    }

    public func saveGameCenterMatch(_ match: ActiveMatch, rival: Rival) async throws {
        try await store.upsertRival(rival)
        try await saveActiveMatch(match)
    }

    public func clearError() {
        lastErrorMessage = nil
    }

    private static func isStandardAIRival(_ rival: Rival, difficulty: AIDifficulty) -> Bool {
        rival.gameCenterPlayerID == nil && rival.displayName == difficulty.rivalDisplayName
    }

    private static func sortLedgers(_ lhs: RivalLedger, _ rhs: RivalLedger) -> Bool {
        let lhsDate = lhs.lastPlayedAt ?? lhs.activeMatch?.lastUpdatedAt ?? lhs.rival.createdAt
        let rhsDate = rhs.lastPlayedAt ?? rhs.activeMatch?.lastUpdatedAt ?? rhs.rival.createdAt
        if lhsDate == rhsDate {
            return lhs.rival.displayName.localizedCaseInsensitiveCompare(rhs.rival.displayName) == .orderedAscending
        }
        return lhsDate > rhsDate
    }

    private func reconciledSnapshot() async throws -> LedgerSnapshot {
        let snapshot = try await store.loadAllLedgerData()
        let completedMatches = snapshot.activeMatchesByRival.values.filter { $0.state.completion != nil }
        guard !completedMatches.isEmpty else { return snapshot }

        for match in completedMatches {
            let record = try makeRecord(from: match, completedAt: match.lastUpdatedAt)
            try await appendRecordIfNeeded(record, for: match, existingRecords: snapshot.recordsByRival[match.rivalID, default: []])
            try await store.clearActiveMatch(rivalID: match.rivalID)
        }

        return try await store.loadAllLedgerData()
    }

    private func makeRecord(from match: ActiveMatch, completedAt: Date) throws -> MatchRecord {
        guard let completion = match.state.completion else {
            throw LedgerStoreError.missingMatchCompletion
        }

        let rivalPlayer = match.userPlayed.opponent
        return MatchRecord(
            rivalID: match.rivalID,
            gameCenterMatchID: match.gameCenterMatchID,
            gameIndex: match.gameIndex,
            userPlayed: match.userPlayed,
            winner: completion.winner == match.userPlayed ? .you : .rival,
            userScore: completion.finalScore.score(for: match.userPlayed),
            rivalScore: completion.finalScore.score(for: rivalPlayer),
            targetScore: match.state.config.targetScore,
            startedAt: match.startedAt,
            completedAt: completedAt,
            finalSnapshot: match.state
        )
    }

    private func appendRecordIfNeeded(
        _ record: MatchRecord,
        for match: ActiveMatch,
        existingRecords: [MatchRecord]? = nil
    ) async throws {
        let records: [MatchRecord]
        if let existingRecords {
            records = existingRecords
        } else {
            records = try await store.loadMatchRecords(rivalID: match.rivalID)
        }

        guard !records.contains(where: { existingRecord in
            if let matchID = match.gameCenterMatchID,
               let existingMatchID = existingRecord.gameCenterMatchID {
                return existingMatchID == matchID && existingRecord.gameIndex == match.gameIndex
            }

            return existingRecord.startedAt == match.startedAt &&
                existingRecord.finalSnapshot == match.state
        }) else {
            return
        }

        try await store.appendMatchRecord(record)
    }
}
