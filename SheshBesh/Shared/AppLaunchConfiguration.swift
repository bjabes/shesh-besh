import Foundation
import SheshBeshGame
import SwiftUI

#if canImport(SheshBeshLedger)
import SheshBeshLedger
#endif

public enum AppLaunchConfiguration {
    @MainActor
    public static func rootView(arguments: [String] = ProcessInfo.processInfo.arguments) -> RootView {
        #if DEBUG
        if let scene = uiTestScene(from: arguments) {
            return scene.rootView(arguments: arguments)
        }

        if arguments.contains("-uiTestingRootLedger") {
            return UITestScene.rivalriesHome.rootView(arguments: arguments)
        }

        if arguments.contains("-uiTesting") {
            return UITestScene.boardOpening.rootView(arguments: arguments)
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
    /// Named scenes the UI test target can route to via `-uiTestScene <name>`.
    /// Add a case here, implement `rootView(arguments:)`, and the new scene is
    /// reachable from any UI test that launches the app.
    public enum UITestScene: String, CaseIterable {
        case boardOpening = "board-opening"
        case rivalriesHome = "rivalries-home"
        case matchEndYouWon = "match-end-you-won"
        case matchEndRivalWon = "match-end-rival-won"

        @MainActor
        func rootView(arguments: [String]) -> RootView {
            switch self {
            case .boardOpening:
                let dice = scriptedDice(from: arguments)
                return RootView(
                    viewModel: MatchViewModel(
                        engine: MatchEngine(diceRoller: ScriptedDiceRoller(dice)),
                        config: .tournament(targetScore: 7),
                        opponentDelay: {}
                    )
                )

            case .rivalriesHome:
                return RootView(coordinator: seededRootLedgerCoordinator())

            case .matchEndYouWon:
                return matchEndRootView(winner: .you)

            case .matchEndRivalWon:
                return matchEndRootView(winner: .rival)
            }
        }
    }

    private static func uiTestScene(from arguments: [String]) -> UITestScene? {
        guard
            let flagIndex = arguments.firstIndex(of: "-uiTestScene"),
            arguments.indices.contains(arguments.index(after: flagIndex))
        else {
            return nil
        }
        return UITestScene(rawValue: arguments[arguments.index(after: flagIndex)])
    }

    @MainActor
    private static func seededRootLedgerCoordinator() -> LedgerCoordinator {
        let rival = Rival(
            id: UUID(uuidString: "7C48FB94-F61B-4D71-BF7F-A181713381B4")!,
            displayName: AIDifficulty.medium.rivalDisplayName,
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )
        let activeMatch = ActiveMatch(
            id: UUID(uuidString: "C74A6D96-5DB9-4774-8EA7-9192F341955E")!,
            rivalID: rival.id,
            userPlayed: .white,
            state: MatchEngine.newMatch(config: .tournament(targetScore: 1)),
            startedAt: Date(timeIntervalSinceReferenceDate: 800_000_100),
            lastUpdatedAt: Date(timeIntervalSinceReferenceDate: 800_000_200)
        )
        return LedgerCoordinator(store: InMemoryLedgerStore(rivals: [rival], activeMatches: [activeMatch]))
    }

    @MainActor
    private static func matchEndRootView(winner: MatchOutcome) -> RootView {
        let rival = Rival(
            id: UUID(uuidString: "7C48FB94-F61B-4D71-BF7F-A181713381B4")!,
            displayName: AIDifficulty.medium.rivalDisplayName,
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )

        let priorOutcomes: [MatchOutcome] = winner == .you
            ? [.rival, .rival, .you, .you, .you]
            : [.you, .you, .rival, .rival, .rival]

        var records: [MatchRecord] = []
        for (index, outcome) in priorOutcomes.enumerated() {
            let started = Date(timeIntervalSinceReferenceDate: Double(800_000_000 + index * 86_400))
            records.append(
                MatchRecord(
                    rivalID: rival.id,
                    gameIndex: index,
                    userPlayed: .white,
                    winner: outcome,
                    userScore: outcome == .you ? 7 : 4,
                    rivalScore: outcome == .you ? 3 : 7,
                    targetScore: 7,
                    startedAt: started,
                    completedAt: started.addingTimeInterval(1_800),
                    finalSnapshot: nil
                )
            )
        }

        let finalStarted = Date(
            timeIntervalSinceReferenceDate: Double(800_000_000 + priorOutcomes.count * 86_400)
        )
        let finalRecord = MatchRecord(
            rivalID: rival.id,
            gameIndex: priorOutcomes.count,
            userPlayed: .white,
            winner: winner,
            userScore: winner == .you ? 7 : 4,
            rivalScore: winner == .you ? 3 : 7,
            targetScore: 7,
            startedAt: finalStarted,
            completedAt: finalStarted.addingTimeInterval(1_800),
            finalSnapshot: nil
        )
        records.append(finalRecord)

        let coordinator = LedgerCoordinator(
            store: InMemoryLedgerStore(rivals: [rival], records: records)
        )
        coordinator.seedLedgersForUITests([
            makeLedger(rival: rival, records: records, activeMatch: nil)
        ])

        let backgroundViewModel = MatchViewModel(
            engine: MatchEngine(diceRoller: ScriptedDiceRoller([6, 1])),
            config: .tournament(targetScore: 7),
            opponentName: rival.displayName,
            opponentDelay: {}
        )

        return RootView(
            coordinator: coordinator,
            backgroundMatchViewModel: backgroundViewModel,
            completedRecordPreview: finalRecord
        )
    }

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
