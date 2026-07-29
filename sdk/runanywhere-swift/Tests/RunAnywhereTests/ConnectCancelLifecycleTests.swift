//
//  ConnectCancelLifecycleTests.swift
//  RunAnywhere SDK
//
//  Focused tests for Connect cancel wire shape and idle-session lifecycle.
//

import Foundation
import XCTest

@testable import RunAnywhere

final class ConnectCancelLifecycleTests: XCTestCase {
    func testCancelRequestRoundTripsInsideClientFrame() throws {
        var cancel = RAConnectInvocationCancelRequest()
        cancel.sessionID = "session-1"
        cancel.requestID = "req-42"

        var frame = RAConnectClientFrame()
        frame.cancel = cancel

        let encoded = try frame.serializedData()
        let decoded = try RAConnectClientFrame(serializedBytes: encoded)

        guard case .cancel(let decodedCancel) = decoded.payload else {
            return XCTFail("Expected cancel payload case")
        }
        XCTAssertEqual(decodedCancel.sessionID, "session-1")
        XCTAssertEqual(decodedCancel.requestID, "req-42")
    }

    @MainActor
    func testCancelGenerationIsNoOpWhenIdle() {
        let session = ConnectSession()
        // Idle sessions must not throw and must leave status unchanged.
        session.cancelGeneration(requestID: "missing")
        session.cancelGeneration()
        XCTAssertEqual(session.status, .idle)
    }

    func testClientFramePayloadCasesIncludeCancel() {
        var frame = RAConnectClientFrame()
        frame.cancel = {
            var cancel = RAConnectInvocationCancelRequest()
            cancel.sessionID = "s"
            cancel.requestID = "r"
            return cancel
        }()
        switch frame.payload {
        case .cancel(let cancel):
            XCTAssertEqual(cancel.requestID, "r")
        default:
            XCTFail("Expected cancel payload case")
        }
    }
}
