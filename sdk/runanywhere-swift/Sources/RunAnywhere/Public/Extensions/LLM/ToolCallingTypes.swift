//
//  ToolCallingTypes.swift — Swift-side helpers for generated tool-calling protos.
//
//  Keep: closures (`ToolExecutor`, `RegisteredTool`), JSON bridge for
//  `argumentsJson` / `resultJson` (oneof tree), and tight RA*
//  convenience initializers/getters consumed by the example app or SDK internals.
//
//  The recursive ToolValue <-> JSON walk now lives in commons behind
//  `rac_tool_value_to_json_proto` / `rac_tool_value_from_json_proto`. Swift
//  no longer hand-rolls it.
//

import CRACommons
import Foundation

// MARK: - Tool Executor Types

/// Function type for Swift-native tool executors.
public typealias ToolExecutor = @Sendable ([String: RAToolValue]) async throws -> [String: RAToolValue]

/// A registered tool with its generated proto definition and Swift executor.
internal struct RegisteredTool: Sendable {
    let definition: RAToolDefinition
    let executor: ToolExecutor
}

// MARK: - ToolValue JSON ABI symbols

private enum ToolValueJSONABI {
    static let toJSONName = "rac_tool_value_to_json_proto"
    static let fromJSONName = "rac_tool_value_from_json_proto"

    static let toJSON = NativeProtoABI.load(toJSONName, as: NativeProtoABI.ProtoRequest.self)
    static let fromJSON = NativeProtoABI.load(fromJSONName, as: NativeProtoABI.ProtoRequest.self)
}

// MARK: - RAToolValue Helpers

public extension RAToolValue {
    init(_ value: String) { self.init(); self.stringValue = value }
    init(_ value: Int) { self.init(); self.numberValue = Double(value) }
    init(_ value: Double) { self.init(); self.numberValue = value }
    init(_ value: Bool) { self.init(); self.boolValue = value }

    static func array(_ values: [RAToolValue]) -> RAToolValue {
        var arr = RAToolValueArray(); arr.values = values
        var value = RAToolValue(); value.arrayValue = arr; return value
    }

    static func object(_ fields: [String: RAToolValue]) -> RAToolValue {
        var obj = RAToolValueObject(); obj.fields = fields
        var value = RAToolValue(); value.objectValue = obj; return value
    }

    var string: String? { if case .stringValue(let value)? = kind { return value }; return nil }
    var number: Double? { if case .numberValue(let value)? = kind { return value }; return nil }
    var int: Int? { number.map(Int.init) }
    var bool: Bool? { if case .boolValue(let value)? = kind { return value }; return nil }
    var array: [RAToolValue]? { if case .arrayValue(let value)? = kind { return value.values }; return nil }
    var object: [String: RAToolValue]? { if case .objectValue(let value)? = kind { return value.fields }; return nil }

    // JSON bridge — required by `argumentsJson` / `resultJson`.
    // Swift consumers see `[String: RAToolValue]`; the wire shape is JSON.
    // The recursive walk lives in commons; Swift only marshals bytes.

    func toJSONString(pretty: Bool = false) -> String? {
        guard let wrapper: RAToolValueJSON = try? NativeProtoABI.invoke(
            self,
            symbol: ToolValueJSONABI.toJSON,
            symbolName: ToolValueJSONABI.toJSONName,
            responseType: RAToolValueJSON.self
        ) else { return nil }
        guard pretty else { return wrapper.json }
        // Pretty-print is a presentation concern; let Foundation render the
        // already-canonical JSON text.
        guard let data = wrapper.json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: parsed,
                  options: [.prettyPrinted, .sortedKeys]) else {
            return wrapper.json
        }
        return String(data: pretty, encoding: .utf8) ?? wrapper.json
    }

    /// Parse a JSON object string into a `[String: RAToolValue]` map.
    ///
    /// Throws an `SDKException` (category `.internal`) when the input is not
    /// valid JSON, the commons bridge cannot decode the payload, or the JSON
    /// root is not an object (e.g. an array or scalar). Callers that
    /// previously relied on the silent-empty-dict fallback must now translate
    /// the thrown error into their own failure surface (e.g.
    /// `RAToolResult.success = false`).
    static func parseObjectJSON(_ json: String) throws -> [String: RAToolValue] {
        var wrapper = RAToolValueJSON(); wrapper.json = json
        let value: RAToolValue = try NativeProtoABI.invoke(
            wrapper,
            symbol: ToolValueJSONABI.fromJSON,
            symbolName: ToolValueJSONABI.fromJSONName,
            responseType: RAToolValue.self
        )
        guard case .objectValue(let obj)? = value.kind else {
            throw SDKException(
                code: .invalidInput,
                message: "ToolCall.argumentsJson must decode to a JSON object, got \(String(describing: value.kind))",
                category: .internal
            )
        }
        return obj.fields
    }

    static func jsonString(from object: [String: RAToolValue]) -> String {
        return RAToolValue.object(object).toJSONString() ?? "{}"
    }
}

// MARK: - Tool Definition Helpers

public extension RAToolParameter {
    init(
        name: String,
        type: RAToolParameterType,
        description: String,
        required: Bool = true,
        enumValues: [String] = []
    ) {
        self.init()
        self.name = name
        self.type = type
        self.description_p = description
        self.required = required
        self.enumValues = enumValues
    }
}

public extension RAToolDefinition {
    init(name: String, description: String, parameters: [RAToolParameter], category: String? = nil) {
        self.init()
        self.name = name
        self.description_p = description
        self.parameters = parameters
        if let category { self.category = category }
    }
}

// MARK: - Tool Calling Options Helpers

public extension RAToolCallingOptions {
    static func defaults() -> RAToolCallingOptions {
        var output = RAToolCallingOptions()
        output.maxToolCalls = 5
        output.autoExecute = true
        output.format = .json
        return output
    }
}
