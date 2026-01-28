//
//  ToolCallingTypes.swift
//  RunAnywhere SDK
//
//  Type definitions for Tool Calling functionality.
//  Allows LLMs to request external actions (API calls, device functions, etc.)
//
//  Mirrors sdk/runanywhere-react-native ToolCallingTypes.ts
//

import Foundation

// MARK: - Tool Value (Type-safe JSON representation)

/// A type-safe representation of JSON values for tool arguments and results.
/// Avoids using `Any` while supporting all JSON types.
public enum ToolValue: Sendable, Codable, Equatable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([ToolValue])
    case object([String: ToolValue])
    case null

    // MARK: - Convenience Initializers

    /// Create from any supported Swift type
    public init(_ value: String) { self = .string(value) }
    public init(_ value: Int) { self = .number(Double(value)) }
    public init(_ value: Double) { self = .number(value) }
    public init(_ value: Bool) { self = .bool(value) }

    // MARK: - Value Extraction

    public var stringValue: String? {
        if case .string(let val) = self { return val }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let val) = self { return val }
        return nil
    }

    public var intValue: Int? {
        if case .number(let val) = self { return Int(val) }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let val) = self { return val }
        return nil
    }

    public var arrayValue: [ToolValue]? {
        if case .array(let val) = self { return val }
        return nil
    }

    public var objectValue: [String: ToolValue]? {
        if case .object(let val) = self { return val }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([ToolValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: ToolValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let val): try container.encode(val)
        case .number(let val): try container.encode(val)
        case .bool(let val): try container.encode(val)
        case .array(let val): try container.encode(val)
        case .object(let val): try container.encode(val)
        case .null: try container.encodeNil()
        }
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .string(let val): return "\"\(val)\""
        case .number(let val): return val.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(val))" : "\(val)"
        case .bool(let val): return val ? "true" : "false"
        case .array(let val): return "[\(val.map(\.description).joined(separator: ", "))]"
        case .object(let val):
            let pairs = val.map { "\"\($0.key)\": \($0.value.description)" }
            return "{\(pairs.joined(separator: ", "))}"
        case .null: return "null"
        }
    }

    // MARK: - JSON Conversion

    /// Convert to JSON string
    public func toJSONString(pretty: Bool = false) -> String? {
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = .prettyPrinted }
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Parse from JSON string
    public static func fromJSONString(_ json: String) -> ToolValue? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ToolValue.self, from: data)
    }
}

// MARK: - Parameter Types

/// Supported parameter types for tool arguments
public enum ToolParameterType: String, Codable, Sendable {
    case string
    case number
    case boolean
    case object
    case array
}

/// A single parameter definition for a tool
public struct ToolParameter: Sendable {

    /// Parameter name
    public let name: String

    /// Data type of the parameter
    public let type: ToolParameterType

    /// Human-readable description
    public let description: String

    /// Whether this parameter is required
    public let required: Bool

    /// Allowed values (for enum-like parameters)
    public let enumValues: [String]?

    public init(
        name: String,
        type: ToolParameterType,
        description: String,
        required: Bool = true,
        enumValues: [String]? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.enumValues = enumValues
    }
}

// MARK: - Tool Definition Types

/// Definition of a tool that the LLM can use
public struct ToolDefinition: Sendable {

    /// Unique name of the tool (e.g., "get_weather")
    public let name: String

    /// Human-readable description of what the tool does
    public let description: String

    /// Parameters the tool accepts
    public let parameters: [ToolParameter]

    /// Category for organizing tools (optional)
    public let category: String?

    public init(
        name: String,
        description: String,
        parameters: [ToolParameter],
        category: String? = nil
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.category = category
    }
}

// MARK: - Tool Call Types (LLM requesting to use a tool)

/// A request from the LLM to execute a tool
public struct ToolCall: Sendable, Codable {

    /// Name of the tool to execute
    public let toolName: String

    /// Arguments to pass to the tool
    public let arguments: [String: ToolValue]

    /// Unique ID for this tool call (for tracking)
    public let callId: String?

    public init(
        toolName: String,
        arguments: [String: ToolValue],
        callId: String? = nil
    ) {
        self.toolName = toolName
        self.arguments = arguments
        self.callId = callId
    }

    /// Get a string argument by name
    public func getString(_ key: String) -> String? {
        arguments[key]?.stringValue
    }

    /// Get a number argument by name
    public func getNumber(_ key: String) -> Double? {
        arguments[key]?.numberValue
    }

    /// Get a bool argument by name
    public func getBool(_ key: String) -> Bool? {
        arguments[key]?.boolValue
    }
}

