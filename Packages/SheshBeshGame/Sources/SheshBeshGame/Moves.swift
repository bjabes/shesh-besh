public enum MoveSource: Codable, Equatable, Hashable, Sendable {
    case bar
    case point(PointID)
}

public enum MoveDestination: Codable, Equatable, Hashable, Sendable {
    case point(PointID)
    case off
}

public struct Move: Codable, Equatable, Hashable, Sendable {
    public let player: Player
    public let source: MoveSource
    public let destination: MoveDestination
    public let die: Int

    public init(
        player: Player,
        source: MoveSource,
        destination: MoveDestination,
        die: Int
    ) {
        self.player = player
        self.source = source
        self.destination = destination
        self.die = die
    }
}

public struct MoveSequence: Codable, Equatable, Hashable, Sendable {
    public let moves: [Move]

    public init(moves: [Move]) {
        self.moves = moves
    }
}

public struct AppliedMove: Codable, Equatable, Hashable, Sendable {
    public let move: Move
    public let didHit: Bool

    public init(move: Move, didHit: Bool = false) {
        self.move = move
        self.didHit = didHit
    }
}
