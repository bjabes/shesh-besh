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
        var offeredDouble = false
        var handledCubeResponse = false
        var offeredResignation = false
        var handledResignationResponse = false

        for _ in 0..<80 {
            let action: MatchAction
            switch state.game.phase {
            case .awaitingOpeningRoll:
                action = .rollOpeningDice
            case .awaitingRoll(let player):
                if !offeredDouble, MatchEngine.legalActions(in: state).contains(.offerDouble(player)) {
                    offeredDouble = true
                    action = .offerDouble(player)
                } else {
                    action = .rollDice(player)
                }
            case .awaitingMove(let turn):
                if !offeredResignation {
                    offeredResignation = true
                    action = .offerResignation(turn.player, .single)
                } else {
                    let firstMove = try #require(MoveValidator.legalFirstMoves(for: turn.player, in: state.game).first)
                    action = .move(firstMove)
                }
            case .awaitingCubeResponse(let offer):
                handledCubeResponse = true
                action = .takeDouble(offer.offeredBy.opponent)
            case .awaitingResignationResponse(let offer):
                handledResignationResponse = true
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

        #expect(offeredDouble)
        #expect(handledCubeResponse)
        #expect(offeredResignation)
        #expect(handledResignationResponse)
    }
}
