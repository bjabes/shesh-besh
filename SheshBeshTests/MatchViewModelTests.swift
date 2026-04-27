import SheshBeshApp
import SheshBeshGame
import Testing

@Suite("Match view model")
struct MatchViewModelTests {
    @Test("opening roll is applied through the engine")
    @MainActor
    func openingRollUsesEngine() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        viewModel.rollOpeningDice()

        guard case .awaitingMove(let turn) = viewModel.state.game.phase else {
            Issue.record("Expected opening roll to begin a move turn.")
            return
        }

        #expect(turn.player == .white)
        #expect(turn.roll.die1 == 6)
        #expect(turn.roll.die2 == 1)
        #expect(viewModel.lastError == nil)
    }

    @Test("legal destinations are sourced from reducer legal actions")
    @MainActor
    func legalDestinationsComeFromEngine() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        viewModel.rollOpeningDice()

        let source = MoveSource.point(PointID(rawValue: 24)!)
        let destinations = viewModel.legalDestinations(from: source)

        #expect(destinations.contains(.point(PointID(rawValue: 18)!)))
        #expect(destinations.contains(.point(PointID(rawValue: 23)!)))
    }

    @Test("applying a point move updates board state")
    @MainActor
    func applyMoveUpdatesState() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        viewModel.rollOpeningDice()

        let moved = viewModel.applyMove(
            from: .point(PointID(rawValue: 24)!),
            to: .point(PointID(rawValue: 18)!)
        )

        #expect(moved)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 24)!).count == 1)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 18)!).owner == .white)
        #expect(viewModel.state.game.board.point(PointID(rawValue: 18)!).count == 1)
    }

    @Test("offering resignation enters resignation response phase")
    @MainActor
    func offerResignationWhenAllowed() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        viewModel.rollOpeningDice()
        viewModel.offerResignationIfAllowed(.gammon)

        guard case .awaitingResignationResponse(let offer) = viewModel.state.game.phase else {
            Issue.record("Expected resignation response phase after resignation offer.")
            return
        }

        #expect(offer.offeredBy == .white)
        #expect(offer.winKind == .gammon)
        #expect(viewModel.lastError == nil)
    }

    @Test("invalid move is surfaced as a friendly message")
    @MainActor
    func invalidMoveMessageIsFriendly() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        viewModel.rollOpeningDice()
        viewModel.send(.move(Move(player: .white, source: .point(PointID(rawValue: 1)!), destination: .point(PointID(rawValue: 2)!), die: 1)))

        #expect(viewModel.lastError == "That move is not legal for the current dice.")
    }

    @Test("opponent double offer is exposed for the local player")
    @MainActor
    func opponentDoubleOfferIsExposedForLocalPlayer() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        advanceToOpponentRoll(viewModel)
        viewModel.send(.offerDouble(.black))

        let offer = viewModel.doubleOfferForLocalPlayer
        #expect(offer?.offeredBy == .black)
        #expect(offer?.proposedValue == 2)
        #expect(offer?.previousCubeValue == 1)
        #expect(viewModel.isLocalTurn)
    }

    @Test("taking an opponent double uses the reducer action")
    @MainActor
    func takeOpponentDoubleUsesReducerAction() {
        let viewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7)
        )

        advanceToOpponentRoll(viewModel)
        viewModel.send(.offerDouble(.black))
        viewModel.takeDoubleIfAllowed()

        #expect(viewModel.state.game.cube.value == 2)
        #expect(viewModel.state.game.cube.owner == .white)
        guard case .awaitingRoll(.black) = viewModel.state.game.phase else {
            Issue.record("Expected play to resume at the opponent's roll after taking.")
            return
        }
    }
}

@MainActor
private func advanceToOpponentRoll(_ viewModel: MatchViewModel) {
    viewModel.rollOpeningDice()
    _ = viewModel.applyMove(
        from: .point(PointID(rawValue: 24)!),
        to: .point(PointID(rawValue: 18)!)
    )
    _ = viewModel.applyMove(
        from: .point(PointID(rawValue: 24)!),
        to: .point(PointID(rawValue: 23)!)
    )
}

private final class ScriptedDiceRoller: DiceRolling, @unchecked Sendable {
    private let values: [Int]
    private var index = 0

    init(_ values: [Int]) {
        self.values = values
    }

    func rollDie() -> Int {
        let value = values[index % values.count]
        index += 1
        return value
    }
}
