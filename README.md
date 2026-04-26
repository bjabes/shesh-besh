# Shesh Besh

An iOS backgammon game repo. The current implementation has a pure Swift rules
engine plus an early SwiftUI app shell with a Linen & Brass portrait board.

## Requirements

- Xcode 26.4+
- Apple Swift 6.3+
- iOS 17+
- Swift Testing

## Repository Layout

```text
shesh-besh/
  Package.swift              # repo-root entry point for swift build/test
  Packages/
    SheshBeshGame/
      Package.swift
      Sources/SheshBeshGame/
      Tests/SheshBeshGameTests/

  SheshBesh.xcodeproj      # iOS SwiftUI app project
  SheshBesh/
    App/                   # @main app entry
    Shared/                # SwiftUI views + app view models
  SheshBeshTests/          # app-level tests
  SheshBeshUITests/        # future UI tests
```

The game engine remains isolated as a local Swift package so app UI can depend
on it without mixing presentation code into the rules layer. The root package
also exposes `SheshBeshApp` for app-level tests and a small `SheshBesh`
SwiftUI executable for local compiler coverage.

## Building and Running Tests

```sh
swift build
swift test
```

To build the iOS app target from the checked-in Xcode project:

```sh
xcodebuild -project SheshBesh.xcodeproj -target SheshBesh -configuration Debug -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

The nested package remains usable directly with `swift build --package-path
Packages/SheshBeshGame` and `swift test --package-path Packages/SheshBeshGame`.

## What The Engine Implements

`SheshBeshGame` implements standard tournament match backgammon:

- standard initial board setup
- opening roll with reroll on ties
- legal checker movement
- bar entry before other moves
- blocked points and hits
- doubles as four playable moves
- maximum dice usage
- higher-die rule when only one die can be played
- bearing off, including oversize bear-off
- automatic pass when no legal move exists
- single, gammon, and backgammon wins
- doubling cube offers, takes, drops, ownership, and redoubles
- Crawford game handling
- resignation offers for single/gammon/backgammon
- match scoring and match completion

White moves from point `24` toward point `1`. Black moves from point `1`
toward point `24`.

## Core Types

Import the engine from app code with:

```swift
import SheshBeshGame
```

The main public value types are:

- `MatchState`: complete match state, including score, game, Crawford status,
  and completion.
- `GameState`: current board, phase, cube, and Crawford flag.
- `Board`: points, bar counts, and borne-off counts.
- `PointID`: validated point identifier from `1...24`.
- `Player`: `.white` or `.black`.
- `DiceRoll`: two dice plus playable dice expansion for doubles.
- `Move` and `MoveSequence`: checker moves and generated legal sequences.
- `CubeState`: cube value and owner.
- `MatchConfig`: match target and rule toggles.
- `MatchAction`: reducer action applied through `MatchEngine`.

State models are value types and support `Codable`, `Equatable`, and `Sendable`
where appropriate.

## Basic Usage

Create a match and apply actions through `MatchEngine`:

```swift
import SheshBeshGame

let engine = MatchEngine()
var state = MatchEngine.newMatch(config: .tournament(targetScore: 5))

state = try engine.apply(action: .rollOpeningDice, to: state)

let legalActions = MatchEngine.legalActions(in: state)
if let moveAction = legalActions.first(where: {
    if case .move = $0 { true } else { false }
}) {
    state = try engine.apply(action: moveAction, to: state)
}
```

`MatchEngine.legalActions(in:)` is the safest source of UI actions. It exposes
rolls, cube decisions, resignations, next-game transitions, legal checker moves,
and explicit pass actions for blocked turns.

## SwiftUI App Surface

`SheshBesh/Shared/MatchViewModel.swift` is the app bridge over `MatchEngine`.
It owns the current `MatchState`, exposes reducer-backed legal actions, computes
pip counts, and applies checker moves through the engine.

`SheshBesh/Shared/BoardView.swift` renders the approved Linen & Brass direction:
portrait board, linen texture, coffee frame, rust/cream checker identities,
brass cube in the bar well, pip dice, header pip counts, and thumb-zone actions.
Views still render directly from value-type engine state.

## Rendering Board State

`Board` is UI-agnostic. A SwiftUI board can map points however it likes:

```swift
let board = viewModel.state.game.board
let pointID = PointID(rawValue: 24)!
let point = board.point(pointID)

switch point.owner {
case .white:
    // render point.count white checkers
case .black:
    // render point.count black checkers
case nil:
    // render an empty point
}
```

Useful board queries:

```swift
board.barCount(for: .white)
board.borneOffCount(for: .black)
board.occupiedPoints(for: .white)
board.totalCheckers(for: .black)
```

To render possible checker destinations for a selected source, ask the reducer
for legal move actions and filter the moves:

```swift
let legalMoves: [Move] = MatchEngine.legalActions(in: viewModel.state).compactMap {
    if case .move(let move) = $0 { move } else { nil }
}
```

## Persistence

`MatchState` is `Codable`, so the app can save and restore snapshots:

```swift
let data = try JSONEncoder().encode(viewModel.state)
let restored = try JSONDecoder().decode(MatchState.self, from: data)
```

The package does not choose a persistence store. The app can put encoded state
in a file, SwiftData, CloudKit, or a multiplayer transport.

## Deterministic Dice In Tests

Production `MatchEngine()` uses `SystemDiceRoller`. Tests can inject a scripted
roller:

```swift
final class ScriptedDiceRoller: DiceRolling, @unchecked Sendable {
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

let engine = MatchEngine(diceRoller: ScriptedDiceRoller([6, 2, 3, 1]))
```

This keeps reducer tests deterministic without baking test-only behavior into
the engine.

## Non-Goals For This Package

The engine does not include:

- SwiftUI, UIKit, or board rendering
- GameKit or networking
- CloudKit or local persistence stores
- animations, gestures, sounds, or haptics
- AI opponents
- commit-reveal dice
- money-game-only rules such as Jacoby or beavers

Commit-reveal dice is tracked as a post-V1 item in `TODOS.md`.
