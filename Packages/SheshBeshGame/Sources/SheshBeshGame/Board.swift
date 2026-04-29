public struct PointState: Codable, Equatable, Hashable, Sendable {
    public let owner: Player?
    public let count: Int

    public init(owner: Player?, count: Int) {
        precondition(count >= 0, "Point count cannot be negative")
        precondition((owner == nil) == (count == 0), "Empty points must not have an owner")
        self.owner = owner
        self.count = count
    }

    public static let empty = PointState(owner: nil, count: 0)
}

public struct Board: Codable, Equatable, Hashable, Sendable {
    public private(set) var points: [PointState]
    public private(set) var whiteBar: Int
    public private(set) var blackBar: Int
    public private(set) var whiteBorneOff: Int
    public private(set) var blackBorneOff: Int

    public init(
        points: [PointState],
        whiteBar: Int = 0,
        blackBar: Int = 0,
        whiteBorneOff: Int = 0,
        blackBorneOff: Int = 0
    ) throws {
        guard points.count == 24 else { throw BoardError.invalidPointCount }
        guard whiteBar >= 0, blackBar >= 0, whiteBorneOff >= 0, blackBorneOff >= 0 else {
            throw BoardError.negativeCheckerCount
        }
        self.points = points
        self.whiteBar = whiteBar
        self.blackBar = blackBar
        self.whiteBorneOff = whiteBorneOff
        self.blackBorneOff = blackBorneOff
    }

    public static func empty() -> Board {
        try! Board(points: Array(repeating: .empty, count: 24))
    }

    public static func initial() -> Board {
        var board = Board.empty()
        try! board.setPoint(PointID(rawValue: 24)!, owner: .white, count: 2)
        try! board.setPoint(PointID(rawValue: 13)!, owner: .white, count: 5)
        try! board.setPoint(PointID(rawValue: 8)!, owner: .white, count: 3)
        try! board.setPoint(PointID(rawValue: 6)!, owner: .white, count: 5)
        try! board.setPoint(PointID(rawValue: 1)!, owner: .black, count: 2)
        try! board.setPoint(PointID(rawValue: 12)!, owner: .black, count: 5)
        try! board.setPoint(PointID(rawValue: 17)!, owner: .black, count: 3)
        try! board.setPoint(PointID(rawValue: 19)!, owner: .black, count: 5)
        return board
    }

    public func point(_ id: PointID) -> PointState {
        points[id.rawValue - 1]
    }

    public func barCount(for player: Player) -> Int {
        switch player {
        case .white: whiteBar
        case .black: blackBar
        }
    }

    public func borneOffCount(for player: Player) -> Int {
        switch player {
        case .white: whiteBorneOff
        case .black: blackBorneOff
        }
    }

    public func occupiedPoints(for player: Player) -> [PointID] {
        points.enumerated().compactMap { index, state in
            guard state.owner == player, state.count > 0 else { return nil }
            return PointID(rawValue: index + 1)
        }
    }

    public func totalCheckers(for player: Player) -> Int {
        let onBoard = points.reduce(0) { total, state in
            total + (state.owner == player ? state.count : 0)
        }
        return onBoard + barCount(for: player) + borneOffCount(for: player)
    }

    public func isValidForGame() -> Bool {
        guard points.count == 24 else { return false }
        guard whiteBar >= 0, blackBar >= 0, whiteBorneOff >= 0, blackBorneOff >= 0 else {
            return false
        }
        guard points.allSatisfy({ $0.count >= 0 && (($0.owner == nil) == ($0.count == 0)) }) else {
            return false
        }
        return totalCheckers(for: .white) == 15 && totalCheckers(for: .black) == 15
    }

    public func allCheckersAreHome(for player: Player) -> Bool {
        guard barCount(for: player) == 0 else { return false }
        for point in occupiedPoints(for: player) where !player.isHomePoint(point) {
            return false
        }
        return true
    }

