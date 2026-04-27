import XCTest

@MainActor
final class SheshBeshUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-uiTestDice",
            "6,1,6,1",
        ]
    }

    func testLaunchSmoke() throws {
        app.launch()

        XCTAssertTrue(app.buttons["action-opening-roll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["header-score"].exists)
        XCTAssertEqual(app.staticTexts["header-score"].label, "0-0")
        XCTAssertTrue(app.staticTexts["header-phase-title"].exists)
        XCTAssertEqual(app.staticTexts["header-phase-title"].label, "Opening roll")
        XCTAssertTrue(element("board").exists)
        XCTAssertTrue(element("point-24").exists)
    }

    func testDeterministicMoveSmoke() throws {
        app.launch()

        app.buttons["action-opening-roll"].tap()

        XCTAssertTrue(element("die-1").waitForExistence(timeout: 2))
        XCTAssertTrue(element("die-2").exists)
        XCTAssertEqual(element("die-1").label, "Die 6")
        XCTAssertEqual(element("die-2").label, "Die 1")

        element("point-24").tap()
        element("point-18").tap()
        XCTAssertTrue(element("point-18").label.contains("1 your checker"))

        element("point-24").tap()
        element("point-23").tap()
        XCTAssertTrue(app.buttons["action-roll-for-dan"].waitForExistence(timeout: 2))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
