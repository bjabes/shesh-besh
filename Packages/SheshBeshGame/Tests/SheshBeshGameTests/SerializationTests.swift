import Foundation
import SheshBeshGame
import Testing

@Suite("Serialization")
struct SerializationTests {
    @Test("Match state round-trips through Codable")
    func matchStateRoundTrip() throws {
        let state = MatchState(
            config: .tournament(targetScore: 5),
            score: MatchScore(white: 2, black: 1),
            game: GameState(
                board: .initial(),
                phase: .awaitingCubeResponse(
                    CubeOffer(offeredBy: .white, proposedValue: 4, previousCubeValue: 2)
                ),
                cube: CubeState(value: 2, owner: .black)
            ),
            gameNumber: 4,
            crawfordState: .completed
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(MatchState.self, from: data)

        #expect(decoded == state)
    }
}
