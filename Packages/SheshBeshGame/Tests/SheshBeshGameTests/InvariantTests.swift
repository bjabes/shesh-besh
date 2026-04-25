import SheshBeshGame
import Testing

@Suite("Invariants")
struct InvariantTests {
    @Test("Generated legal transitions preserve board invariants")
    func generatedLegalTransitionsPreserveInvariants() throws {
        let dice = [
            6, 1, 3, 2, 5, 4, 2, 2, 6, 3, 1, 5, 4, 4, 2, 1,
            6, 5, 3, 3, 1, 4, 5, 2, 6, 6, 1, 3, 4, 2, 5, 1,
        ]
        let engine = MatchEngine(diceRoller: ScriptedDiceRoller(dice))
        var state = MatchEngine.newMatch(config: .tournament(targetScore: 7))

        for _ in 0..<80 {
            let action: MatchAction
            switch state.game.phase {
            case .awaitingOpeningRoll:
                action = .rollOpeningDice
            case .awaitingRoll(let player):
                action = .rollDice(player)
            case .awaitingMove(let turn):
                let firstMove = try #require(MoveValidator.legalFirstMoves(for: turn.player, in: state.game).first)
                action = .move(firstMove)
            case .awaitingCubeResponse(let offer):
                action = .takeDouble(offer.offeredBy.opponent)
            case .awaitingResignationResponse(let offer):
                action = .rejectResignation(offer.offeredBy.opponent)
            case .gameOver:
                if state.completion != nil { return }
                action = .startNextGame
            }

            state = try engine.apply(action: action, to: state)

            #expect(state.game.board.totalCheckers(for: .white) == 15)
            #expect(state.game.board.totalCheckers(for: .black) == 15)
            expectNoMixedPoints(state.game.board)
            #expect(state.score.score(for: .white) >= 0)
            #expect(state.score.score(for: .black) >= 0)
        }
    }
}
