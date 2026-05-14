//
//  ToolCallingProtoHelpersTests.swift
//  RunAnywhere SDK
//
//  Focused tests for generated RATool* helper surface.
//

import Foundation
import XCTest

@testable import RunAnywhere

final class ToolCallingProtoHelpersTests: XCTestCase {
    func testRAToolValueRoundTripsJSONObject() throws {
        let object: [String: RAToolValue] = [
            "location": RAToolValue("San Francisco"),
            "days": RAToolValue(3),
            "includeHourly": RAToolValue(true),
            "units": .array([RAToolValue("fahrenheit"), RAToolValue("mph")])
        ]

        let json = RAToolValue.jsonString(from: object)
        let parsed = RAToolValue.parseObjectJSON(json)

        XCTAssertEqual(parsed["location"]?.string, "San Francisco")
        XCTAssertEqual(parsed["days"]?.int, 3)
        XCTAssertEqual(parsed["includeHourly"]?.bool, true)
        XCTAssertEqual(parsed["units"]?.array?.compactMap(\.string), ["fahrenheit", "mph"])
    }

    func testRAToolResultUsesGeneratedFieldsAndJSONPayload() throws {
        var result = RAToolResult()
        result.name = "get_weather"
        result.success = true
        result.result = ["temperature": RAToolValue(72)]
        result.resultJson = RAToolValue.jsonString(from: result.result)
        result.toolCallID = "call_1"
        result.callID = result.toolCallID

        XCTAssertEqual(result.name, "get_weather")
        XCTAssertEqual(result.toolCallID, "call_1")
        XCTAssertEqual(result.callID, "call_1")
        XCTAssertEqual(result.result["temperature"]?.int, 72)

        let json = RAToolValue.parseObjectJSON(result.resultJson)
        XCTAssertEqual(json["temperature"]?.int, 72)
    }

    func testToolCallingOptionsPreferGeneratedFormatEnum() {
        var options = RAToolCallingOptions.defaults()
        options.formatHint = "lfm2"
        options.format = .openaiFunctions

        XCTAssertEqual(options.resolvedFormatName, "openai")
    }
}
