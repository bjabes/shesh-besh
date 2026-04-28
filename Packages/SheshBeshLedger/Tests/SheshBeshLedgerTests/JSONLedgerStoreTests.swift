import Foundation
import SheshBeshGame
import SheshBeshLedger
import Testing

@Suite("JSON ledger store")
struct JSONLedgerStoreTests {
    @Test("snapshot survives store reinitialization")
    func roundTripAcrossInstances() async throws {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("ledger.json")
        defer {
            try? fileManager.removeItem(at: directoryURL)
        }

        let rival = Rival(displayName: "Dan")
        let record = MatchRecord(
            rivalID: rival.id,
            userPlayed: .white,
            winner: .rival,
            userScore: 3,
            rivalScore: 7,
            targetScore: 7,
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 200),
            finalSnapshot: MatchEngine.newMatch(config: .tournament(targetScore: 7))
        )
        let activeMatch = ActiveMatch(
            rivalID: rival.id,
            userPlayed: .black,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 5))
        )

        let writer = try JSONLedgerStore(fileURL: fileURL)
        try await writer.upsertRival(rival)
        try await writer.appendMatchRecord(record)
        try await writer.saveActiveMatch(activeMatch)

        let reader = try JSONLedgerStore(fileURL: fileURL)
        let snapshot = try await reader.loadAllLedgerData()

        #expect(snapshot.rivals == [rival])
        #expect(snapshot.recordsByRival[rival.id] == [record])
        #expect(snapshot.activeMatchesByRival[rival.id] == activeMatch)

        let directoryContents = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
        #expect(!directoryContents.contains(".ledger.json.tmp"))
    }

    @Test("match record deletion persists")
    func deleteMatchRecordsPersists() async throws {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("ledger.json")
        defer {
            try? fileManager.removeItem(at: directoryURL)
        }

        let firstRival = Rival(displayName: "Dan")
        let secondRival = Rival(displayName: "Lee")
        let firstRecord = MatchRecord(
            rivalID: firstRival.id,
            userPlayed: .white,
            winner: .you,
            userScore: 7,
            rivalScore: 2,
            targetScore: 7,
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 200)
        )
        let secondRecord = MatchRecord(
            rivalID: secondRival.id,
            userPlayed: .black,
            winner: .rival,
            userScore: 3,
            rivalScore: 7,
            targetScore: 7,
            startedAt: Date(timeIntervalSince1970: 300),
            completedAt: Date(timeIntervalSince1970: 400)
        )

        let writer = try JSONLedgerStore(fileURL: fileURL)
        try await writer.appendMatchRecord(firstRecord)
        try await writer.appendMatchRecord(secondRecord)
        try await writer.deleteMatchRecords(rivalID: firstRival.id)

        let reader = try JSONLedgerStore(fileURL: fileURL)
        #expect(try await reader.loadMatchRecords(rivalID: firstRival.id).isEmpty)
        #expect(try await reader.loadMatchRecords(rivalID: secondRival.id) == [secondRecord])
    }
}
