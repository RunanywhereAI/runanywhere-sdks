// SPDX-License-Identifier: Apache-2.0
//
// parity_test.swift — GAP 09 Phase 20 streaming parity test (Swift).
// See tests/streaming/README.md.

import XCTest
@testable import RunAnywhere

final class StreamingParityTests: XCTestCase {

    // GAP 09 ship: scaffold + adapter wiring. The golden-events comparison
    // wires up alongside the first end-to-end voice-agent C++ build (Wave D).
    func test_voiceAgent_streamsExpectedEvents() async throws {
        try XCTSkipIf(true, "GAP 09 ship: parity test scaffold; golden events land in Wave D.")

        // let handle = try RunAnywhere.voiceAgent.create(...)
        // let adapter = VoiceAgentStreamAdapter(handle: handle)
        // var collected: [String] = []
        // for await event in adapter.stream() {
        //     collected.append(eventSummary(event))
        //     if collected.count >= 20 { break }
        // }
        // XCTAssertEqual(collected, expectedGoldenSequence())
    }

    func test_cancellation_yieldsNoStaleEvents() async throws {
        try XCTSkipIf(true, "GAP 09 ship: cancellation test scaffold; lands with golden events in Wave D.")
    }
}
