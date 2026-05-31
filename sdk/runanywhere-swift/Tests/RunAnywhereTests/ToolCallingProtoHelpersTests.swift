//
//  ToolCallingProtoHelpersTests.swift
//  RunAnywhere SDK
//
//  Focused tests for generated RATool* helper surface.
//
//  Untyped dictionaries from `JSONSerialization.jsonObject` are unavoidable
//  here — the assertions cast its return value to inspect the JSON payload
//  carried by `RAToolResult.result_json`. The `avoid_any_type` rule is
//  silenced for this file only.
//

// swiftlint:disable avoid_any_type

import Foundation
import XCTest

@testable import RunAnywhere

final class ToolCallingProtoHelpersTests: XCTestCase {
    func testRAToolValueTypedInitsAndAccessorsRoundTrip() throws {
        // The JSON <-> RAToolValue round-trip is owned by commons
        // (`rac_tool_value_to_json_proto` / `rac_tool_value_from_json_proto`)
        // and is integration-tested in the commons C++ test suite. Here we
        // only verify the Swift-side typed initializers and the `.string` /
        // `.int` / `.bool` / `.array` / `.object` accessor surface, which is
        // the contract this test target can deterministically exercise
        // without the native ABI being dlsym-resolvable.
        let object: [String: RAToolValue] = [
            "location": RAToolValue("San Francisco"),
            "days": RAToolValue(3),
            "includeHourly": RAToolValue(true),
            "units": .array([RAToolValue("fahrenheit"), RAToolValue("mph")])
        ]

        XCTAssertEqual(object["location"]?.string, "San Francisco")
        XCTAssertEqual(object["days"]?.int, 3)
        XCTAssertEqual(object["includeHourly"]?.bool, true)
        XCTAssertEqual(object["units"]?.array?.compactMap(\.string), ["fahrenheit", "mph"])

        let wrapped = RAToolValue.object(object)
        let fields = try XCTUnwrap(wrapped.object)
        XCTAssertEqual(fields["location"]?.string, "San Francisco")
        XCTAssertEqual(fields["days"]?.int, 3)
        XCTAssertEqual(fields["includeHourly"]?.bool, true)
        XCTAssertEqual(fields["units"]?.array?.compactMap(\.string), ["fahrenheit", "mph"])
    }

    func testRAToolResultUsesGeneratedFieldsAndJSONPayload() throws {
        // `RAToolResult` now carries tool output exclusively as a JSON string
        // (`result_json`). The previous typed `result` map field was removed as
        // part of the proto contract simplification; callers JSON-encode the
        // payload themselves and downstream consumers decode it on read.
        var result = RAToolResult()
        result.name = "get_weather"
        result.success = true
        result.resultJson = "{\"temperature\":72}"
        result.toolCallID = "call_1"
        result.callID = result.toolCallID

        XCTAssertEqual(result.name, "get_weather")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.toolCallID, "call_1")
        XCTAssertEqual(result.callID, "call_1")

        let data = try XCTUnwrap(result.resultJson.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(parsed?["temperature"] as? Int, 72)
    }

    func testToolCallingOptionsPreferGeneratedFormatEnum() {
        // resolvedFormatName delegates the proto-enum -> hint-string mapping to
        // commons (rac_tool_call_format_hint_from_format_name), the single
        // source of truth. .openaiFunctions has no distinct runtime route, so
        // it folds to the JSON-tagged "default" (the prior hand-rolled Swift
        // table emitted "openai", a string commons never recognized).
        var options = RAToolCallingOptions.defaults()
        options.formatHint = "lfm2"
        options.format = .openaiFunctions
        XCTAssertEqual(options.resolvedFormatName, "default")

        // .pythonic routes to the LFM2 Pythonic format.
        options.format = .pythonic
        XCTAssertEqual(options.resolvedFormatName, "lfm2")
    }

    func testExecuteToolSurfacesParseFailureWhenArgumentsJsonIsInvalid() async {
        // parseObjectJSON used to silently swallow malformed JSON
        // into an empty dict, so executeTool reported success=true with no
        // arguments. Now the parse failure must propagate as success=false
        // with a non-empty error message regardless of whether the native
        // ABI symbol is resolvable in the test environment.
        let definition = RAToolDefinition(
            name: "echo",
            description: "echo tool",
            parameters: []
        )
        await RunAnywhere.registerTool(definition) { _ in [:] }
        defer { Task { await RunAnywhere.unregisterTool("echo") } }

        var toolCall = RAToolCall()
        toolCall.name = "echo"
        toolCall.argumentsJson = "{not valid json}"
        toolCall.id = "call_parse_fail"

        let result = await RunAnywhere.executeTool(toolCall)
        XCTAssertFalse(result.success)
        XCTAssertFalse(result.error.isEmpty)
    }
}

// swiftlint:enable avoid_any_type
