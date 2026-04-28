import Foundation
import SheshBeshGame
import SheshBeshLedger
import Testing

@Suite("In-memory ledger store")
struct InMemoryLedgerStoreTests {
    @Test("rivals, records, and active matches round-trip")
    func roundTrip() async throws {
        let store = InMemoryLedgerStore()
        let rival = Rival(displayName: "Dan")
        let record = MatchRecord(
            rivalID: rival.id,
            userPlayed: .white,
            winner: .you,
            userScore: 7,
            rivalScore: 2,
            targetScore: 7,
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 200)
        )
        let activeMatch = ActiveMatch(
            rivalID: rival.id,
            userPlayed: .black,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 5))
        )

        try await store.upsertRival(rival)
        try await store.appendMatchRecord(record)
        try await store.saveActiveMatch(activeMatch)

        #expect(try await store.loadRivals() == [rival])
        #expect(try await store.loadMatchRecords(rivalID: rival.id) == [record])
        #expect(try await store.loadActiveMatch(rivalID: rival.id) == activeMatch)

        let snapshot = try await store.loadAllLedgerData()
        #expect(snapshot.rivals == [rival])
        #expect(snapshot.recordsByRival[rival.id] == [record])
        #expect(snapshot.activeMatchesByRival[rival.id] == activeMatch)
    }

    @Test("concurrent appends are serialized by the actor")
    func concurrentAppends() async throws {
        let store = InMemoryLedgerStore()
        let rival = Rival(displayName: "Dan")
        let first = record(rivalID: rival.id, id: UUID(), winner: .you)
        let second = record(rivalID: rival.id, id: UUID(), winner: .rival)

        try await store.upsertRival(rival)

        async let firstAppend: Void = store.appendMatchRecord(first)
        async let secondAppend: Void = store.appendMatchRecord(second)
        _ = try await (firstAppend, secondAppend)

        let records = try await store.loadMatchRecords(rivalID: rival.id)
        #expect(Set(records.map(\.id)) == Set([first.id, second.id]))
    }

    @Test("match records can be deleted for one rival")
    func deleteMatchRecords() async throws {
        let store = InMemoryLedgerStore()
        let firstRival = Rival(displayName: "Dan")
        let secondRival = Rival(displayName: "Lee")
        let firstRecord = record(rivalID: firstRival.id, id: UUID(), winner: .you)
        let secondRecord = record(rivalID: secondRival.id, id: UUID(), winner: .rival)

        try await store.appendMatchRecord(firstRecord)
        try await store.appendMatchRecord(secondRecord)
        try await store.deleteMatchRecords(rivalID: firstRival.id)

        #expect(try await store.loadMatchRecords(rivalID: firstRival.id).isEmpty)
        #expect(try await store.loadMatchRecords(rivalID: secondRival.id) == [secondRecord])
    }
}

private func record(rivalID: Rival.ID, id: UUID, winner: MatchOutcome) -> MatchRecord {
    MatchRecord(
        id: id,
        rivalID: rivalID,
        userPlayed: .white,
        winner: winner,
        userScore: winner == .you ? 7 : 2,
        rivalScore: winner == .you ? 2 : 7,
        targetScore: 7,
        startedAt: Date(timeIntervalSince1970: 100),
        completedAt: Date(timeIntervalSince1970: 200)
    )
}
