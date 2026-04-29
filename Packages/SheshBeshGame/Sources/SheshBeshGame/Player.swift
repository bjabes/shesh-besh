public enum Player: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case white
    case black

    public var opponent: Player {
        switch self {
        case .white: .black
        case .black: .white
        }
    }

    public var movementDirection: Int {
        switch self {
        case .white: -1
        case .black: 1
        }
    }

    public var homeBoard: ClosedRange<Int> {
        switch self {
        case .white: 1...6
        case .black: 19...24
        }
    }

    public func entryPoint(for die: Int) -> PointID? {
        switch self {
        case .white:
            PointID(rawValue: 25 - die)
        case .black:
            PointID(rawValue: die)
        }
    }

    public func isHomePoint(_ point: PointID) -> Bool {
        homeBoard.contains(point.rawValue)
    }
}

public struct PointID: RawRepresentable, Codable, Comparable, Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init?(rawValue: Int) {
        guard (1...24).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public func perspectiveValue(for player: Player) -> Int {
        switch player {
        case .white:
            rawValue
        case .black:
            25 - rawValue
        }
    }

    public static func < (lhs: PointID, rhs: PointID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
