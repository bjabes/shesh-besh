import CryptoKit
import Foundation
import SheshBeshGame

public struct GameCenterPlayerMapping: Codable, Equatable, Hashable, Sendable {
    public var whitePlayerID: String
    public var blackPlayerID: String
    public var whiteDisplayName: String
    public var blackDisplayName: String

    public init(
        whitePlayerID: String,
        blackPlayerID: String,
        whiteDisplayName: String,
        blackDisplayName: String
    ) {
        self.whitePlayerID = whitePlayerID
        self.blackPlayerID = blackPlayerID
        self.whiteDisplayName = whiteDisplayName
        self.blackDisplayName = blackDisplayName
    }

    public func player(forGameCenterID playerID: String) -> Player? {
        if playerID == whitePlayerID { return .white }
        if playerID == blackPlayerID { return .black }
        return nil
    }

    public func gameCenterID(for player: Player) -> String {
        switch player {
        case .white:
            whitePlayerID
        case .black:
            blackPlayerID
        }
    }

    public func displayName(for player: Player) -> String {
        switch player {
        case .white:
            whiteDisplayName
        case .black:
            blackDisplayName
        }
    }
}

public struct GameCenterMatchEnvelope: Codable, Equatable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let minimumSupportedSchemaVersion = 1

    public var schemaVersion: Int
    public var minimumSupportedSchemaVersion: Int
    public var revision: Int
    public var turnCounter: Int
    public var gameIndex: Int
    public var gameCenterMatchID: String
    public var playerMapping: GameCenterPlayerMapping
    public var config: MatchConfig
    public var state: MatchState

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        minimumSupportedSchemaVersion: Int = Self.minimumSupportedSchemaVersion,
        revision: Int = 0,
        turnCounter: Int = 0,
        gameIndex: Int = 0,
        gameCenterMatchID: String,
        playerMapping: GameCenterPlayerMapping,
        config: MatchConfig,
        state: MatchState
    ) {
        self.schemaVersion = schemaVersion
        self.minimumSupportedSchemaVersion = minimumSupportedSchemaVersion
        self.revision = revision
        self.turnCounter = turnCounter
        self.gameIndex = gameIndex
        self.gameCenterMatchID = gameCenterMatchID
        self.playerMapping = playerMapping
        self.config = config
        self.state = state
    }

    public func validateSupported() throws {
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw GameCenterEnvelopeError.futureSchemaVersion(schemaVersion)
        }
        guard minimumSupportedSchemaVersion <= Self.currentSchemaVersion else {
            throw GameCenterEnvelopeError.futureMinimumSupportedSchemaVersion(minimumSupportedSchemaVersion)
        }
    }

    public func encoded() throws -> Data {
        try JSONEncoder.gameCenterEnvelope.encode(self)
    }

    public static func decoded(from data: Data) throws -> GameCenterMatchEnvelope {
        let envelope = try JSONDecoder().decode(GameCenterMatchEnvelope.self, from: data)
        try envelope.validateSupported()
        return envelope
    }
}

public enum GameCenterEnvelopeError: Error, Equatable, LocalizedError, Sendable {
    case emptyMatchData
    case futureSchemaVersion(Int)
    case futureMinimumSupportedSchemaVersion(Int)
    case corruptMatchData
    case matchDataTooLarge(Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyMatchData:
            "This Game Center match does not have game data yet."
        case .futureSchemaVersion:
            "Update \(AppBrand.name) to continue this match."
        case .futureMinimumSupportedSchemaVersion:
            "Update \(AppBrand.name) to continue this match."
        case .corruptMatchData:
            "This match data could not be read. Try reloading the match."
        case .matchDataTooLarge(let size, let maximum):
            "The match data is \(size) bytes, above Game Center's \(maximum)-byte limit."
        }
    }
}

public final class GameCenterDiceRoller: DiceRolling, @unchecked Sendable {
    private var state: UInt64

    public init(matchID: String, turnCounter: Int, revision: Int = 0) {
        self.state = Self.seed(matchID: matchID, turnCounter: turnCounter, revision: revision)
    }

    public func rollDie() -> Int {
        let value = next()
        return Int(value % 6) + 1
    }

    private func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    public static func seed(matchID: String, turnCounter: Int, revision: Int = 0) -> UInt64 {
        stableHash(matchID)
            ^ (UInt64(bitPattern: Int64(turnCounter)) &* 0xD6E8_FEB8_6659_FD93)
            ^ (UInt64(bitPattern: Int64(revision)) &* 0xA5A3_58EF_1BBC_3F43)
    }

    public static func stableHash(_ string: String) -> UInt64 {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.prefix(8).reduce(UInt64(0)) { partial, byte in
            (partial << 8) | UInt64(byte)
        }
    }
}

private extension JSONEncoder {
    static var gameCenterEnvelope: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
