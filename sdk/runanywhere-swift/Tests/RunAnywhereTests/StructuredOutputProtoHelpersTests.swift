//
//  StructuredOutputProtoHelpersTests.swift
//  RunAnywhere SDK
//
//  Focused tests for generated RA* structured-output helpers.
//
//  `RAJSONSchema`/`RAJSONSchemaProperty` were deleted outright
//  (idl/structured_output.proto): `StructuredOutputOptions.schema` is now a
//  single raw JSON Schema STRING (the `oneof constraint` arm), so these
//  tests build schema text directly rather than a typed tree.
//
//  Untyped dictionaries from `JSONSerialization.jsonObject` are unavoidable
//  here — the helpers cast its return value to inspect parsed JSON in
//  assertions. The `avoid_any_type` rule is silenced for this file only.
//

// swiftlint:disable avoid_any_type

import Foundation
import XCTest

@testable import RunAnywhere

final class StructuredOutputProtoHelpersTests: XCTestCase {
    private static let objectSchemaWithAnswerAndScore = """
    {"type":"object","properties":{"answer":{"type":"string","description":"Short answer"},\
    "score":{"type":"number","minimum":0,"maximum":1}},"required":["answer"],"additionalProperties":false}
    """

    func testStructuredOutputOptionsCarrySchemaStringForCABI() throws {
        let schema = #"{"type":"array"}"#
        let options = RAStructuredOutputOptions.defaults(schema: schema)
        XCTAssertTrue(options.includeSchemaInPrompt)

        // `schema` is a plain string on the oneof `constraint` arm now — no
        // typed tree, no separate json_schema field to decode.
        let json = try parseObject(options.schema)
        XCTAssertEqual(json["type"] as? String, "array")
    }

    func testLLMRequestUsesStructuredOutputSchemaString() throws {
        let schema = Self.objectSchemaWithAnswerAndScore

        var generationOptions = RALLMGenerationOptions.defaults()
        generationOptions.structuredOutput = .defaults(schema: schema)

        let request = generationOptions.toRALLMGenerateRequest(prompt: "Return a value")
        let structuredOutput = request.options.structuredOutput
        let json = try parseObject(structuredOutput.schema)

        XCTAssertTrue(request.hasOptions)
        XCTAssertTrue(request.options.hasStructuredOutput)
        XCTAssertEqual(json["type"] as? String, "object")
        XCTAssertNotNil(json["properties"] as? [String: Any])

        let properties = try XCTUnwrap(json["properties"] as? [String: Any])
        let answerSchema = try XCTUnwrap(properties["answer"] as? [String: Any])
        XCTAssertEqual(answerSchema["type"] as? String, "string")
        XCTAssertEqual(answerSchema["description"] as? String, "Short answer")
    }

    func testStructuredOutputParseRequestUsesGeneratedOptions() {
        let schema = #"{"type":"object","properties":{"status":{"type":"string"}},"required":["status"]}"#

        let request = CppBridge.StructuredOutput.makeParseRequest(
            text: "answer {\"status\":\"ok\"}",
            schema: schema,
            requestID: "structured-test"
        )

        XCTAssertEqual(request.requestID, "structured-test")
        XCTAssertEqual(request.text, "answer {\"status\":\"ok\"}")
        XCTAssertTrue(request.options.includeSchemaInPrompt)
        XCTAssertTrue(request.options.schema.contains("\"status\""))
    }

    func testStructuredOutputParseRequestEnvelopeCarriesPromptAsText() {
        // `RAStructuredOutputRequest`/`makeGenerateRequest` were deleted
        // outright: `RAStructuredOutputParseRequest` (request_id, text,
        // options, metadata) is now the sole envelope shared by
        // parse/validate/prepare-prompt, with `text` playing the role the
        // old `prompt` field did. `preparePrompt` builds exactly this
        // envelope before dispatching to the native ABI.
        let schema = #"{"type":"array"}"#
        var request = RAStructuredOutputParseRequest()
        request.requestID = "prepare-test"
        request.text = "Return rows"
        request.options = .defaults(schema: schema)

        XCTAssertEqual(request.requestID, "prepare-test")
        XCTAssertEqual(request.text, "Return rows")
        XCTAssertTrue(request.options.schema.contains("array"))
    }

    private func parseObject(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// swiftlint:enable avoid_any_type
