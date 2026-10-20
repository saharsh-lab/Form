import XCTest

/// End-to-end flows against a fresh in-memory store (`-UITestInMemoryStore`),
/// so runs never touch real data and always start from a first launch.
final class FormUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore"]
        app.launch()
    }

    func testEveryTabOpens() {
        let tabs = app.tabBars.firstMatch
        for (tab, title) in [("Train", "Train"), ("Nutrition", "Nutrition"), ("Progress", "Progress"), ("Today", "Today")] {
            tabs.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(tab) tab should show its screen")
        }
    }

    func testLogBodyWeightFromToday() {
        app.buttons["Log weight"].firstMatch.tap()
        let field = app.textFields.matching(NSPredicate(format: "label BEGINSWITH %@", "Body weight in")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("72.4")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "72.4")).firstMatch.waitForExistence(timeout: 5),
                      "Today shows the weight that was just saved")
    }

    func testStartAndDiscardAnEmptyWorkout() {
        app.tabBars.buttons["Train"].tap()
        let start = app.buttons["Start empty workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let discard = app.buttons["Discard workout"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "the active workout opens full screen")
        discard.tap()
        app.sheets.buttons["Discard workout"].firstMatch.tap()

        XCTAssertTrue(app.buttons["Start empty workout"].waitForExistence(timeout: 5), "back on Train with no workout running")
    }

    func testSettingsShowsDataControls() {
        app.navigationBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Export data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete all data"].exists)
    }
}
