public struct MatchConfig: Codable, Equatable, Hashable, Sendable {
    public let targetScore: Int
    public let maximumCubeValue: Int
    public let usesDoublingCube: Bool
    public let usesCrawfordRule: Bool

    public init(
        targetScore: Int,
        maximumCubeValue: Int = 64,
        usesDoublingCube: Bool = true,
        usesCrawfordRule: Bool = true
    ) {
        precondition(targetScore > 0, "Match target score must be positive")
        precondition(maximumCubeValue > 0, "Maximum cube value must be positive")
        self.targetScore = targetScore
        self.maximumCubeValue = maximumCubeValue
        self.usesDoublingCube = usesDoublingCube
        self.usesCrawfordRule = usesCrawfordRule
    }

    public static func tournament(targetScore: Int) -> MatchConfig {
        MatchConfig(targetScore: targetScore)
    }
}

public struct MatchScore: Codable, Equatable, Hashable, Sendable {
    public private(set) var white: Int
    public private(set) var black: Int

    public init(white: Int = 0, black: Int = 0) {
        precondition(white >= 0 && black >= 0, "Scores cannot be negative")
        self.white = white
        self.black = black
    }

    public func score(for player: Player) -> Int {
        switch player {
        case .white: white
        case .black: black
        }
    }

    internal mutating func add(_ points: Int, to player: Player) {
        switch player {
        case .white: white += points
        case .black: black += points
        }
    }
}

public struct CubeState: Codable, Equatable, Hashable, Sendable {
    public let value: Int
    public let owner: Player?

    public init(value: Int = 1, owner: Player? = nil) {
        precondition(value > 0, "Cube value must be positive")
        self.value = value
        self.owner = owner
    }

    internal func doubled(to proposedValue: Int, owner newOwner: Player) -> CubeState {
        CubeState(value: proposedValue, owner: newOwner)
    }
}

public enum WinKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case single
    case gammon
    case backgammon

    public var multiplier: Int {
        switch self {
        case .single: 1
        case .gammon: 2
        case .backgammon: 3
        }
    }
}

public struct GameResult: Codable, Equatable, Hashable, Sendable {
    public let winner: Player
    public let winKind: WinKind
    public let cubeValue: Int
    public let points: Int

    public init(winner: Player, winKind: WinKind, cubeValue: Int) {
        self.winner = winner
        self.winKind = winKind
        self.cubeValue = cubeValue
        self.points = cubeValue * winKind.multiplier
    }
}

public struct MatchCompletion: Codable, Equatable, Hashable, Sendable {
    public let winner: Player
    public let finalScore: MatchScore

    public init(winner: Player, finalScore: MatchScore) {
        self.winner = winner
        self.finalScore = finalScore
    }
}

public struct TurnState: Codable, Equatable, Hashable, Sendable {
    public let player: Player
    public let roll: DiceRoll
    public let remainingDice: [Int]

    public init(player: Player, roll: DiceRoll, remainingDice: [Int]) {
        self.player = player
        self.roll = roll
        self.remainingDice = remainingDice
    }
}

public struct CubeOffer: Codable, Equatable, Hashable, Sendable {
    public let offeredBy: Player
    public let proposedValue: Int
    public let previousCubeValue: Int

    public init(offeredBy: Player, proposedValue: Int, previousCubeValue: Int) {
        self.offeredBy = offeredBy
        self.proposedValue = proposedValue
        self.previousCubeValue = previousCubeValue
    }
}

public enum ResumablePhase: Codable, Equatable, Hashable, Sendable {
    case awaitingRoll(Player)
    case awaitingMove(TurnState)

    internal var gamePhase: GamePhase {
        switch self {
        case .awaitingRoll(let player):
            .awaitingRoll(player)
        case .awaitingMove(let turn):
            .awaitingMove(turn)
        }
    }
}

public struct ResignationOffer: Codable, Equatable, Hashable, Sendable {
    public let offeredBy: Player
    public let winKind: WinKind
    public let resumePhase: ResumablePhase

    public init(offeredBy: Player, winKind: WinKind, resumePhase: ResumablePhase) {
        self.offeredBy = offeredBy
        self.winKind = winKind
        self.resumePhase = resumePhase
    }
}

public enum GamePhase: Codable, Equatable, Hashable, Sendable {
    case awaitingOpeningRoll
    case awaitingRoll(Player)
    case awaitingMove(TurnState)
    case awaitingCubeResponse(CubeOffer)
    case awaitingResignationResponse(ResignationOffer)
    case gameOver(GameResult)
}

public enum CrawfordState: String, Codable, Equatable, Hashable, Sendable {
    case notReached
    case availableNextGame
    case active
    case completed
}

public struct GameState: Codable, Equatable, Hashable, Sendable {
    public var board: Board
    public var phase: GamePhase
    public var cube: CubeState
    public var isCrawford: Bool

    public init(
        board: Board = .initial(),
        phase: GamePhase = .awaitingOpeningRoll,
        cube: CubeState = CubeState(),
        isCrawford: Bool = false
    ) {
        self.board = board
        self.phase = phase
        self.cube = cube
        self.isCrawford = isCrawford
    }
}

public struct MatchState: Codable, Equatable, Hashable, Sendable {
    public var config: MatchConfig
    public var score: MatchScore
    public var game: GameState
    public var gameNumber: Int
    public var crawfordState: CrawfordState
    public var completion: MatchCompletion?

    public init(
        config: MatchConfig,
        score: MatchScore = MatchScore(),
        game: GameState = GameState(),
        gameNumber: Int = 1,
        crawfordState: CrawfordState = .notReached,
        completion: MatchCompletion? = nil
    ) {
        self.config = config
        self.score = score
        self.game = game
        self.gameNumber = gameNumber
        self.crawfordState = crawfordState
        self.completion = completion
    }
}

public enum MatchAction: Codable, Equatable, Hashable, Sendable {
    case rollOpeningDice
    case rollDice(Player)
    case move(Move)
    case passTurn(Player)
    case offerDouble(Player)
    case takeDouble(Player)
    case dropDouble(Player)
    case offerResignation(Player, WinKind)
    case acceptResignation(Player)
    case rejectResignation(Player)
    case startNextGame
}

public enum MatchEngineError: Error, Equatable, Sendable {
    case invalidDiceValue
    case invalidAction(String)
    case illegalMove(Move)
    case matchAlreadyCompleted
}
