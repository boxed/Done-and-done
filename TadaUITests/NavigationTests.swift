//
//  NavigationTests.swift
//  TadaUITests
//

import XCTest

final class NavigationTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Going back to the sidebar and then tapping a list again must open that list.
    @MainActor
    func testCanReenterListAfterGoingBack() throws {
        let app = XCUIApplication()
        app.launch()

        let addItemField = app.textFields["Add item..."]
        let backButton = app.navigationBars.buttons.element(boundBy: 0)

        // The app restores the last selected list, so we may start in the detail view.
        if addItemField.waitForExistence(timeout: 5) {
            XCTAssertTrue(backButton.exists, "Expected a back button in the detail view")
            backButton.tap()
        }

        let sidebarTitle = app.navigationBars["Lists"]
        XCTAssertTrue(sidebarTitle.waitForExistence(timeout: 5), "Expected to land on the Lists sidebar")

        let row = app.staticTexts["My List"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Expected the default list in the sidebar")
        row.tap()

        XCTAssertTrue(
            addItemField.waitForExistence(timeout: 5),
            "Tapping the list did not open it — navigation is stuck on the sidebar"
        )
    }

    /// Regression test for lists whose `id` attribute collides (nil, or duplicated by a sync
    /// merge). Requires a store seeded with at least two such lists — skipped otherwise. To seed:
    ///
    ///     C=$(xcrun simctl get_app_container <device> net.kodare.Tada data)
    ///     sqlite3 "$C/Library/Application Support/Tada.sqlite" "UPDATE ZTODOLIST SET ZID = NULL;"
    ///
    /// and run with `-parallel-testing-enabled NO` so the test uses that device, not a clone.
    @MainActor
    func testListsWithCollidingIdentitiesAreTappable() throws {
        let app = XCUIApplication()
        app.launch()

        let addItemField = app.textFields["Add item..."]
        if addItemField.waitForExistence(timeout: 5) {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.navigationBars["Lists"].waitForExistence(timeout: 5))

        let rows = app.cells
        try XCTSkipUnless(rows.count >= 2, "needs a store seeded with two colliding-identity lists")

        rows.element(boundBy: 0).tap()
        XCTAssertTrue(
            addItemField.waitForExistence(timeout: 5),
            "Tapping the first list did nothing — colliding row identities killed the tap"
        )

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Lists"].waitForExistence(timeout: 5))

        rows.element(boundBy: 1).tap()
        XCTAssertTrue(
            addItemField.waitForExistence(timeout: 5),
            "Tapping the second list did nothing"
        )
    }

    /// Repeated in-and-out navigation must keep working.
    @MainActor
    func testRepeatedBackAndForthNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        let addItemField = app.textFields["Add item..."]
        _ = addItemField.waitForExistence(timeout: 5)

        for round in 1...6 {
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(backButton.waitForExistence(timeout: 5), "round \(round): no back button")
            backButton.tap()

            XCTAssertTrue(
                app.navigationBars["Lists"].waitForExistence(timeout: 5),
                "round \(round): back did not return to the sidebar"
            )

            let row = app.staticTexts["My List"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), "round \(round): list row missing")
            row.tap()

            XCTAssertTrue(
                addItemField.waitForExistence(timeout: 5),
                "round \(round): tapping the list no longer opens it"
            )
        }
    }

    /// Leaving the list with the edge swipe (rather than the back button) must not wedge
    /// navigation: the sidebar selection has to be cleared either way.
    @MainActor
    func testSwipeBackThenTapListAgain() throws {
        let app = XCUIApplication()
        app.launch()

        let addItemField = app.textFields["Add item..."]
        if !addItemField.waitForExistence(timeout: 5) {
            app.cells.element(boundBy: 0).tap()
            XCTAssertTrue(addItemField.waitForExistence(timeout: 5), "could not open a list")
        }

        // Interactive pop: drag from the very left edge to the right.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)

        XCTAssertTrue(
            app.navigationBars["Lists"].waitForExistence(timeout: 5),
            "swipe did not return to the sidebar"
        )

        let row = app.cells.element(boundBy: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "list row missing")
        row.tap()

        XCTAssertTrue(
            addItemField.waitForExistence(timeout: 5),
            "After swiping back, tapping the list does nothing"
        )
    }

    /// Fast taps must not wedge navigation.
    @MainActor
    func testFastBackAndTapDoesNotWedge() throws {
        let app = XCUIApplication()
        app.launch()

        let addItemField = app.textFields["Add item..."]
        _ = addItemField.waitForExistence(timeout: 5)

        // Back and immediately tap the row again, with no waiting in between.
        for _ in 1...4 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.staticTexts["My List"].firstMatch.tap()
        }

        XCTAssertTrue(
            addItemField.waitForExistence(timeout: 5),
            "Navigation wedged after fast back/tap cycles"
        )
    }
}
