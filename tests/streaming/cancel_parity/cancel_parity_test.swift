// SPDX-License-Identifier: Apache-2.0
//
// cancel_parity_test.swift — XCTest wrapper for GAP 09 #7 (v3.1 Phase 5.1).
//
// Wired into the StreamingParity test target via Package.swift. The test
// is skipped when /tmp/cancel_input.bin is not present; it is produced by
// `cmake --build build/macos-release --target cancel_producer && \
//  ./build/macos-release/tests/streaming/cancel_parity/cancel_producer`.

import XCTest

final class CancelParityTests: XCTestCase {
    override func setUpWithError() throws {
        guard FileManager.default.fileExists(atPath: CancelParity.defaultInputPath) else {
            throw XCTSkip(
                "cancel_parity input missing at \(CancelParity.defaultInputPath). " +
                "Run: cmake --build build/macos-release --target cancel_producer && " +
                "./build/macos-release/tests/streaming/cancel_parity/cancel_producer"
            )
        }
    }

    func testCancelParityRecordsInterruptAndWritesTrace() throws {
        let result = try CancelParity.run()
        XCTAssertGreaterThan(result.total, 0)
        XCTAssertNotNil(result.interruptOrdinal)
    }
}
