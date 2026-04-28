import SheshBeshGame

public struct CheckerID: Hashable, Sendable {
    public let player: Player
    public let index: Int

    public init(player: Player, index: Int) {
        self.player = player
        self.index = index
    }
}

public enum CheckerSlot: Hashable, Sendable {
    case point(PointID)
    case bar(Player)
    case off(Player)
}

public struct CheckerLayout: Equatable, Sendable {
    public var slots: [CheckerSlot: [CheckerID]]

    public init(slots: [CheckerSlot: [CheckerID]]) {
        self.slots = slots
    }

    public static func reconstructed(from board: Board) -> CheckerLayout {
        var slots: [CheckerSlot: [CheckerID]] = [:]
        var nextIndex: [Player: Int] = [.white: 0, .black: 0]

        func append(_ count: Int, for player: Player, to slot: CheckerSlot) {
            guard count > 0 else { return }
            for _ in 0..<count {
                let index = nextIndex[player, default: 0]
                slots[slot, default: []].append(CheckerID(player: player, index: index))
                nextIndex[player] = index + 1
            }
        }

        for (offset, point) in board.points.enumerated() {
            guard let owner = point.owner, let pointID = PointID(rawValue: offset + 1) else {
                continue
            }
            append(point.count, for: owner, to: .point(pointID))
        }

        for player in Player.allCases {
            append(board.barCount(for: player), for: player, to: .bar(player))
            append(board.borneOffCount(for: player), for: player, to: .off(player))
        }

        return CheckerLayout(slots: slots)
    }

    public mutating func apply(_ move: Move) {
        guard let movedID = pop(from: slot(for: move.source, player: move.player)) else {
            return
        }

        if case .point(let point) = move.destination {
            let destinationSlot = CheckerSlot.point(point)
            if slots[destinationSlot]?.count == 1,
               slots[destinationSlot]?.last?.player == move.player.opponent,
               let hitID = pop(from: destinationSlot) {
                slots[.bar(hitID.player), default: []].append(hitID)
            }
        }

        slots[slot(for: move.destination, player: move.player), default: []].append(movedID)
    }

    private mutating func pop(from slot: CheckerSlot) -> CheckerID? {
        guard var checkerIDs = slots[slot], let checkerID = checkerIDs.popLast() else {
            return nil
        }

        if checkerIDs.isEmpty {
            slots.removeValue(forKey: slot)
        } else {
            slots[slot] = checkerIDs
        }

        return checkerID
    }

    private func slot(for source: MoveSource, player: Player) -> CheckerSlot {
        switch source {
        case .bar:
            .bar(player)
        case .point(let point):
            .point(point)
        }
    }

    private func slot(for destination: MoveDestination, player: Player) -> CheckerSlot {
        switch destination {
        case .off:
            .off(player)
        case .point(let point):
            .point(point)
        }
    }
}
