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

    @Test("Match state round-trips while a turn is in progress")
    func awaitingMoveRoundTripPreservesRemainingDice() throws {
        let state = try makeMatch(
            board: .initial(),
            player: .black,
            dice: [6, 3],
            config: .tournament(targetScore: 7),
            score: MatchScore(white: 3, black: 2),
            cube: CubeState(value: 2, owner: .white)
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(MatchState.self, from: data)

        #expect(decoded == state)
        guard case .awaitingMove(let turn) = decoded.game.phase else {
            Issue.record("Expected awaitingMove phase after decoding")
            return
        }
        #expect(turn.player == .black)
        #expect(turn.remainingDice == [6, 3])
    }

    @Test("Match state round-trips remaining game phases")
    func remainingGamePhasesRoundTrip() throws {
        let rollState = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(board: .initial(), phase: .awaitingRoll(.white))
        )
        let openingState = MatchEngine.newMatch(config: .tournament(targetScore: 5))
        let resignationState = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(
                board: .initial(),
                phase: .awaitingResignationResponse(
                    ResignationOffer(
                        offeredBy: .black,
                        winKind: .gammon,
                        resumePhase: .awaitingRoll(.black)
                    )
                )
            )
        )
        let gameOverState = MatchState(
            config: .tournament(targetScore: 5),
            game: GameState(
                board: .initial(),
                phase: .gameOver(GameResult(winner: .white, winKind: .single, cubeValue: 2))
            )
        )

        for state in [openingState, rollState, resignationState, gameOverState] {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(MatchState.self, from: data)

            #expect(decoded == state)
        }
    }

    @Test("Match state round-trips completion and Crawford states")
    func completionAndCrawfordStatesRoundTrip() throws {
        for crawfordState in [
            CrawfordState.notReached,
            .availableNextGame,
            .active,
            .completed,
        ] {
            let state = MatchState(
                config: .tournament(targetScore: 5),
                score: MatchScore(white: 5, black: 3),
                game: GameState(
                    board: .initial(),
                    phase: .gameOver(GameResult(winner: .white, winKind: .single, cubeValue: 1))
                ),
                gameNumber: 6,
                crawfordState: crawfordState,
                completion: MatchCompletion(winner: .white, finalScore: MatchScore(white: 5, black: 3))
            )

            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(MatchState.self, from: data)

            #expect(decoded == state)
            #expect(decoded.completion == state.completion)
            #expect(decoded.crawfordState == crawfordState)
        }
    }
}
