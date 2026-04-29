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

    @Test("default file URL migrates legacy app support ledger")
    func defaultFileURLMigratesLegacyLedger() async throws {
        let fileManager = FileManager.default
        let applicationSupportURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyDirectoryURL = applicationSupportURL.appendingPathComponent("SheshBesh", isDirectory: true)
        let legacyFileURL = legacyDirectoryURL.appendingPathComponent("ledger.json")
        defer {
            try? fileManager.removeItem(at: applicationSupportURL)
        }

        try fileManager.createDirectory(at: legacyDirectoryURL, withIntermediateDirectories: true)
        let rival = Rival(displayName: "Dan")
        let writer = try JSONLedgerStore(fileURL: legacyFileURL)
        try await writer.upsertRival(rival)

        let migratedFileURL = try JSONLedgerStore.defaultFileURL(applicationSupportURL: applicationSupportURL)
        #expect(migratedFileURL.pathComponents.suffix(2) == ["Gammonade", "ledger.json"])
        #expect(fileManager.fileExists(atPath: migratedFileURL.path))
        #expect(!fileManager.fileExists(atPath: legacyFileURL.path))

        let reader = try JSONLedgerStore(fileURL: migratedFileURL)
        #expect(try await reader.loadRivals() == [rival])
    }

    @Test("default file URL keeps existing Gammonade ledger")
    func defaultFileURLKeepsExistingGammonadeLedger() async throws {
        let fileManager = FileManager.default
        let applicationSupportURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let newDirectoryURL = applicationSupportURL.appendingPathComponent("Gammonade", isDirectory: true)
        let newFileURL = newDirectoryURL.appendingPathComponent("ledger.json")
        let legacyDirectoryURL = applicationSupportURL.appendingPathComponent("SheshBesh", isDirectory: true)
        let legacyFileURL = legacyDirectoryURL.appendingPathComponent("ledger.json")
        defer {
            try? fileManager.removeItem(at: applicationSupportURL)
        }

        try fileManager.createDirectory(at: newDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: legacyDirectoryURL, withIntermediateDirectories: true)

        let gammonadeRival = Rival(displayName: "Mira")
        let legacyRival = Rival(displayName: "Dan")
        let newWriter = try JSONLedgerStore(fileURL: newFileURL)
        try await newWriter.upsertRival(gammonadeRival)
        let legacyWriter = try JSONLedgerStore(fileURL: legacyFileURL)
        try await legacyWriter.upsertRival(legacyRival)

        let resolvedFileURL = try JSONLedgerStore.defaultFileURL(applicationSupportURL: applicationSupportURL)
        let reader = try JSONLedgerStore(fileURL: resolvedFileURL)

        #expect(resolvedFileURL == newFileURL)
        #expect(try await reader.loadRivals() == [gammonadeRival])
        #expect(fileManager.fileExists(atPath: legacyFileURL.path))
    }
}
