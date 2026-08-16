//
//  SyncProbeTests.swift
//  TadaUITests
//
//  Manual end-to-end sync check against real iCloud accounts. Not part of the normal suite —
//  run explicitly against a simulator that is signed in:
//
//    xcodebuild ... -parallel-testing-enabled NO \
//      -only-testing:TadaUITests/SyncProbeTests/testCreateProbeList test
//
//  `-parallel-testing-enabled NO` matters: a cloned simulator has no iCloud account.
//

import XCTest

final class SyncProbeTests: XCTestCase {

    static let probeListName = "SyncProbe"
    static let probeItemText = "hello from the phone"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Creates a list and an item, then gives the sync engine time to push them.
    @MainActor
    func testCreateProbeList() throws {
        let app = XCUIApplication()
        app.launch()

        let addItemField = app.textFields["Add item..."]
        if addItemField.waitForExistence(timeout: 5) {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.navigationBars["Lists"].waitForExistence(timeout: 10))

        app.navigationBars["Lists"].buttons["Add List"].tap()

        let alert = app.alerts["New List"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "new list dialog did not appear")
        alert.textFields.firstMatch.typeText(Self.probeListName)
        alert.buttons["Create"].tap()

        XCTAssertTrue(addItemField.waitForExistence(timeout: 10), "creating a list did not open it")
        addItemField.tap()
        addItemField.typeText(Self.probeItemText)
        addItemField.typeText("\n")

        // Let the engine send. automaticallySync schedules this on its own.
        Thread.sleep(forTimeInterval: 25)
    }

    /// Deletes the probe list. Because each list owns its record zone, this deletes the zone —
    /// the path most likely to take other data with it if it's wrong.
    @MainActor
    func testDeleteProbeList() throws {
        let app = XCUIApplication()
        app.launch()

        let addItemField = app.textFields["Add item..."]
        if addItemField.waitForExistence(timeout: 5) {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.navigationBars["Lists"].waitForExistence(timeout: 10))

        let row = app.staticTexts[Self.probeListName]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "probe list not present to delete")
        row.swipeLeft()

        let deleteButton = app.buttons["Delete"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "no delete affordance")
        deleteButton.tap()

        // Confirmation dialog
        let confirm = app.buttons["Delete"].firstMatch
        if confirm.waitForExistence(timeout: 3) {
            confirm.tap()
        }

        XCTAssertFalse(
            app.staticTexts[Self.probeListName].waitForExistence(timeout: 5),
            "list still shown after deleting it"
        )

        Thread.sleep(forTimeInterval: 25)
    }

    /// Launches and waits for the probe list to arrive from the other device.
    @MainActor
    func testProbeListArrives() throws {
        let app = XCUIApplication()
        app.launch()

        let probe = app.staticTexts[Self.probeListName]
        var found = probe.waitForExistence(timeout: 45)

        if !found {
            // Nudge it with an explicit refresh, then keep waiting.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            found = probe.waitForExistence(timeout: 60)
        }

        XCTAssertTrue(found, "the list created on the other device never arrived")
    }
}
