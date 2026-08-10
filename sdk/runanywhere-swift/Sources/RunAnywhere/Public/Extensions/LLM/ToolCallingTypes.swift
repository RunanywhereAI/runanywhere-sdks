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

/// One parameter on a `ToolDefinition`, expressed as a JSON Schema property.
/// `RAToolParameter`/`RAToolParameterType` were deleted outright
/// (idl/tool_calling.proto): `ToolDefinition.parameters` is now a single raw
/// JSON Schema object STRING — the same OpenAI `parameters` / Anthropic
/// `input_schema` / MCP `inputSchema` shape every tool-calling API publishes.
/// This struct is a Swift-side convenience for building that schema; it never
/// crosses the wire on its own.
public struct ToolParameter: Sendable {
    /// JSON Schema primitive types (`"string"`, `"number"`, `"integer"`,
    /// `"boolean"`, `"array"`, `"object"`).
    public enum ParameterType: String, Sendable {
        case string
        case number
        case integer
        case boolean
        case array
        case object
    }

    public let name: String
    public let type: ParameterType
    public let description: String
    public let required: Bool
    public let enumValues: [String]

    public init(
        name: String,
        type: ParameterType,
        description: String,
        required: Bool = true,
        enumValues: [String] = []
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.enumValues = enumValues
    }

    /// This parameter's contribution to the enclosing JSON Schema `properties`
    /// object: `["type": ..., "description": ...]`, plus `"enum"` when set.
    var schemaProperty: [String: RAToolValue] {
        var property: [String: RAToolValue] = [
            "type": RAToolValue(type.rawValue),
            "description": RAToolValue(description)
        ]
        if !enumValues.isEmpty {
            property["enum"] = .array(enumValues.map { RAToolValue($0) })
        }
        return property
    }
}

public extension RAToolDefinition {
    /// Build a `ToolDefinition` from Swift-side `ToolParameter`s, serializing
    /// them into the single JSON Schema object `parameters` now carries
    /// (idl/tool_calling.proto). Mirrors the OpenAI/Anthropic/MCP tool-schema
    /// shape: `{"type": "object", "properties": {...}, "required": [...]}`.
    init(name: String, description: String, parameters: [ToolParameter], category: String? = nil) {
        self.init()
        self.name = name
        self.description_p = description
        self.parameters = RAToolDefinition.jsonSchema(for: parameters)
        if let category { self.category = category }
    }

    private static func jsonSchema(for parameters: [ToolParameter]) -> String {
        guard !parameters.isEmpty else { return "{}" }
        let properties = parameters.reduce(into: [String: RAToolValue]()) { fields, parameter in
            fields[parameter.name] = .object(parameter.schemaProperty)
        }
        let required = parameters.filter(\.required).map(\.name)
        var schema: [String: RAToolValue] = [
            "type": RAToolValue("object"),
            "properties": .object(properties)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { RAToolValue($0) })
        }
        return RAToolValue.jsonString(from: schema)
    }
}
