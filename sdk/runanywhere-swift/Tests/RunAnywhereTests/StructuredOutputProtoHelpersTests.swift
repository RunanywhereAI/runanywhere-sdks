//
//  StructuredOutputProtoHelpersTests.swift
//  RunAnywhere SDK
//
//  Focused tests for generated RA* structured-output helpers.
//

import Foundation
import XCTest

@testable import RunAnywhere

final class StructuredOutputProtoHelpersTests: XCTestCase {
    func testRAJSONSchemaSerializesAsJSONSchemaText() throws {
        var answer = RAJSONSchemaProperty()
        answer.type = .string
        answer.description_p = "Short answer"

        var score = RAJSONSchemaProperty()
        score.type = .number
        score.minimum = 0
        score.maximum = 1

        var schema = RAJSONSchema()
        schema.type = .object
        schema.properties = [
            "answer": answer,
            "score": score
        ]
        schema.required = ["answer"]
        schema.additionalProperties = false

        let json = try parseObject(schema.jsonSchemaString)
        XCTAssertEqual(json["type"] as? String, "object")
        XCTAssertEqual(json["required"] as? [String], ["answer"])
        XCTAssertEqual(json["additionalProperties"] as? Bool, false)

        let properties = try XCTUnwrap(json["properties"] as? [String: Any])
        let answerSchema = try XCTUnwrap(properties["answer"] as? [String: Any])
        XCTAssertEqual(answerSchema["type"] as? String, "string")
        XCTAssertEqual(answerSchema["description"] as? String, "Short answer")

        let scoreSchema = try XCTUnwrap(properties["score"] as? [String: Any])
        XCTAssertEqual(scoreSchema["type"] as? String, "number")
        XCTAssertEqual(scoreSchema["minimum"] as? Double, 0)
        XCTAssertEqual(scoreSchema["maximum"] as? Double, 1)
    }

    func testStructuredOutputOptionsCarrySchemaJsonForCABI() throws {
        var schema = RAJSONSchema()
        schema.type = .array

        let options = RAStructuredOutputOptions.defaults(schema: schema)
        XCTAssertEqual(options.mode, .jsonSchema)
        XCTAssertTrue(options.includeSchemaInPrompt)
        XCTAssertEqual(options.schema.type, .array)

        let json = try parseObject(options.jsonSchema)
        XCTAssertEqual(json["type"] as? String, "array")
    }

    func testLLMRequestUsesStructuredOutputSchemaJson() throws {
        var value = RAJSONSchemaProperty()
        value.type = .integer

        var schema = RAJSONSchema()
        schema.type = .object
        schema.properties = ["value": value]
        schema.required = ["value"]

        var generationOptions = RALLMGenerationOptions.defaults()
        generationOptions.structuredOutput = .defaults(schema: schema)

        let request = generationOptions.toRALLMGenerateRequest(prompt: "Return a value")
        let json = try parseObject(request.jsonSchema)

        XCTAssertEqual(request.responseFormat, "json_schema")
        XCTAssertEqual(json["type"] as? String, "object")
        XCTAssertNotNil(json["properties"] as? [String: Any])
    }

    func testStructuredOutputParseRequestUsesGeneratedOptions() {
        var value = RAJSONSchemaProperty()
        value.type = .string

        var schema = RAJSONSchema()
        schema.type = .object
        schema.properties = ["status": value]
        schema.required = ["status"]

        let request = CppBridge.StructuredOutput.makeParseRequest(
            text: "answer {\"status\":\"ok\"}",
            schema: schema,
            requestID: "structured-test"
        )

        XCTAssertEqual(request.requestID, "structured-test")
        XCTAssertEqual(request.text, "answer {\"status\":\"ok\"}")
        XCTAssertEqual(request.options.schema.type, .object)
        XCTAssertEqual(request.options.mode, .jsonSchema)
        XCTAssertTrue(request.options.includeSchemaInPrompt)
        XCTAssertTrue(request.options.jsonSchema.contains("\"status\""))
    }

    func testStructuredOutputPreparePromptRequestUsesGeneratedContract() {
        var schema = RAJSONSchema()
        schema.type = .array
        let options = RAStructuredOutputOptions.defaults(schema: schema)

        let request = CppBridge.StructuredOutput.makePreparePromptRequest(
            prompt: "Return rows",
            options: options,
            requestID: "prepare-test"
        )

        XCTAssertEqual(request.requestID, "prepare-test")
        XCTAssertEqual(request.prompt, "Return rows")
        XCTAssertEqual(request.options.schema.type, .array)
        XCTAssertEqual(request.options.mode, .jsonSchema)
        XCTAssertTrue(request.options.jsonSchema.contains("\"array\""))
    }

    private func parseObject(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
