# TODOS

Deferred items surfaced during /plan-eng-review on 2026-04-23. Each captures what, why, pros, cons, and where to pick up.

---

## Commit-reveal dice protocol (post-V1)

**What:** Replace the deterministic-seed dice RNG with a commit-reveal protocol. Each player generates a private random seed contribution, commits a hash of it before their opponent's turn, and reveals the preimage with the turn. Combined seeds drive `GKMersenneTwisterRandomSource`.

**Why:** Current V1 dice are deterministic from `SHA256(matchID) XOR turnCounter`. Both players can compute the same seed — and therefore any motivated player can compute all future rolls. Documented as friendly-game-only in `Dice.swift`. Commit-reveal removes the caveat entirely without a server.

**Pros:** Trust model extends to strangers / money play. Removes a known limitation before it's ever exploited. Enables honest app-store positioning as "fair dice."

**Cons:** Adds round-trips to `MatchState` serialization (commit field per turn). Reveal-missing recovery needed (what if opponent drops the app mid-turn after committing?). ~1 weekend of careful work including tests.

**Context:** Rules engine in `Game/` already decouples RNG from turn logic. Swap is localized to `Dice.swift` + `MatchState` two-field addition (`myCommit`, `myReveal`). Existing schemaVersion gating handles the transition.

**Depends on / blocked by:** None. Can land any time post-V1.

---

## CloudKit ledger sync (post-V1)

**What:** Sync `LedgerStore` JSON file into CloudKit private database so head-to-head records survive reinstalls and cross over to a new iPhone.

**Why:** V1 ledger is a local JSON file in the app's Documents directory. Reinstall = wipe. "47-42 across 89 matches" is the thesis of the app; losing it because you switched phones is a brand-damaging bug-shaped UX problem.

**Pros:** Ledger persists across devices. Free with a normal Apple ID. No custom backend. Matches iOS-native expectations.

**Cons:** CloudKit private DB has its own conflict resolution and schema-migration surface. Need to handle offline-first read/write. Adds ~2-3 days of integration + QA.

**Context:** `LedgerStore` has a tight interface (`recordMatch(_:)`, `fetchRival(id:)`, `all()`). CloudKit replacement is a drop-in with a sync layer behind the same protocol. Read `Rival` and `MatchRecord` types from `Ledger/` module.

**Depends on / blocked by:** V1 ledger shape must stabilize before migrating to CloudKit schema.

---

## Drag-to-move interaction (post-V1)

**What:** Add drag gesture for moving checkers. Haptic snap when the dragged checker enters a legal destination's hit area. Drop outside any legal point = snap back to source.

**Why:** iOS-native gesture feel. Tap-source-then-tap-dest is explicit and beginner-friendly, but serious backgammon players expect to pick up and move. This is the polish that takes the UX from "works" to "feels right."

**Pros:** Matches physical-board intuition. Lower tap count per turn. Stronger "expert mode" feeling.

**Cons:** Legal-destination computation must run on gesture predicates, not post-tap — more perf pressure. Accessibility concern (drag is harder than tap for motor-impaired users — keep tap as fallback). ~2-3 days with polish.

**Context:** `BoardView` already needs legal-dest computation per tap; expand to track drag position. `Game/` exports `MoveValidator.legalDestinations(from:dice:)`.

**Depends on / blocked by:** V1 tap interaction must ship and real friends must play 10+ matches to confirm the tap model is the baseline to compare against.

---

## CI/CD (Xcode Cloud or Fastlane) (post-V1)

**What:** Automated TestFlight build + upload on push to main. Optionally run tests on PR.

**Why:** Manual `Product > Archive > Upload to App Store Connect` is fine for V1. The moment iteration rate picks up (daily-ish TestFlight builds), that friction compounds.

**Pros:** Removes a 5-10 minute manual step per build. Enforces tests passing before each TestFlight drop. Enables continuous invite-friend-to-try workflow.

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

