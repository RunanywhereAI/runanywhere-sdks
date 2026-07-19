//
//  DarwinNotificationCenterTests.swift
//  RunAnywhereAIUnitTests
//
//  DarwinNotificationCenter registration is idempotent per name (single
//  replaceable slot) instead of accumulating handlers unbounded. Headless.
//

import XCTest
@testable import RunAnywhereAI

final class DarwinNotificationCenterTests: XCTestCase {

    /// Re-registering the same name REPLACES the handler rather than appending,
    /// so handlers don't accumulate unbounded across keyboard presentations.
    func testAddObserverIsIdempotentPerName() {
        let center = DarwinNotificationCenter.shared
        let name = "com.runanywhere.test.idempotent.\(UUID().uuidString)"

        var firstRan = false
        var secondRan = false
        center.addObserver(name: name) { firstRan = true }
        center.addObserver(name: name) { secondRan = true }

        let exp = expectation(description: "handlers dispatched")
        center.fire(name: name)
        // `fire` dispatches the handler on the main queue; this fulfil is queued
        // after it (FIFO), so by the time it runs the handler has run.
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertFalse(firstRan, "the replaced handler must not run")
        XCTAssertTrue(secondRan, "only the latest handler runs")
    }
}