// MARK: - Tool Result Types (Result after execution)

/// Result of executing a tool
public struct ToolResult: Sendable, Codable {

    /// Name of the tool that was executed
    public let toolName: String

    /// Whether execution was successful
    public let success: Bool

    /// Result data (if successful)
    public let result: [String: ToolValue]?

    /// Error message (if failed)
    public let error: String?

    /// The original call ID (for tracking)
    public let callId: String?

    public init(
        toolName: String,
        success: Bool,
        result: [String: ToolValue]? = nil,
        error: String? = nil,
        callId: String? = nil
    ) {
        self.toolName = toolName
        self.success = success
        self.result = result
        self.error = error
        self.callId = callId
    }
}

// MARK: - Tool Executor Types

/// Function type for tool executors.
/// Takes arguments as strongly-typed ToolValue dictionary, returns result dictionary.
public typealias ToolExecutor = @Sendable ([String: ToolValue]) async throws -> [String: ToolValue]

/// A registered tool with its definition and executor
internal struct RegisteredTool: Sendable {
    let definition: ToolDefinition
    let executor: ToolExecutor
}

// MARK: - Tool Call Format

/// Format names for tool calling output.
/// Different LLM models expect different formats for tool calls.
///
/// The format logic is handled in C++ commons (single source of truth).
public enum ToolCallFormatName {
    /// JSON format: `<tool_call>{"tool":"name","arguments":{...}}</tool_call>`
    /// Use for most general-purpose models (Llama, Qwen, Mistral, etc.)
    public static let `default` = "default"
    
    /// Liquid AI format: `<|tool_call_start|>[func(args)]<|tool_call_end|>`
    /// Use for LFM2-Tool models
    public static let lfm2 = "lfm2"
}

// MARK: - Tool Calling Options

/// Options for tool-enabled generation
public struct ToolCallingOptions: Sendable {

    /// Available tools for this generation (if not provided, uses registered tools)
    public let tools: [ToolDefinition]?

    /// Maximum number of tool calls allowed in one conversation turn (default: 5)
    public let maxToolCalls: Int

    /// Whether to automatically execute tools or return them for manual execution (default: true)
    public let autoExecute: Bool

    /// Temperature for generation
    public let temperature: Float?

    /// Maximum tokens to generate
    public let maxTokens: Int?

    /// System prompt to use (will be merged with tool instructions by default)
    public let systemPrompt: String?

    /// If true, replaces the system prompt entirely instead of appending tool instructions.
    /// Use this if your system prompt already includes tool-calling instructions.
    /// Default: false (tool instructions are appended to systemPrompt)
    public let replaceSystemPrompt: Bool

    /// If true, keeps tool definitions available after the first tool call.
    /// This allows the LLM to make multiple sequential tool calls if needed.
    /// Default: false (tool definitions are removed after first call to encourage natural response)
    public let keepToolsAvailable: Bool
    
    /// Format for tool calls. Use "lfm2" for LFM2-Tool models (Liquid AI).
    /// Default: "default" which uses JSON-based format suitable for most models.
    /// Valid values: "auto", "default", "lfm2", "openai"
    /// See `ToolCallFormatName` for constants.
    public let format: String

    public init(
        tools: [ToolDefinition]? = nil,
        maxToolCalls: Int = 5,
        autoExecute: Bool = true,
        temperature: Float? = nil,
        maxTokens: Int? = nil,
        systemPrompt: String? = nil,
        replaceSystemPrompt: Bool = false,
        keepToolsAvailable: Bool = false,
        format: String = ToolCallFormatName.default
    ) {
        self.tools = tools
        self.maxToolCalls = maxToolCalls
        self.autoExecute = autoExecute
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.replaceSystemPrompt = replaceSystemPrompt
        self.keepToolsAvailable = keepToolsAvailable
        self.format = format
    }
}

// MARK: - Tool Calling Result Types

/// Result of a generation that may include tool calls
public struct ToolCallingResult: @unchecked Sendable {

    /// The final text response
    public let text: String

    /// Any tool calls the LLM made
    public let toolCalls: [ToolCall]

    /// Results of executed tools (if autoExecute was true)
    public let toolResults: [ToolResult]

    /// Whether the response is complete or waiting for tool results
    public let isComplete: Bool

    /// Conversation ID for continuing with tool results
    public let conversationId: String?

    public init(
        text: String,
        toolCalls: [ToolCall],
        toolResults: [ToolResult],
        isComplete: Bool,
        conversationId: String? = nil
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.isComplete = isComplete
        self.conversationId = conversationId
    }
}
