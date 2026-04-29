# TODOS

Deferred items surfaced during /plan-eng-review on 2026-04-23. Each captures what, why, pros, cons, and where to pick up.

---

## Commit-reveal dice protocol (post-V1)

**What:** Replace the current production dice roller with a commit-reveal protocol. Each player generates a private random seed contribution, commits a hash of it before their opponent's turn, and reveals the preimage with the turn. Combined seeds drive the roll.

**Why:** Production `MatchEngine()` currently uses `SystemDiceRoller`, which calls `Int.random(in: 1...6)`. That is fine for local play and deterministic tests can inject a scripted `DiceRolling`, but async multiplayer needs a verifiable fairness story. Commit-reveal removes the need to trust one device or a server for dice.

**Pros:** Trust model extends beyond friendly local play. Enables honest app-store positioning around fair dice. Keeps the engine testable through the existing `DiceRolling` injection point.

**Cons:** Adds round-trips to `MatchState` serialization. Reveal-missing recovery is needed (what if an opponent drops the app mid-turn after committing?). Requires careful migration for saved games if shipped after persistence.

**Context:** The rules engine is in `Packages/SheshBeshGame/Sources/SheshBeshGame`. Dice are already decoupled from turn logic through `DiceRolling` in `Dice.swift`; current state types live in `State.swift`.

**Depends on / blocked by:** None. Can land any time post-V1.

---

## CloudKit ledger sync (post-V1)

**What:** Once the V1 head-to-head ledger exists, sync it into CloudKit private database so records survive reinstalls and cross over to a new iPhone.

**Why:** The current repo has match state and app UI tests, but no ledger module yet. When the ledger is added, local-only storage will make reinstall or phone migration wipe the core "47-42 across 89 matches" history.

**Pros:** Ledger persists across devices. Free with a normal Apple ID. No custom backend. Matches iOS-native expectations.

**Cons:** CloudKit private DB has its own conflict resolution and schema-migration surface. Need to handle offline-first read/write. Adds integration and QA time after the ledger shape stabilizes.

**Context:** No `LedgerStore`, `Rival`, `MatchRecord`, or `Ledger/` module exists in this repo yet. Define a small storage protocol when the ledger lands, then make CloudKit a backing implementation behind that protocol.

**Depends on / blocked by:** V1 ledger shape must stabilize before migrating to CloudKit schema.

---

## Drag-to-move interaction (post-V1)

**What:** Add drag gesture for moving checkers. Haptic snap when the dragged checker enters a legal destination's hit area. Drop outside any legal point = snap back to source.

**Why:** iOS-native gesture feel. Tap-source-then-tap-dest is explicit and beginner-friendly, but serious backgammon players expect to pick up and move. This is the polish that takes the UX from "works" to "feels right."

**Pros:** Matches physical-board intuition. Lower tap count per turn. Stronger "expert mode" feeling.

**Cons:** Legal-destination computation must run on gesture predicates, not post-tap — more perf pressure. Accessibility concern (drag is harder than tap for motor-impaired users — keep tap as fallback). ~2-3 days with polish.

**Context:** `BoardView` already computes legal destinations for tap selection through `MatchViewModel.legalDestinations(from:)`, which filters reducer-backed legal moves from `MatchEngine.legalActions(in:)`. Expand that flow to track drag position and legal drop targets.

**Depends on / blocked by:** V1 tap interaction must ship and real friends must play 10+ matches to confirm the tap model is the baseline to compare against.

---

## TestFlight upload automation (post-V1)

**What:** Automated TestFlight build + upload on push to main.

**Why:** GitHub Actions already runs `./scripts/test.sh` on pushes and PRs to `main`. Manual `Product > Archive > Upload to App Store Connect` is fine for V1, but the moment iteration rate picks up, upload friction compounds.

**Pros:** Removes a manual build/upload step. Can require tests to pass before each TestFlight drop. Enables continuous invite-friend-to-try workflow.

**Cons:** Xcode Cloud has a per-month free tier then paid. Fastlane is free but one-time setup is fiddly (API keys, certificates, Match for cert management). ~1 day to set up either.

**Context:** Add once the app is being iterated on weekly. Not before.

**Depends on / blocked by:** V1 ships and gets regular iteration.

---

## App Store submission (post-V1)

**What:** Full App Store release. Proper screenshots at all device sizes, privacy policy URL, App Store description copy, app icon at all required sizes, App Store Connect submission.

**Why:** TestFlight is for invited testers (limit 10,000). App Store is the path to "send this link to anyone who'd want to play backgammon with one specific friend."

**Pros:** Discoverable. Shareable via App Store link. Public review signal.

**Cons:** App Review can take 24-72 hours, can reject for any reason, resubmit cycle. Adds marketing surface (screenshots, description, keywords). Needs privacy policy (even for local-only data — GameKit data handling must be disclosed).

