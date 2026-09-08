import XCTest
@testable import SketchyBarToggleCore

final class StateMachineTests: XCTestCase {

    // MARK: - Basic state transitions

    func testInitialStateIsVisible() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock)
        XCTAssertEqual(sm.state, .visible)
    }

    func testMouseInTriggerZoneHidesBar() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 2)

        sm.handleMousePosition(distanceFromTop: 1) // inside trigger zone

        XCTAssertEqual(sm.state, .hidden)
        XCTAssertEqual(mock.hideCallCount, 1)
        XCTAssertEqual(mock.showCallCount, 0)
    }

    func testMouseAtExactTriggerZoneBoundaryDoesNotHide() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 2)

        sm.handleMousePosition(distanceFromTop: 2) // at boundary, not less than

        XCTAssertEqual(sm.state, .visible)
        XCTAssertEqual(mock.hideCallCount, 0)
    }

    func testMouseBelowTriggerZoneNoChange() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 2)

        sm.handleMousePosition(distanceFromTop: 100)

        XCTAssertEqual(sm.state, .visible)
        XCTAssertEqual(mock.hideCallCount, 0)
    }

    func testMouseInMenuBarZoneStaysHidden() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 2, menuBarHeight: 40)

        // Enter trigger zone to hide
        sm.handleMousePosition(distanceFromTop: 1)
        XCTAssertEqual(sm.state, .hidden)

        // Move within menu bar zone (between trigger and menuBarHeight)
        sm.handleMousePosition(distanceFromTop: 20)
        XCTAssertEqual(sm.state, .hidden)
        XCTAssertEqual(mock.showCallCount, 0)
    }

    func testMouseAtMenuBarBoundaryStaysHidden() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 2, menuBarHeight: 40)

        sm.handleMousePosition(distanceFromTop: 1) // hide
        sm.handleMousePosition(distanceFromTop: 40) // exactly at boundary

        XCTAssertEqual(sm.state, .hidden)
        XCTAssertEqual(mock.showCallCount, 0)
    }

    // MARK: - Debounce behavior

    func testMouseLeavingMenuBarStartsDebounce() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.05
        )

        sm.handleMousePosition(distanceFromTop: 1) // hide
        sm.handleMousePosition(distanceFromTop: 50) // leave menu bar zone

        // Should still be hidden — debounce hasn't fired yet
        XCTAssertEqual(sm.state, .hidden)
        XCTAssertTrue(sm.hasPendingDebounce)
    }

    func testDebounceFiresAndShowsBar() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.05,
            timerQueue: .main
        )

        sm.handleMousePosition(distanceFromTop: 1) // hide
        sm.handleMousePosition(distanceFromTop: 50) // leave menu bar zone

        let expectation = XCTestExpectation(description: "Debounce fires")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(sm.state, .visible)
            XCTAssertEqual(mock.showCallCount, 1)
            XCTAssertFalse(sm.hasPendingDebounce)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testDebounceCancelledByReenteringMenuBarZone() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.1
        )

        sm.handleMousePosition(distanceFromTop: 1)  // hide
        sm.handleMousePosition(distanceFromTop: 50) // leave — starts debounce
        XCTAssertTrue(sm.hasPendingDebounce)

        sm.handleMousePosition(distanceFromTop: 20) // re-enter menu bar zone — cancels debounce
        XCTAssertFalse(sm.hasPendingDebounce)
        XCTAssertEqual(sm.state, .hidden)
    }

    // MARK: - Repeated triggers

    func testMultipleMovesInTriggerZoneOnlyHideOnce() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 2)

        sm.handleMousePosition(distanceFromTop: 1)
        sm.handleMousePosition(distanceFromTop: 0)
        sm.handleMousePosition(distanceFromTop: 1)

        // Only the first triggers hide; after that we're in .hidden state
        XCTAssertEqual(mock.hideCallCount, 1)
    }

    func testMultipleExitsFromMenuBarDontStackDebounces() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.05
        )

        sm.handleMousePosition(distanceFromTop: 1) // hide
        sm.handleMousePosition(distanceFromTop: 50) // start debounce
        sm.handleMousePosition(distanceFromTop: 60) // still outside — should not stack

        XCTAssertTrue(sm.hasPendingDebounce)

        let expectation = XCTestExpectation(description: "Only one show call")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(mock.showCallCount, 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Full cycle

    func testFullHideShowCycle() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.05
        )

        // Start visible
        XCTAssertEqual(sm.state, .visible)

        // Mouse hits top — hide
        sm.handleMousePosition(distanceFromTop: 1)
        XCTAssertEqual(sm.state, .hidden)
        XCTAssertEqual(mock.actions, [.hide])

        // Mouse moves away — debounce then show
        sm.handleMousePosition(distanceFromTop: 50)

        let expectation = XCTestExpectation(description: "Full cycle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(sm.state, .visible)
            XCTAssertEqual(mock.actions, [.hide, .show])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Force visible

    func testForceVisibleFromHiddenState() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 2)

        sm.handleMousePosition(distanceFromTop: 1) // hide
        mock.reset()

        sm.forceVisible()
        XCTAssertEqual(sm.state, .visible)
        XCTAssertEqual(mock.showCallCount, 1)
    }

    func testForceVisibleCancelsPendingDebounce() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.1
        )

        sm.handleMousePosition(distanceFromTop: 1)  // hide
        sm.handleMousePosition(distanceFromTop: 50) // start debounce
        XCTAssertTrue(sm.hasPendingDebounce)

        sm.forceVisible()
        XCTAssertFalse(sm.hasPendingDebounce)
        XCTAssertEqual(sm.state, .visible)
    }

    // MARK: - Custom thresholds

    func testCustomTriggerZone() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 10)

        sm.handleMousePosition(distanceFromTop: 5) // inside custom zone
        XCTAssertEqual(sm.state, .hidden)

        let mock2 = MockBarController()
        let sm2 = BarStateMachine(controller: mock2, triggerZone: 10)

        sm2.handleMousePosition(distanceFromTop: 15) // outside custom zone
        XCTAssertEqual(sm2.state, .visible)
    }

    // MARK: - Click-to-restore behavior

    func testClickInHiddenStateOutsideTriggerZoneRestoresBar() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 10, menuBarHeight: 50)

        sm.handleMousePosition(distanceFromTop: 5) // hide
        XCTAssertEqual(sm.state, .hidden)
        mock.reset()

        sm.handleMouseClick(distanceFromTop: 30) // below the native menu bar strip (24)
        XCTAssertEqual(sm.state, .visible)
        XCTAssertEqual(mock.showCallCount, 1)
    }

    func testClickOnNativeMenuBarDoesNotRestore() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 5,
            menuBarHeight: 50,
            nativeMenuBarHeight: 32
        )

        sm.handleMousePosition(distanceFromTop: 1) // hide
        XCTAssertEqual(sm.state, .hidden)
        mock.reset()

        // Clicking a menu bar item: past the trigger zone, but inside the strip
        // the native menu bar occupies. SketchyBar must stay out of the way.
        sm.handleMouseClick(distanceFromTop: 12)
        XCTAssertEqual(sm.state, .hidden)
        XCTAssertEqual(mock.showCallCount, 0)
    }

    func testClickJustBelowNativeMenuBarRestores() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 5,
            menuBarHeight: 50,
            nativeMenuBarHeight: 32
        )

        sm.handleMousePosition(distanceFromTop: 1) // hide
        mock.reset()

        // A window title bar can be reached here, so the click-to-restore fix
        // for window headers still applies.
        sm.handleMouseClick(distanceFromTop: 32)
        XCTAssertEqual(sm.state, .visible)
        XCTAssertEqual(mock.showCallCount, 1)
    }

    func testClickWhileMenuOpenDoesNotRestore() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 5,
            menuBarHeight: 50,
            nativeMenuBarHeight: 32,
            isMenuOpen: { true }
        )

        sm.handleMousePosition(distanceFromTop: 1) // hide
        mock.reset()

        // Clicking an item inside an open popup menu must not slide SketchyBar
        // over it.
        sm.handleMouseClick(distanceFromTop: 200)
        XCTAssertEqual(sm.state, .hidden)
        XCTAssertEqual(mock.showCallCount, 0)
    }

    func testClickInHiddenStateInsideTriggerZoneDoesNotRestore() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 10, menuBarHeight: 50)

        sm.handleMousePosition(distanceFromTop: 5) // hide
        XCTAssertEqual(sm.state, .hidden)

        sm.handleMouseClick(distanceFromTop: 5) // click still in trigger zone (using menu bar)
        XCTAssertEqual(sm.state, .hidden)
    }

    func testClickInVisibleStateIsIgnored() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 10, menuBarHeight: 50)

        sm.handleMouseClick(distanceFromTop: 30) // click while visible
        XCTAssertEqual(sm.state, .visible)
        XCTAssertEqual(mock.showCallCount, 0) // no redundant show call
    }

    func testClickCancelsPendingDebounce() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 10,
            menuBarHeight: 50,
            debounceInterval: 0.1
        )

        sm.handleMousePosition(distanceFromTop: 5)  // hide
        sm.handleMousePosition(distanceFromTop: 60) // leave menu bar zone, starts debounce
        XCTAssertTrue(sm.hasPendingDebounce)

        sm.handleMouseClick(distanceFromTop: 60) // click while debounce pending
        XCTAssertEqual(sm.state, .visible)
        XCTAssertFalse(sm.hasPendingDebounce) // debounce cancelled, immediate restore
    }

    func testClickBelowMenuBarZoneRestoresBar() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock, triggerZone: 10, menuBarHeight: 50)

        sm.handleMousePosition(distanceFromTop: 5) // hide
        mock.reset()

        sm.handleMouseClick(distanceFromTop: 100) // click well below menu bar
        XCTAssertEqual(sm.state, .visible)
        XCTAssertEqual(mock.showCallCount, 1)
    }

    func testCustomMenuBarHeight() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 60,
            debounceInterval: 0.05
        )

        sm.handleMousePosition(distanceFromTop: 1) // hide
        sm.handleMousePosition(distanceFromTop: 50) // still within custom menu bar zone

        XCTAssertEqual(sm.state, .hidden)
        XCTAssertFalse(sm.hasPendingDebounce)
    }

    // MARK: - Popup menu gating (isMenuOpen)

    func testMenuOpenWhileHiddenSuppressesShow() {
        let mock = MockBarController()
        let menuOpen = true
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.05,
            isMenuOpen: { menuOpen }
        )

        sm.handleMousePosition(distanceFromTop: 1) // hide
        sm.handleMousePosition(distanceFromTop: 50) // leave menu bar zone, but menu is open

        XCTAssertEqual(sm.state, .hidden)
        XCTAssertFalse(sm.hasPendingDebounce)
        XCTAssertEqual(mock.showCallCount, 0)

        // Give any stray debounce a chance to fire
        let expectation = XCTestExpectation(description: "No show while menu open")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(sm.state, .hidden)
            XCTAssertEqual(mock.showCallCount, 0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testMenuClosingResumesShow() {
        let mock = MockBarController()
        var menuOpen = true
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.05,
            isMenuOpen: { menuOpen }
        )

        sm.handleMousePosition(distanceFromTop: 1) // hide
        sm.handleMousePosition(distanceFromTop: 50) // leave zone, menu open → suppressed

        menuOpen = false
        sm.handleMousePosition(distanceFromTop: 60) // next tick: menu closed → start debounce

        XCTAssertEqual(sm.state, .hidden)
        XCTAssertTrue(sm.hasPendingDebounce)

        let expectation = XCTestExpectation(description: "Show after menu closes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(sm.state, .visible)
            XCTAssertEqual(mock.showCallCount, 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testMenuOpenCancelsPendingDebounce() {
        let mock = MockBarController()
        var menuOpen = false
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.1,
            isMenuOpen: { menuOpen }
        )

        sm.handleMousePosition(distanceFromTop: 1) // hide
        sm.handleMousePosition(distanceFromTop: 50) // leave zone → debounce starts
        XCTAssertTrue(sm.hasPendingDebounce)

        menuOpen = true
        sm.handleMousePosition(distanceFromTop: 60) // menu opens → debounce cancelled
        XCTAssertFalse(sm.hasPendingDebounce)
        XCTAssertEqual(sm.state, .hidden)
    }

    func testDefaultIsMenuOpenAllowsShow() {
        let mock = MockBarController()
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.05
        )

        sm.handleMousePosition(distanceFromTop: 1) // hide
        sm.handleMousePosition(distanceFromTop: 50) // leave zone, default isMenuOpen = false

        XCTAssertEqual(sm.state, .hidden)
        XCTAssertTrue(sm.hasPendingDebounce)
    }

    // MARK: - Stale menu timeout (self-heal)

    func testDefaultStaleMenuTimeoutIsFifteenSeconds() {
        let mock = MockBarController()
        let sm = BarStateMachine(controller: mock)
        XCTAssertEqual(sm.staleMenuTimeout, 15)
    }

    func testMenuOpenSuppressesShowUntilStaleTimeout() {
        let mock = MockBarController()
        var menuOpen = true
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.05,
            staleMenuTimeout: 5,
            isMenuOpen: { menuOpen }
        )

        sm.handleMousePosition(distanceFromTop: 1, now: 0) // hide
        XCTAssertEqual(sm.state, .hidden)

        // Below the menu-bar zone with a menu open: show suppressed.
        sm.handleMousePosition(distanceFromTop: 60, now: 0)
        XCTAssertFalse(sm.hasPendingDebounce)

        // Still within the timeout window: keep suppressing.
        sm.handleMousePosition(distanceFromTop: 60, now: 4)
        XCTAssertFalse(sm.hasPendingDebounce)
        XCTAssertEqual(mock.showCallCount, 0)

        // Menu has been continuously "open" past the timeout: treat as stale,
        // allow the debounce/show to proceed.
        sm.handleMousePosition(distanceFromTop: 60, now: 5)
        XCTAssertTrue(sm.hasPendingDebounce)

        let expectation = XCTestExpectation(description: "Show after stale menu")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(sm.state, .visible)
            XCTAssertEqual(mock.showCallCount, 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testMenuClosingResetsStaleClockAndShows() {
        let mock = MockBarController()
        var menuOpen = true
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.05,
            staleMenuTimeout: 5,
            isMenuOpen: { menuOpen }
        )

        sm.handleMousePosition(distanceFromTop: 1, now: 0) // hide
        sm.handleMousePosition(distanceFromTop: 60, now: 0) // menu open, suppressed
        XCTAssertFalse(sm.hasPendingDebounce)

        menuOpen = false
        sm.handleMousePosition(distanceFromTop: 60, now: 100) // menu closed -> show normally
        XCTAssertTrue(sm.hasPendingDebounce)

        let expectation = XCTestExpectation(description: "Show after menu closes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(sm.state, .visible)
            XCTAssertEqual(mock.showCallCount, 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testStaleClockRestartsWhenMenuReopens() {
        let mock = MockBarController()
        var menuOpen = true
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.5,
            staleMenuTimeout: 5,
            isMenuOpen: { menuOpen }
        )

        sm.handleMousePosition(distanceFromTop: 1, now: 0) // hide

        // Menu open from t=0..2, then closes.
        sm.handleMousePosition(distanceFromTop: 60, now: 0)
        XCTAssertFalse(sm.hasPendingDebounce)
        menuOpen = false
        sm.handleMousePosition(distanceFromTop: 60, now: 2)
        XCTAssertTrue(sm.hasPendingDebounce) // normal show path started

        // Menu reopens at t=3 — cancels debounce and restarts the stale clock,
        // so it must not be treated as stale until 3 + 5 = 8.
        menuOpen = true
        sm.handleMousePosition(distanceFromTop: 60, now: 3)
        XCTAssertFalse(sm.hasPendingDebounce)

        sm.handleMousePosition(distanceFromTop: 60, now: 7)
        XCTAssertFalse(sm.hasPendingDebounce) // 4s since reopen — still suppressed

        sm.handleMousePosition(distanceFromTop: 60, now: 8)
        XCTAssertTrue(sm.hasPendingDebounce) // 5s since reopen — stale, show
    }

    func testStaleTimeoutDoesNotFireWhileCursorInMenuBarZone() {
        let mock = MockBarController()
        var menuOpen = true
        let sm = BarStateMachine(
            controller: mock,
            triggerZone: 2,
            menuBarHeight: 40,
            debounceInterval: 0.05,
            staleMenuTimeout: 5,
            isMenuOpen: { menuOpen }
        )

        sm.handleMousePosition(distanceFromTop: 1, now: 0) // hide
        XCTAssertEqual(sm.state, .hidden)

        // Lingering inside the menu-bar zone must never start a debounce, no
        // matter how long the menu stays open there.
        sm.handleMousePosition(distanceFromTop: 20, now: 0)
        sm.handleMousePosition(distanceFromTop: 20, now: 1000)
        XCTAssertFalse(sm.hasPendingDebounce)
        XCTAssertEqual(mock.showCallCount, 0)

        // Leaving the zone restarts the clock fresh (not stale from t=1000).
        sm.handleMousePosition(distanceFromTop: 60, now: 1001)
        XCTAssertFalse(sm.hasPendingDebounce)

        sm.handleMousePosition(distanceFromTop: 60, now: 1006)
        XCTAssertTrue(sm.hasPendingDebounce)
    }
}
