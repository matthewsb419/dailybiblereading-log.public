import XCTest

/// Drives the real app the way a person would: write on the Today card, answer a tracker,
/// then quit and reopen to make sure it all stuck.
final class TodayFlowTests: XCTestCase {
    func testWritingSurvivesARelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        let god = app.descendants(matching: .any)["answer-god"].firstMatch
        XCTAssertTrue(god.waitForExistence(timeout: 15), "Today card didn't appear")
        god.tap()
        let words = "Faithful \(Int.random(in: 1000...9999))"
        app.typeText(words)

        let yes = app.buttons["tracker-j-yes"]
        if yes.exists {                       // J is asked on the current day
            yes.tap()
            XCTAssertTrue(yes.isSelected)
        }
        sleep(2)                              // longer than the 0.7 s typing pause
        app.terminate()

        app.launch()
        let again = app.descendants(matching: .any)["answer-god"].firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 15))
        XCTAssertTrue((again.value as? String ?? "").contains(words), "typed text was lost: \(again.value ?? "nil")")
        if app.buttons["tracker-j-yes"].exists { XCTAssertTrue(app.buttons["tracker-j-yes"].isSelected, "J answer was lost") }
    }
}
