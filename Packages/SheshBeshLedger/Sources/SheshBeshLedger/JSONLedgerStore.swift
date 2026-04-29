import Foundation

public actor JSONLedgerStore: LedgerStore {
    public static let schemaVersion = 1

    private let fileURL: URL
    private var snapshot: PersistedSnapshot

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.snapshot = try Self.loadSnapshot(from: fileURL)
    }

    public static func defaultFileURL(
        applicationName: String = "Gammonade",
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) throws -> URL {
        let applicationSupportURL = try applicationSupportURL ?? defaultApplicationSupportURL(fileManager: fileManager)
        let fileURL = applicationSupportURL
            .appendingPathComponent(applicationName, isDirectory: true)
            .appendingPathComponent("ledger.json")

        try migrateLegacyLedgerIfNeeded(
            to: fileURL,
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )

        return fileURL
    }

    public func loadRivals() async throws -> [Rival] {
        snapshot.rivals
    }

    public func upsertRival(_ rival: Rival) async throws {
        if let index = snapshot.rivals.firstIndex(where: { $0.id == rival.id }) {
            snapshot.rivals[index] = rival
        } else {
            snapshot.rivals.append(rival)
        }
        try persist()
    }

    public func deleteRival(id: Rival.ID) async throws {
        let hasRecords = snapshot.records.contains { $0.rivalID == id }
        let hasActiveMatch = snapshot.activeMatches.contains { $0.rivalID == id }
        guard !hasRecords, !hasActiveMatch else {
            throw LedgerStoreError.rivalHasHistory
        }

        snapshot.rivals.removeAll { $0.id == id }
        try persist()
    }

    public func loadMatchRecords(rivalID: Rival.ID) async throws -> [MatchRecord] {
        snapshot.records.filter { $0.rivalID == rivalID }
    }

    public func appendMatchRecord(_ record: MatchRecord) async throws {
        snapshot.records.append(record)
        try persist()
    }

    public func deleteMatchRecords(rivalID: Rival.ID) async throws {
        snapshot.records.removeAll { $0.rivalID == rivalID }
        try persist()
    }

    public func loadActiveMatch(rivalID: Rival.ID) async throws -> ActiveMatch? {
        snapshot.activeMatches.first { $0.rivalID == rivalID }
    }

    public func saveActiveMatch(_ match: ActiveMatch) async throws {
        if let index = snapshot.activeMatches.firstIndex(where: { $0.rivalID == match.rivalID }) {
            snapshot.activeMatches[index] = match
        } else {
            snapshot.activeMatches.append(match)
        }
        try persist()
    }

    public func clearActiveMatch(rivalID: Rival.ID) async throws {
        snapshot.activeMatches.removeAll { $0.rivalID == rivalID }
        try persist()
    }

    public func loadAllLedgerData() async throws -> LedgerSnapshot {
        LedgerSnapshot(
            rivals: snapshot.rivals,
            recordsByRival: Dictionary(grouping: snapshot.records, by: \.rivalID),
            activeMatchesByRival: Dictionary(uniqueKeysWithValues: snapshot.activeMatches.map { ($0.rivalID, $0) })
        )
    }

    private func persist() throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        try data.write(to: fileURL, options: [.atomic])
    }

    private static func loadSnapshot(from fileURL: URL) throws -> PersistedSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PersistedSnapshot()
        }

        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(PersistedSnapshot.self, from: data)
        guard decoded.schemaVersion == schemaVersion else {
            throw LedgerStoreError.unsupportedSchemaVersion(decoded.schemaVersion)
        }
        return decoded
    }

    private static func defaultApplicationSupportURL(fileManager: FileManager) throws -> URL {
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return applicationSupportURL
    }

    private static func migrateLegacyLedgerIfNeeded(
        to fileURL: URL,
        applicationSupportURL: URL,
        fileManager: FileManager
    ) throws {
        guard !fileManager.fileExists(atPath: fileURL.path) else { return }

        let legacyFileURL = applicationSupportURL
            .appendingPathComponent("SheshBesh", isDirectory: true)
            .appendingPathComponent("ledger.json")
        guard fileManager.fileExists(atPath: legacyFileURL.path) else { return }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: legacyFileURL, to: fileURL)

        let legacyDirectoryURL = legacyFileURL.deletingLastPathComponent()
        if let remainingItems = try? fileManager.contentsOfDirectory(atPath: legacyDirectoryURL.path),
           remainingItems.isEmpty {
            try? fileManager.removeItem(at: legacyDirectoryURL)
        }
    }
}

private struct PersistedSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var rivals: [Rival]
    var records: [MatchRecord]
    var activeMatches: [ActiveMatch]

    init(
        schemaVersion: Int = JSONLedgerStore.schemaVersion,
        rivals: [Rival] = [],
        records: [MatchRecord] = [],
        activeMatches: [ActiveMatch] = []
    ) {
        self.schemaVersion = schemaVersion
        self.rivals = rivals
        self.records = records
        self.activeMatches = activeMatches
    }
}
