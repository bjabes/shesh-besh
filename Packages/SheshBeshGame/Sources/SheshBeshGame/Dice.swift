public protocol DiceRolling: Sendable {
    func rollDie() -> Int
}

public struct SystemDiceRoller: DiceRolling {
    public init() {}

    public func rollDie() -> Int {
        Int.random(in: 1...6)
    }
}

public struct DiceRoll: Codable, Equatable, Hashable, Sendable {
    public let die1: Int
    public let die2: Int

    public init(die1: Int, die2: Int) throws {
        guard (1...6).contains(die1), (1...6).contains(die2) else {
            throw MatchEngineError.invalidDiceValue
        }
        self.die1 = die1
        self.die2 = die2
    }

    internal init(uncheckedDie1 die1: Int, die2: Int) {
        self.die1 = die1
        self.die2 = die2
    }

    public var isDouble: Bool {
        die1 == die2
    }

    public var playableDice: [Int] {
        isDouble ? Array(repeating: die1, count: 4) : [die1, die2]
    }
}