    public var isNoContactRace: Bool {
        guard whiteBar == 0, blackBar == 0 else { return false }

        let whitePoints = occupiedPoints(for: .white).map(\.rawValue)
        let blackPoints = occupiedPoints(for: .black).map(\.rawValue)
        guard let highestWhitePoint = whitePoints.max(),
              let lowestBlackPoint = blackPoints.min()
        else {
            return true
        }

        return highestWhitePoint < lowestBlackPoint
    }

    public func canLand(on point: PointID, player: Player) -> Bool {
        let state = self.point(point)
        return state.owner == nil || state.owner == player || state.count == 1
    }

    public func hasCheckerOnBarOrInHomeBoard(of winner: Player, loser: Player) -> Bool {
        if barCount(for: loser) > 0 { return true }
        return occupiedPoints(for: loser).contains { winner.homeBoard.contains($0.rawValue) }
    }

    public mutating func setPoint(_ id: PointID, owner: Player?, count: Int) throws {
        guard count >= 0 else { throw BoardError.negativeCheckerCount }
        guard (owner == nil) == (count == 0) else { throw BoardError.invalidPointOccupancy }
        points[id.rawValue - 1] = PointState(owner: owner, count: count)
    }

    public mutating func setBar(for player: Player, count: Int) throws {
        guard count >= 0 else { throw BoardError.negativeCheckerCount }
        switch player {
        case .white: whiteBar = count
        case .black: blackBar = count
        }
    }

    public mutating func setBorneOff(for player: Player, count: Int) throws {
        guard count >= 0 else { throw BoardError.negativeCheckerCount }
        switch player {
        case .white: whiteBorneOff = count
        case .black: blackBorneOff = count
        }
    }

    internal mutating func apply(_ move: Move) throws {
        try removeChecker(from: move.source, player: move.player)
        try addChecker(to: move.destination, player: move.player)
    }

    internal func canBearOff(player: Player, from point: PointID, die: Int) -> Bool {
        guard allCheckersAreHome(for: player), player.isHomePoint(point) else { return false }

        switch player {
        case .white:
            if point.rawValue == die { return true }
            guard die > point.rawValue else { return false }
            let fartherPoints = (point.rawValue + 1)...6
            return fartherPoints.allSatisfy { rawValue in
                self.point(PointID(rawValue: rawValue)!).owner != .white
            }
        case .black:
            let exactDie = point.perspectiveValue(for: player)
            if exactDie == die { return true }
            guard die > exactDie else { return false }
            let fartherPoints = 19..<(point.rawValue)
            return fartherPoints.allSatisfy { rawValue in
                self.point(PointID(rawValue: rawValue)!).owner != .black
            }
        }
    }

    private mutating func removeChecker(from source: MoveSource, player: Player) throws {
        switch source {
        case .bar:
            let count = barCount(for: player)
            guard count > 0 else { throw BoardError.noCheckerAtSource }
            try setBar(for: player, count: count - 1)
        case .point(let point):
            let state = self.point(point)
            guard state.owner == player, state.count > 0 else { throw BoardError.noCheckerAtSource }
            try setPoint(
                point,
                owner: state.count == 1 ? nil : player,
                count: state.count - 1
            )
        }
    }

    private mutating func addChecker(to destination: MoveDestination, player: Player) throws {
        switch destination {
        case .off:
            try setBorneOff(for: player, count: borneOffCount(for: player) + 1)
        case .point(let point):
            let state = self.point(point)
            if state.owner == player {
                try setPoint(point, owner: player, count: state.count + 1)
            } else if state.owner == nil {
                try setPoint(point, owner: player, count: 1)
            } else if state.count == 1 {
                try setPoint(point, owner: player, count: 1)
                try setBar(for: player.opponent, count: barCount(for: player.opponent) + 1)
            } else {
                throw BoardError.blockedDestination
            }
        }
    }
}

public enum BoardError: Error, Equatable, Sendable {
    case invalidPointCount
    case negativeCheckerCount
    case invalidPointOccupancy
    case noCheckerAtSource
    case blockedDestination
}