## Secondary-screen mockups (before BoardView implementation)

**Status:** Completed on 2026-04-26. Approved manifest:
`~/.gstack/projects/bjabes-shesh-besh/designs/secondary-screens-20260424/approved.json`.

**What:** Run `/design-shotgun` on each of the four unsketched V1 screens, pick a direction, save `approved.json` alongside the Linen & Brass BoardView mockup. Screens: HomeView (0-rival empty, 1-rival hero, multi-rival scrollable), Opponent-Turn read-only board, DoubleOfferSheet ("Dan is offering a double to 4 — Take/Drop"), Match-End sheet overlay.

**Why:** BoardView has a locked visual identity (Linen & Brass) but half the V1 experience lives on the other four screens. Without mockups, engineering ships placeholders and the visual language fragments across states.

**Pros:** Coherent visual vocabulary across all V1 screens. Catches IA problems early. Reuses the BoardView brief-base so mockups calibrate to the approved palette + typography.

**Cons:** ~30 minutes of mockup + pick per screen. Some OpenAI API credit cost. Needs 4 more `/design-shotgun` runs.

**Context:** The BoardView mockup is at `~/.gstack/projects/bjabes-shesh-besh/designs/boardview-round2-20260424/variant-E.png` (Linen & Brass). Reuse that direction's palette, cube mechanics, typography hierarchy. DoubleOfferSheet is the most emotionally-loaded — invest the most iteration time there.

**Depends on / blocked by:** None. Can start immediately.

---

## DESIGN.md extraction (post-V1)

**What:** After V1 ships, run `/design-consultation` on the built-and-shipped BoardView to extract the Linen & Brass direction into a permanent `DESIGN.md` — palette tokens, typography hierarchy, cube-in-bar convention, checker identity rules, pip conventions, spacing scale, interaction language.

**Why:** DESIGN.md becomes the single source of truth for all future design decisions. V2+ features calibrate to one system; `/design-review` uses it for visual QA; designers don't have to re-infer "was that rust #A8502A or #B05330?" every time.

**Pros:** Future designs stay coherent. Onboarding a designer or AI partner becomes trivial. Enables `/design-review` automated visual audits against a stated system.

**Cons:** ~1-2 hours of distillation work.

**Context:** Extract from real shipped pixels, not from the initial mockup (painted pixels always drift from mockups). `/design-consultation` handles the structure.

**Depends on / blocked by:** V1 shipped, at least one real match played, typography rendered on-device.

---

## Full VoiceOver game-play narration (pre-App-Store)

**What:** VoiceOver support for actual backgammon gameplay — board state narration ("opponent has 5 checkers on the 19 point"), legal-move announcement on source tap ("3 legal destinations: 17-point, 15-point, bear off"), turn transitions, dice announcements, cube offer narration. Baseline a11y (44pt touch targets, Dynamic Type, reduce-motion, WCAG AA contrast) is already in V1; this is the next layer.

**Why:** V1 baseline is enough for the 2-friend TestFlight (presumed sighted). App Store submission triggers App Review scrutiny where accessibility failures are grounds for rejection or negative signal. Also: backgammon has a long history with blind players — there's a real audience.

**Pros:** App Store submission-ready. Real audience expansion (blind + low-vision players). Forces clearer information architecture (anything that's narratable is also understandable).

**Cons:** ~1-2 weeks of careful work. Game-board narration is non-trivial: needs custom `accessibilityLabel` / `accessibilityHint` / custom rotor actions on every point, checker, cube, die. Must test with VoiceOver actually running.

**Context:** `BoardView` is value-types-in, value-types-out (per eng review), so narration can be a pure function of `MatchState`. Apple's `AccessibilityLabeledPair`, `accessibilityRepresentation`, and custom rotor actions are the building blocks.

**Depends on / blocked by:** V1 baseline a11y shipped, real-device BoardView, and at least one friend willing to test with VoiceOver enabled.
