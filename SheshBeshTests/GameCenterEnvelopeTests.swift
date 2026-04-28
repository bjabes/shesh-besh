import Foundation
@testable import SheshBeshApp
import SheshBeshGame
import Testing

@Suite("Game Center envelope")
struct GameCenterEnvelopeTests {
    @Test("envelope round trips match state and player mapping")
    func envelopeRoundTrip() throws {
        let config = MatchConfig.tournament(targetScore: 7)
        let envelope = GameCenterMatchEnvelope(
            revision: 3,
            turnCounter: 4,
            gameCenterMatchID: "match-123",
            playerMapping: GameCenterPlayerMapping(
                whitePlayerID: "white-player",
                blackPlayerID: "black-player",
                whiteDisplayName: "Boris",
                blackDisplayName: "Dan"
            ),
            config: config,
            state: MatchEngine.newMatch(config: config)
        )

        let decoded = try GameCenterMatchEnvelope.decoded(from: envelope.encoded())

        #expect(decoded == envelope)
        #expect(decoded.playerMapping.player(forGameCenterID: "black-player") == .black)
        #expect(decoded.playerMapping.displayName(for: .white) == "Boris")
    }

    @Test("future schema asks for app update")
    func futureSchemaThrowsUpdateError() throws {
        let config = MatchConfig.tournament(targetScore: 7)
        let envelope = GameCenterMatchEnvelope(
            schemaVersion: GameCenterMatchEnvelope.currentSchemaVersion + 1,
            gameCenterMatchID: "match-123",
            playerMapping: GameCenterPlayerMapping(
                whitePlayerID: "white-player",
                blackPlayerID: "black-player",
                whiteDisplayName: "Boris",
                blackDisplayName: "Dan"
            ),
            config: config,
            state: MatchEngine.newMatch(config: config)
        )

        #expect(throws: GameCenterEnvelopeError.futureSchemaVersion(2)) {
            try GameCenterMatchEnvelope.decoded(from: envelope.encoded())
        }
    }

    @Test("deterministic dice fixture is stable")
    func deterministicDiceFixture() {
        let roller = GameCenterDiceRoller(matchID: "match-fixture-1", turnCounter: 4)
        let rolls = (0..<10).map { _ in roller.rollDie() }

        #expect(rolls == [1, 5, 2, 1, 6, 6, 5, 1, 1, 3])
    }

    @Test("revision participates in deterministic dice seed")
    func revisionChangesDiceSequence() {
        let roller = GameCenterDiceRoller(matchID: "match-fixture-1", turnCounter: 4, revision: 1)
        let rolls = (0..<6).map { _ in roller.rollDie() }

        #expect(rolls == [5, 4, 4, 6, 4, 2])
    }

    @Test("pending Game Center IDs are identified as unresolved participants")
    func pendingGameCenterIDsAreUnresolvedParticipants() {
        let mapping = GameCenterPlayerMapping(
            whitePlayerID: "local-player",
            blackPlayerID: "pending-match-123",
            whiteDisplayName: "Boris",
            blackDisplayName: "Opponent"
        )

        #expect(mapping.hasPendingGameCenterID(for: .black))
        #expect(!mapping.hasPendingGameCenterID(for: .white))
        #expect(GameCenterPlayerMapping.isPendingGameCenterID("pending-match-123"))
        #expect(!GameCenterPlayerMapping.isPendingGameCenterID("real-player"))
    }
}
