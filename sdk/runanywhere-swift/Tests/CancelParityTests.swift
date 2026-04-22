//
// CancelParityTests.swift — XCTest runner for GAP 09 #7 (v3.1 Phase 5.1).
//
// Pre-condition: /tmp/cancel_input.bin (produced by cancel_producer).
//

import XCTest
@testable import RunAnywhere

final class CancelParityTests: XCTestCase {
    override func setUpWithError() throws {
        guard FileManager.default.fileExists(atPath: "/tmp/cancel_input.bin") else {
            throw XCTSkip("cancel_parity input missing at /tmp/cancel_input.bin")
        }
    }

    func testCancelParityRecordsInterruptAndWritesTrace() throws {
        let result = try CancelParity.run()
        XCTAssertGreaterThan(result.total, 0)
        XCTAssertNotNil(result.interruptOrdinal)
    }
}
