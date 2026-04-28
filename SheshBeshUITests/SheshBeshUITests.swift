import XCTest
import UIKit

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
        XCTAssertTrue(app.buttons["action-submit-turn"].exists)
        app.buttons["action-submit-turn"].tap()
        XCTAssertTrue(app.buttons["action-roll-dice"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["header-phase-title"].label, "Your turn")
    }

    @MainActor
    func testPRScreenshots() throws {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["action-opening-roll"].waitForExistence(timeout: 5))
        attachScreenshot(named: "01-opening-roll")

        app.buttons["action-opening-roll"].tap()
        XCTAssertTrue(element("die-1", in: app).waitForExistence(timeout: 2))
        attachScreenshot(named: "02-rolled-6-1")

        element("point-24", in: app).tap()
        element("point-18", in: app).tap()
        element("point-24", in: app).tap()
        element("point-23", in: app).tap()
        app.buttons["action-submit-turn"].tap()

        XCTAssertTrue(app.buttons["action-roll-dice"].waitForExistence(timeout: 4))
        attachScreenshot(named: "03-your-turn")
    }

    @MainActor
    func testRootRivalryButtonsDoNotRenderSystemBlueIcons() throws {
        let app = rootLedgerApp()
        app.launch()

        let aiButton = app.buttons["home-new-ai-rival"]
        let inviteButton = app.buttons["home-new-game-center-rival"]
        let removeAllButton = app.buttons["home-remove-all-matches"]
        let resumeButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "resume-match-")
        ).firstMatch

        XCTAssertTrue(aiButton.waitForExistence(timeout: 5))
        XCTAssertTrue(inviteButton.exists)
        XCTAssertTrue(removeAllButton.waitForExistence(timeout: 2))
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 2))

        let screenshot = XCUIScreen.main.screenshot()
        let blueControls = [
            ("Practice vs AI", aiButton),
            ("Invite Friend", inviteButton),
            ("Remove All Matches", removeAllButton),
            ("Resume match", resumeButton),
        ].filter { _, control in
            screenshotContainsSystemBlue(in: control.frame, screenshot: screenshot, appFrame: app.frame)
        }

        XCTAssertTrue(
            blueControls.isEmpty,
            "Expected themed Rivalries root controls to avoid system-blue pixels, but found blue in: \(blueControls.map(\.0).joined(separator: ", "))"
        )
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
    private func rootLedgerApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingRootLedger"]
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func screenshotContainsSystemBlue(
        in frame: CGRect,
        screenshot: XCUIScreenshot,
        appFrame: CGRect
    ) -> Bool {
        guard
            let image = UIImage(data: screenshot.pngRepresentation),
            let cgImage = image.cgImage,
            let dataProvider = cgImage.dataProvider,
            let data = dataProvider.data,
            let bytes = CFDataGetBytePtr(data)
        else {
            XCTFail("Could not inspect screenshot pixels")
            return false
        }

        let screenFrame = appFrame.isEmpty ? UIScreen.main.bounds : appFrame
        let scaleX = CGFloat(cgImage.width) / max(screenFrame.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(screenFrame.height, 1)
        let pixelFrame = frame
            .insetBy(dx: 2, dy: 2)
            .applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
            .integral
            .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard !pixelFrame.isNull, !pixelFrame.isEmpty else { return false }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        guard bytesPerPixel >= 4 else {
            XCTFail("Unexpected screenshot pixel format")
            return false
        }

        let minX = max(Int(pixelFrame.minX), 0)
        let maxX = min(Int(pixelFrame.maxX), cgImage.width)
        let minY = max(Int(pixelFrame.minY), 0)
        let maxY = min(Int(pixelFrame.maxY), cgImage.height)
        let stride = 2

        for y in Swift.stride(from: minY, to: maxY, by: stride) {
            for x in Swift.stride(from: minX, to: maxX, by: stride) {
                let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
                let (red, green, blue) = rgbComponents(
                    bytes: bytes,
                    offset: offset,
                    bitmapInfo: cgImage.bitmapInfo
                )

                if isSystemBlue(red: red, green: green, blue: blue) {
                    return true
                }
            }
        }

        return false
    }

    private func rgbComponents(
        bytes: UnsafePointer<UInt8>,
        offset: Int,
        bitmapInfo: CGBitmapInfo
    ) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let alphaInfo = CGImageAlphaInfo(rawValue: bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
        let byteOrder = bitmapInfo.intersection(CGBitmapInfo.byteOrderMask)
        switch byteOrder {
        case .byteOrder32Little:
            switch alphaInfo {
            case .premultipliedFirst, .first, .noneSkipFirst:
                return (bytes[offset + 2], bytes[offset + 1], bytes[offset])
            case .premultipliedLast, .last, .noneSkipLast:
                return (bytes[offset + 3], bytes[offset + 2], bytes[offset + 1])
            default:
                return (bytes[offset + 2], bytes[offset + 1], bytes[offset])
            }
        case .byteOrder32Big:
            switch alphaInfo {
            case .premultipliedFirst, .first, .noneSkipFirst:
                return (bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
            default:
                return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
            }
        default:
            return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
        }
    }

    private func isSystemBlue(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
        blue > 150 &&
            green > 80 &&
            red < 100 &&
            blue > red + 70 &&
            blue > green + 25
    }
}
