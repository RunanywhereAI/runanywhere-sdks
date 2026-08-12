//
//  FinishReasonMappingTests.swift
//  RunAnywhere SDK
//
//  Pins commons RAFinishReason → public FinishReason mapping: no tool-call
//  count heuristics; UNSPECIFIED stays .unknown; ERROR stays .error.
//

@testable import RunAnywhere
import XCTest

final class FinishReasonMappingTests: XCTestCase {
    func testProtoMappingPreservesTerminalsWithoutInventingFromLocalState() {
        XCTAssertEqual(FinishReason(proto: .stop), .stop)
        XCTAssertEqual(FinishReason(proto: .stopSequence), .stop)
        XCTAssertEqual(FinishReason(proto: .length), .length)
        XCTAssertEqual(FinishReason(proto: .contextOverflow), .length)
        XCTAssertEqual(FinishReason(proto: .toolCalls), .toolCalls)
        XCTAssertEqual(FinishReason(proto: .cancelled), .cancelled)
        XCTAssertEqual(FinishReason(proto: .error), .error)
        XCTAssertEqual(FinishReason(proto: .unspecified), .unknown)
    }

    func testToolCallingResultUsesCommonsFinishReasonNotToolCallCount() {
        var withTools = RAToolCallingResult()
        withTools.toolCalls = [RAToolCall()]
        withTools.finishReason = .unspecified
        let inventedStop = GenerationResult(
            proto: withTools,
            requestId: "req",
            model: "m"
        )
        XCTAssertEqual(inventedStop.finishReason, .unknown)

        var lengthComplete = RAToolCallingResult()
        lengthComplete.isComplete = true
        lengthComplete.finishReason = .length
        let lengthResult = GenerationResult(
            proto: lengthComplete,
            requestId: "req",
            model: "m"
        )
        XCTAssertEqual(lengthResult.finishReason, .length)
    }
}
