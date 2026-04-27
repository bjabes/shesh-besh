import SheshBeshGame
import SwiftUI

#if canImport(SheshBeshLedger)
import SheshBeshLedger
#endif

public enum AppLaunchConfiguration {
    @MainActor
    public static func rootView(arguments: [String] = ProcessInfo.processInfo.arguments) -> RootView {
        #if DEBUG
        if arguments.contains("-uiTesting") {
            let dice = scriptedDice(from: arguments)
            return RootView(
                viewModel: MatchViewModel(
                    engine: MatchEngine(diceRoller: ScriptedDiceRoller(dice)),
                    config: .tournament(targetScore: 7),
                    opponentDelay: {}
                )
            )
        }
        #else
        _ = arguments
        #endif

        return RootView(coordinator: LedgerCoordinator(store: makeLedgerStore()))
    }

    private static func makeLedgerStore() -> any LedgerStore {
        do {
            let fileURL = try JSONLedgerStore.defaultFileURL()
            return try JSONLedgerStore(fileURL: fileURL)
        } catch {
            return InMemoryLedgerStore()
        }
    }

    #if DEBUG
    private static func scriptedDice(from arguments: [String]) -> [Int] {
        guard
            let diceFlagIndex = arguments.firstIndex(of: "-uiTestDice"),
            arguments.indices.contains(arguments.index(after: diceFlagIndex))
        else {
            return [6, 1]
        }

        let diceArgumentIndex = arguments.index(after: diceFlagIndex)
        let values = arguments[diceArgumentIndex]
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { (1...6).contains($0) }

        return values.isEmpty ? [6, 1] : values
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
    #endif
}
