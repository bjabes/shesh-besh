import XCTest

/// One method per "scene" the PR screenshot pipeline can capture.
///
/// To add a new scene:
///   1. Add a case to `AppLaunchConfiguration.UITestScene` and implement its
///      `rootView(arguments:)` so the app launches directly into the desired
///      surface.
///   2. Add a `testCapture_<SceneName>` method here that launches with that
///      scene and attaches a screenshot named the same as the scene's raw
///      value.
///   3. Add the scene name to the SCREENSHOT_SCENE_TESTS map in
///      `scripts/capture-pr-screenshots.sh`.
///
/// `scripts/capture-pr-screenshots.sh` runs every method in this class by
/// default. Pass `PR_SCREENSHOT_SCENES=board-opening,match-end-you-won` to
/// run a subset.
final class PRScreenshotsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Scenes

    @MainActor
    func testCapture_BoardOpening() throws {
        let app = sceneApp("board-opening", extraArguments: ["-uiTestDice", "6,1,6,1"])
        app.launch()

        XCTAssertTrue(app.buttons["action-opening-roll"].waitForExistence(timeout: 5))
        attachScreenshot(named: "board-opening-pre-roll")

        app.buttons["action-opening-roll"].tap()
        XCTAssertTrue(element("die-1", in: app).waitForExistence(timeout: 5))
        attachScreenshot(named: "board-opening-rolled-6-1")

        element("point-24", in: app).tap()
        element("point-18", in: app).tap()
        element("point-24", in: app).tap()
        element("point-23", in: app).tap()
        app.buttons["action-submit-turn"].tap()

        XCTAssertTrue(app.buttons["action-roll"].waitForExistence(timeout: 4))
        attachScreenshot(named: "board-opening-after-first-turn")
    }

    @MainActor
    func testCapture_BoardOpponentSkip() throws {
        let app = sceneApp("board-opponent-skip")
        app.launch()

        // The AI rolls into a closed-out home and auto-skips. Wait for the
        // local roll-dice button so we know the skip has finished and the
        // tray's previous-roll slot is rendered.
        XCTAssertTrue(app.buttons["action-roll-dice"].waitForExistence(timeout: 5))
        attachScreenshot(named: "board-opponent-skip")
    }

    @MainActor
    func testCapture_RivalriesHome() throws {
        let app = sceneApp("rivalries-home")
        app.launch()

        XCTAssertTrue(app.buttons["home-new-ai-rival"].waitForExistence(timeout: 5))
        attachScreenshot(named: "rivalries-home")
    }

    @MainActor
    func testCapture_MatchEndYouWon() throws {
        let app = sceneApp("match-end-you-won")
        app.launch()
        captureMatchEndSheet(in: app, named: "match-end-you-won")
    }

    @MainActor
    func testCapture_MatchEndRivalWon() throws {
        let app = sceneApp("match-end-rival-won")
        app.launch()
        captureMatchEndSheet(in: app, named: "match-end-rival-won")
    }

    // MARK: Helpers

    @MainActor
    private func sceneApp(_ scene: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestScene", scene] + extraArguments
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func captureMatchEndSheet(in app: XCUIApplication, named name: String) {
        // The match-end sheet presents over the board. Wait for its dismiss
        // button so we know it is fully laid out before grabbing the frame.
        let dismiss = app.buttons.matching(identifier: "Back home").firstMatch
        XCTAssertTrue(
            dismiss.waitForExistence(timeout: 6),
            "Match-end sheet did not appear within 6s for scene named \(name)"
        )
        attachScreenshot(named: name)
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
