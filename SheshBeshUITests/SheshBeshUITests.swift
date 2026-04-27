import XCTest

final class SheshBeshUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchSmoke() throws {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["action-opening-roll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["header-score"].exists)
        XCTAssertEqual(app.staticTexts["header-score"].label, "0-0")
        XCTAssertTrue(app.staticTexts["header-phase-title"].exists)
        XCTAssertEqual(app.staticTexts["header-phase-title"].label, "Opening roll")
        XCTAssertTrue(element("board", in: app).exists)
        XCTAssertTrue(element("point-24", in: app).exists)
    }

    @MainActor
    func testDeterministicMoveSmoke() throws {
        let app = configuredApp()
        app.launch()

        app.buttons["action-opening-roll"].tap()

        XCTAssertTrue(element("die-1", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(element("die-2", in: app).exists)
        XCTAssertEqual(element("die-1", in: app).label, "Die 6")
        XCTAssertEqual(element("die-2", in: app).label, "Die 1")

        element("point-24", in: app).tap()
        element("point-18", in: app).tap()
        XCTAssertTrue(element("point-18", in: app).label.contains("1 your checker"))

        element("point-24", in: app).tap()
        element("point-23", in: app).tap()
        XCTAssertTrue(app.buttons["action-roll-dice"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["header-phase-title"].label, "Your turn")
    }

    @MainActor
    private func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-uiTestDice",
            "6,1,6,1",
        ]
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
