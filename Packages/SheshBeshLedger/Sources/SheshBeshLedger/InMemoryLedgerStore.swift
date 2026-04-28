import Foundation

public actor InMemoryLedgerStore: LedgerStore {
    private var rivalsByID: [Rival.ID: Rival]
    private var rivalOrder: [Rival.ID]
    private var recordsByRival: [Rival.ID: [MatchRecord]]
    private var activeMatchesByRival: [Rival.ID: ActiveMatch]

    public init(
        rivals: [Rival] = [],
        records: [MatchRecord] = [],
        activeMatches: [ActiveMatch] = []
    ) {
        self.rivalsByID = Dictionary(uniqueKeysWithValues: rivals.map { ($0.id, $0) })
        self.rivalOrder = rivals.map(\.id)
        self.recordsByRival = Dictionary(grouping: records, by: \.rivalID)
        self.activeMatchesByRival = Dictionary(uniqueKeysWithValues: activeMatches.map { ($0.rivalID, $0) })
    }

    public func loadRivals() async throws -> [Rival] {
        orderedRivals()
    }

    public func upsertRival(_ rival: Rival) async throws {
        if rivalsByID[rival.id] == nil {
            rivalOrder.append(rival.id)
        }
        rivalsByID[rival.id] = rival
    }

    public func deleteRival(id: Rival.ID) async throws {
        if recordsByRival[id, default: []].isEmpty, activeMatchesByRival[id] == nil {
            rivalsByID[id] = nil
            rivalOrder.removeAll { $0 == id }
        } else {
            throw LedgerStoreError.rivalHasHistory
        }
    }

    public func loadMatchRecords(rivalID: Rival.ID) async throws -> [MatchRecord] {
        recordsByRival[rivalID, default: []]
    }

    public func appendMatchRecord(_ record: MatchRecord) async throws {
        recordsByRival[record.rivalID, default: []].append(record)
    }

    public func deleteMatchRecords(rivalID: Rival.ID) async throws {
        recordsByRival[rivalID] = nil
    }

    public func loadActiveMatch(rivalID: Rival.ID) async throws -> ActiveMatch? {
        activeMatchesByRival[rivalID]
    }

    public func saveActiveMatch(_ match: ActiveMatch) async throws {
        activeMatchesByRival[match.rivalID] = match
    }

    public func clearActiveMatch(rivalID: Rival.ID) async throws {
        activeMatchesByRival[rivalID] = nil
    }

    public func loadAllLedgerData() async throws -> LedgerSnapshot {
        LedgerSnapshot(
            rivals: orderedRivals(),
            recordsByRival: recordsByRival,
            activeMatchesByRival: activeMatchesByRival
        )
    }

    private func orderedRivals() -> [Rival] {
        rivalOrder.compactMap { rivalsByID[$0] }
    }
}