**Context:** Hold until V1 proves the loop with the two-friends test. Then use screenshots from real matches in the ledger.

**Depends on / blocked by:** V1 success criteria met.

---

## Secondary-screen mockups (completed)

**Status:** Completed on 2026-04-26. Approved manifest:
`~/.gstack/projects/bjabes-shesh-besh/designs/secondary-screens-20260424/approved.json`.

**What:** Approved design directions exist for the four secondary V1 screens. Screens: HomeView (0-rival empty, 1-rival hero, multi-rival scrollable), Opponent-Turn read-only board, DoubleOfferSheet ("Dan is offering a double to 4 - Take/Drop"), Match-End sheet overlay.

**Why:** BoardView has a locked visual identity (Linen & Brass) but half the V1 experience lives on the other four screens. Without mockups, engineering ships placeholders and the visual language fragments across states.

**Pros:** Coherent visual vocabulary across all V1 screens. Catches IA problems early. Reuses the BoardView brief-base so mockups calibrate to the approved palette + typography.

**Cons:** Completed item; keep the manifest path below as historical design context.

**Context:** The BoardView mockup is at `~/.gstack/projects/bjabes-shesh-besh/designs/boardview-round2-20260424/variant-E.png` (Linen & Brass). Reuse that direction's palette, cube mechanics, and typography hierarchy when implementing the approved secondary screens.

**Depends on / blocked by:** None. Design exploration is complete; implementation can use the approved manifest.

---

## DESIGN.md extraction (post-V1)

**What:** After V1 ships, run `/design-consultation` on the built-and-shipped BoardView to extract the Linen & Brass direction into a permanent `DESIGN.md` — palette tokens, typography hierarchy, cube-in-bar convention, checker identity rules, pip conventions, spacing scale, interaction language.

**Why:** DESIGN.md becomes the single source of truth for all future design decisions. V2+ features calibrate to one system; `/design-review` uses it for visual QA; designers don't have to re-infer "was that rust #A8502A or #B05330?" every time.

**Pros:** Future designs stay coherent. Onboarding a designer or AI partner becomes trivial. Enables `/design-review` automated visual audits against a stated system.

**Cons:** ~1-2 hours of distillation work.

**Context:** Extract from real shipped pixels, not from the initial mockup (painted pixels always drift from mockups). `/design-consultation` handles the structure.

**Depends on / blocked by:** V1 shipped, at least one real match played, typography rendered on-device.

---

## Render the back chevron in board-opening UI test scene

**What:** Pass an `onBackToRivals` stub into the `RootView`/`BoardView` constructed by `AppLaunchConfiguration.UITestScene.boardOpening` so the header's back chevron is rendered in PR screenshots.

**Why:** The board-opening scene currently constructs the board without a back callback, so the chevron is hidden — even though the production path in `RootView` always passes the callback when navigating Rivalries → Match. PR reviewers looking at header screenshots can wrongly conclude the chevron was removed (surfaced in PR #68).

**Pros:** PR screenshots match production fidelity for header changes.

**Cons:** Trivial.

**Context:** `SheshBesh/Shared/AppLaunchConfiguration.swift:53` (the `.boardOpening` case). May need a small adjustment to the test-only `RootView`/`BoardView` initializer wiring to thread a stub callback into this construction path. `HeaderCard` in `SheshBesh/Shared/BoardView.swift:368` is the gated component.

**Depends on / blocked by:** None.

---

## Full VoiceOver game-play narration (pre-App-Store)

**What:** VoiceOver support for actual backgammon gameplay — board state narration ("opponent has 5 checkers on the 19 point"), legal-move announcement on source tap ("3 legal destinations: 17-point, 15-point, bear off"), turn transitions, dice announcements, cube offer narration. Baseline a11y (44pt touch targets, Dynamic Type, reduce-motion, WCAG AA contrast) is already in V1; this is the next layer.

**Why:** V1 baseline is enough for the 2-friend TestFlight (presumed sighted). App Store submission triggers App Review scrutiny where accessibility failures are grounds for rejection or negative signal. Also: backgammon has a long history with blind players — there's a real audience.

**Pros:** App Store submission-ready. Real audience expansion (blind + low-vision players). Forces clearer information architecture (anything that's narratable is also understandable).

**Cons:** ~1-2 weeks of careful work. Game-board narration is non-trivial: needs custom `accessibilityLabel` / `accessibilityHint` / custom rotor actions on every point, checker, cube, die. Must test with VoiceOver actually running.

**Context:** `BoardView` is value-types-in, value-types-out (per eng review), so narration can be a pure function of `MatchState`. Apple's `AccessibilityLabeledPair`, `accessibilityRepresentation`, and custom rotor actions are the building blocks.

**Depends on / blocked by:** V1 baseline a11y shipped, real-device BoardView, and at least one friend willing to test with VoiceOver enabled.
