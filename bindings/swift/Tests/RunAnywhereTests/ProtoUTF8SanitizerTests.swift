//
//  ProtoUTF8SanitizerTests.swift
//  RunAnywhere SDK
//
//  Verifies that `ProtoUTF8Sanitizer` repairs invalid UTF-8 in the `string`
//  fields of a serialized RAGResult so SwiftProtobuf can decode a payload that
//  the C++ pipeline produced and that Android (Wire) / Flutter (dart-protobuf)
//  already decode leniently. Regression guard for the iOS-only
//  `BinaryDecodingError.invalidUTF8` ("error 2") RAG-query decode failure.
//

import Foundation
import SwiftProtobuf
import XCTest

@testable import RunAnywhere

final class ProtoUTF8SanitizerTests: XCTestCase {

    // MARK: - Helpers

    /// Builds an `RARAGResult` with deliberately invalid UTF-8 in its text
    /// fields by injecting raw bytes that protobuf serializes but SwiftProtobuf
    /// rejects on decode. We construct the wire bytes by hand because the typed
    /// `RARAGResult` cannot hold invalid UTF-8 in a Swift `String`.
    private func makeRAGResultBytes(
        answer: [UInt8],
        contextUsed: [UInt8],
        chunkText: [UInt8]
    ) -> Data {
        func tag(_ field: Int, _ wireType: Int) -> UInt8 { UInt8((field << 3) | wireType) }

        // retrieved_chunks[0] = RAGSearchResult { text(2) = chunkText }
        var chunk: [UInt8] = []
        chunk.append(tag(2, 2))
        chunk.append(UInt8(chunkText.count))
        chunk += chunkText

        var message: [UInt8] = []
        // answer (field 1, string)
        message.append(tag(1, 2)); message.append(UInt8(answer.count)); message += answer
        // retrieved_chunks (field 2, repeated message)
        message.append(tag(2, 2)); message.append(UInt8(chunk.count)); message += chunk
        // context_used (field 3, string)
        message.append(tag(3, 2)); message.append(UInt8(contextUsed.count)); message += contextUsed
        // retrieval_time_ms (field 4, varint) = 300 — a scalar that must survive
        message.append(tag(4, 0)); message.append(0xAC); message.append(0x02)
        return Data(message)
    }

    // MARK: - Tests

    func testStrictDecodeRejectsInvalidUTF8() throws {
        // Sanity check the premise: SwiftProtobuf hard-fails on invalid UTF-8.
        let bytes = makeRAGResultBytes(
            answer: Array("Answer ".utf8) + [0xE2, 0x82],   // truncated euro sign
            contextUsed: Array("context".utf8),
            chunkText: Array("chunk".utf8)
        )
        XCTAssertThrowsError(try RARAGResult(serializedBytes: bytes)) { error in
            XCTAssertEqual(error as? BinaryDecodingError, .invalidUTF8)
        }
    }

    func testRepairMakesInvalidUTF8RAGResultDecodable() throws {
        let bytes = makeRAGResultBytes(
            answer: Array("Answer ".utf8) + [0xE2, 0x82],        // truncated 3-byte
            contextUsed: Array("ctx ".utf8) + [0xF0, 0x9F],      // truncated 4-byte emoji
            chunkText: Array("snippet ".utf8) + [0x80]           // lone continuation byte
        )

        guard let shape = ProtoUTF8Sanitizer.shape(forMessageNamed: "runanywhere.v1.RAGResult") else {
            return XCTFail("RAGResult shape must be registered")
        }
        guard let repaired = ProtoUTF8Sanitizer.repair(bytes, as: shape) else {
            return XCTFail("repair returned nil for well-formed (but invalid-UTF-8) bytes")
        }

        // The repaired bytes must now decode strictly, and the substituted
        // U+FFFD must be present in each scrubbed field.
        let result = try RARAGResult(serializedBytes: repaired)
        XCTAssertTrue(result.answer.hasPrefix("Answer "))
        XCTAssertTrue(result.answer.contains("\u{FFFD}"))
        XCTAssertTrue(result.contextUsed.contains("\u{FFFD}"))
        XCTAssertEqual(result.retrievalTimeMs, 300, "scalar fields must be preserved")
        XCTAssertEqual(result.retrievedChunks.count, 1)
        XCTAssertTrue(result.retrievedChunks[0].text.hasPrefix("snippet "))
        XCTAssertTrue(result.retrievedChunks[0].text.contains("\u{FFFD}"))
    }

    func testRepairPreservesValidUTF8Verbatim() throws {
        // Valid multibyte strings (incl. ones SwiftProtobuf accepts) must be
        // reproduced byte-for-byte — repair must never corrupt good data.
        let answer = Array("héllo ✓ café 🚀".utf8)
        let bytes = makeRAGResultBytes(
            answer: answer,
            contextUsed: Array("plain".utf8),
            chunkText: Array("chunk".utf8)
        )

        guard let shape = ProtoUTF8Sanitizer.shape(forMessageNamed: "runanywhere.v1.RAGResult") else {
            return XCTFail("RAGResult shape must be registered")
        }
        guard let repaired = ProtoUTF8Sanitizer.repair(bytes, as: shape) else {
            return XCTFail("repair returned nil for valid bytes")
        }
        XCTAssertEqual(repaired, bytes, "valid input must be reproduced verbatim")

        let result = try RARAGResult(serializedBytes: repaired)
        XCTAssertEqual(result.answer, "héllo ✓ café 🚀")
    }

    func testUnregisteredMessageTypeHasNoShape() {
        // Only RAGResult is registered; other messages keep the strict error so
        // the lenient path stays scoped to the proven-failing type.
        XCTAssertNil(ProtoUTF8Sanitizer.shape(forMessageNamed: "runanywhere.v1.RAGStatistics"))
        XCTAssertNil(ProtoUTF8Sanitizer.shape(forMessageNamed: "runanywhere.v1.LLMGenerationResult"))
    }

    func testRepairReturnsNilForMalformedBytes() {
        guard let shape = ProtoUTF8Sanitizer.shape(forMessageNamed: "runanywhere.v1.RAGResult") else {
            return XCTFail("RAGResult shape must be registered")
        }
        // Length-delimited field claims 50 bytes but only 3 follow: a genuinely
        // truncated/malformed buffer must NOT be silently "repaired"; repair
        // returns nil so the caller surfaces the real decode error.
        let truncated = Data([UInt8((1 << 3) | 2), 50, 0x41, 0x42, 0x43])
        XCTAssertNil(ProtoUTF8Sanitizer.repair(truncated, as: shape))
    }
}
