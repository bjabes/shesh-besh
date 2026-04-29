---
name: pr-screenshots
description: Capture relevant iOS simulator screenshots for a Gammonade PR before opening it. Inspects the staged/unstaged diff (and the diff vs main if on a branch), figures out which named scenes are actually affected, runs only those scenes from the deterministic XCUITest screenshot pipeline, and surfaces the resulting image paths so they can be referenced in the PR body. Use this whenever you are about to create or update a PR in this repo, whenever the user says "ship", "open a PR", "create a PR", or asks for screenshots, before-and-afters, or visual evidence of a change. Also use proactively when the user has finished work on the iOS app (anything under SheshBesh/) and is moving toward landing it. Skip when the diff is purely engine/ledger/tests/docs with no UI surface touched.
---

# pr-screenshots

A skill for the Gammonade iOS app. The repo ships a scene-based screenshot pipeline:

- `SheshBeshUITests/PRScreenshotsTests.swift` — one `testCapture_<SceneName>` method per named scene. Each launches the app with `-uiTestScene <name>` and attaches one or more screenshots.
- `SheshBesh/Shared/AppLaunchConfiguration.swift` — defines the `UITestScene` enum and seeds the right state for each scene (deterministic dice for the board, in-memory ledger for the rivalries home, pre-completed records for match-end sheets, and so on).
- `scripts/capture-pr-screenshots.sh` — boots a simulator, runs the requested scenes, and exports PNGs into `.context/pr-screenshots/`. Honors `PR_SCREENSHOT_SCENES`, `IOS_TEST_DESTINATION`, `SCREENSHOT_DIR`, `RESULT_BUNDLE_PATH`.

Your job is to use that pipeline intelligently — pick the right scenes for the diff, run them, and report the paths.

## Mental model

A bad outcome is taking screenshots that don't show the change. They look like evidence but aren't, and they erode reviewer trust in future PR screenshots. So the question this skill answers is **"which scenes does this diff actually affect?"** Then it runs only those scenes — not all of them, and not none of them.

## Scenes currently available

Keep this list up to date with `AppLaunchConfiguration.UITestScene` and `PRScreenshotsTests`. If the diff hits an area that no scene covers, treat that as a coverage gap (see "Extending coverage" below).

| Scene | What it captures | Files where a change typically means run this scene |
|---|---|---|
| `board-opening` | The in-game board: opening-roll state, dice rolled (6-1), and post-first-turn. Three frames. | `SheshBesh/Shared/BoardView.swift`, `CheckerLayout.swift`, `MatchViewModel.swift`, dice/turn UI, `Assets.xcassets/` board/checker/dice/frame textures, `Info.plist` if it changes how the board renders |
| `rivalries-home` | The rivalries home screen with one seeded AI rival and one resumable match. | `SheshBesh/Shared/HomeView.swift`, `RootView.swift` (when changing the home branch), `LedgerCoordinator.swift`, `GameCenterEnvelope.swift`/`GameCenterSupport.swift` if they affect the home UI |
| `match-end-you-won` | The post-game sheet over the board, "You won" variant. | `SheshBesh/Shared/MatchEndSheet.swift`, sheet theme/typography helpers, anything that materially changes the "you won" header, ledger numbers, or streak rendering |
| `match-end-rival-won` | Same sheet, "Rival won" variant. Capture this when a change affects the headline string, the rival name styling, or anything where the "rival" branch differs from the "you" branch. | Same as above; usually run alongside `match-end-you-won` rather than instead of it |

## Workflow

### 1. Read the diff

Determine the scope of changes. Prefer the branch-vs-main diff when on a feature branch:

```bash
# If on a feature branch:
git diff --name-only main...HEAD

# Otherwise (working on main, or no branch yet), include working tree:
git diff --name-only HEAD
git status --porcelain
```

If both yield nothing, there's nothing to screenshot — say so and stop.

### 2. Pick scenes

Walk the file list and accumulate a set of scene names per the table above. A few patterns worth knowing:

