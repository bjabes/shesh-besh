import Foundation

public protocol LedgerStore: Sendable {
    func loadRivals() async throws -> [Rival]
    func upsertRival(_ rival: Rival) async throws
    func deleteRival(id: Rival.ID) async throws

    func loadMatchRecords(rivalID: Rival.ID) async throws -> [MatchRecord]
    func appendMatchRecord(_ record: MatchRecord) async throws
    func deleteMatchRecords(rivalID: Rival.ID) async throws

    func loadActiveMatch(rivalID: Rival.ID) async throws -> ActiveMatch?
    func saveActiveMatch(_ match: ActiveMatch) async throws
    func clearActiveMatch(rivalID: Rival.ID) async throws

    func loadAllLedgerData() async throws -> LedgerSnapshot
}

public struct LedgerSnapshot: Equatable, Sendable {
    public let rivals: [Rival]
    public let recordsByRival: [Rival.ID: [MatchRecord]]
    public let activeMatchesByRival: [Rival.ID: ActiveMatch]

    public init(
        rivals: [Rival],
        recordsByRival: [Rival.ID: [MatchRecord]],
        activeMatchesByRival: [Rival.ID: ActiveMatch]
    ) {
        self.rivals = rivals
        self.recordsByRival = recordsByRival
        self.activeMatchesByRival = activeMatchesByRival
    }
}

public enum LedgerStoreError: Error, Equatable, LocalizedError, Sendable {
    case missingMatchCompletion
    case rivalHasHistory
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .missingMatchCompletion:
            "The match has not completed yet."
        case .rivalHasHistory:
            "A rival with match history cannot be deleted yet."
        case .unsupportedSchemaVersion(let version):
            "Unsupported ledger schema version \(version)."
        }
    }
}