- A change to `MatchEndSheet.swift` almost always means **both** match-end scenes (`match-end-you-won` AND `match-end-rival-won`) — the sheet branches on `record.winner`, so the two variants exercise different code paths.
- A change in `Assets.xcassets/` only matters if the asset is actually rendered by a scene. Assets used only by `SplashView`, GameCenter, or other uncovered surfaces don't trigger any scene.
- Pure logic / engine / ledger changes (`Packages/SheshBeshGame/`, `Packages/SheshBeshLedger/`, `SheshBeshTests/`) trigger no scenes — skip screenshots entirely.
- `SheshBeshUITests/`, `scripts/`, `*.md`, `.github/workflows/*.yml` — no scenes.
- Ambiguous app-level files (`SheshBeshMain.swift`, `Info.plist`, `AppLaunchConfiguration.swift`, entitlements) — read the actual diff. If the change steers toward a specific surface, pick that surface's scene; if it's pure plumbing, no scenes.

When in doubt, read the diff for that file (not just the path). A one-line tweak that only renames a private helper changes nothing on screen; running scenes for it is wasted time.

### 3. Decide and announce

Choose one of three outcomes and tell the user **before** doing it (each scene takes ~10–25s of simulator time — don't surprise people):

- **Run a specific subset of scenes.** State which scenes and which files drove the choice. Example: "BoardView.swift and MatchEndSheet.swift changed; running `board-opening`, `match-end-you-won`, `match-end-rival-won`."
- **Skip with reason.** State why. Example: "Diff is `Packages/SheshBeshGame/Sources/...` only; no UI affected — skipping screenshots."
- **Run a subset and flag a gap.** Some files are covered by scenes, others touch a surface no scene currently captures (e.g. `SplashView.swift`). Run the covered scenes and explicitly say which surfaces won't be in the output. Don't silently produce a partial set.

### 4. Run the script

Pass the chosen scenes via `PR_SCREENSHOT_SCENES`. Unset it only if you want all scenes (which is rarely the right choice — this PR almost certainly didn't change every surface):

```bash
PR_SCREENSHOT_SCENES=board-opening,match-end-you-won ./scripts/capture-pr-screenshots.sh
```

Capture stdout — the script prints the resulting PNG paths.

If the script fails:
- **xcodebuild can't find a simulator** — check `xcrun simctl list devices available | grep iPhone`. The default destination is `platform=iOS Simulator,name=iPhone 17,OS=latest`. Override via `IOS_TEST_DESTINATION` if needed. Don't silently fall back; tell the user.
- **A UI test fails** — that's a real bug surfaced by the screenshot pipeline. Read the failure, share it, let the user decide whether the PR is even ready.
- **Unknown scene name** — the script will exit with a list of known scenes. Either pick a known one or extend coverage (below).
- **No attachments exported** — usually means the test ran but `attachScreenshot(named:)` calls didn't fire. Check the test method.

### 5. Report

Emit a short summary the PR-creation step can use directly:

- The list of PNG paths.
- Optionally, one short line per screenshot describing the moment captured (the file names already encode this — `match-end-you-won.png` is self-explanatory).
- Any coverage gaps you flagged in step 3.

This skill produces the screenshots and surfaces the paths — it does not push to git, edit the PR body, or upload anywhere. The /ship flow or the user owns that step.

## Extending coverage

If the diff hits a real UI surface that no scene currently covers (e.g. `SplashView.swift`, `DoubleOfferSheet`, GameCenter pickers), the path forward is:

1. Add a case to `AppLaunchConfiguration.UITestScene` in `SheshBesh/Shared/AppLaunchConfiguration.swift`. Implement its `rootView(arguments:)` so the app launches directly into that surface — typically by seeding state and using the existing `RootView` debug initializers, or by adding a new debug initializer if the surface needs one.
2. Add a `testCapture_<SceneName>` method to `SheshBeshUITests/PRScreenshotsTests.swift` that launches with `-uiTestScene <new-scene>` and attaches a screenshot.
3. Add the scene to the `SCENE_NAMES`/`test_name_for_scene` mapping in `scripts/capture-pr-screenshots.sh`.
4. Update the table in this SKILL.md.

This is real work — confirm scope with the user before doing it. Don't add scenes speculatively.

## What this skill is NOT

- It is not a general "test the iOS app" runner — for that, use `scripts/test.sh` or `xcodebuild test`.
- It does not push to git, create PRs, or comment on GitHub. It produces screenshots and a path list. The /ship flow or the user owns the PR.
- It is not a replacement for design review. Screenshots show *what changed*, not *whether the change is good*.

## Why this matters

Screenshots that genuinely show the change save reviewers minutes of pulling the branch and running the simulator themselves. Screenshots that don't show the change waste reviewer attention and erode trust in future screenshots. Picking the right subset of scenes — instead of always running everything or always skipping — is the whole point of this skill.
