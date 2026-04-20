// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Public tool-calling types — format enum, options struct, argument
// value type, and executor protocol. Mirrors the main-branch
// `Public/Extensions/LLM/ToolCallingTypes.swift` surface.

import Foundation

/// Name of the tool-call text format the LLM emits. Exposed as plain
/// String constants so sample call sites can pass them straight into
/// `ToolCallingOptions(format:)`.
public enum ToolCallFormatName {
    public static let `default` = "default"
    public static let xml       = "xml"
    public static let json      = "json"
    public static let openai    = "openai"
    public static let chatml    = "chatml"
    public static let generic   = "generic"
    public static let lfm2      = "lfm2"
}

public struct ToolCallingOptions: Sendable {
    public var format: String
    public var autoExecute: Bool
    public var maxToolCalls: Int
    public var temperature: Float
    public var maxTokens: Int
    public init(maxToolCalls: Int = 3,
                autoExecute: Bool = true,
                temperature: Float = 0.7,
                maxTokens: Int = 512,
                format: String = ToolCallFormatName.default) {
        self.format = format; self.autoExecute = autoExecute
        self.maxToolCalls = maxToolCalls
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

/// Tool call emitted by the LLM with fully-typed args — matches main's
/// sample UI shape. `ToolCall` in `ToolCalling.swift` keeps an `[String:
/// Any]` field for internal use; this dedicated type provides the
/// `toolName` alias and a typed argument dictionary.
public struct ToolCallInvocation: Sendable {
    public let toolName: String
    public let arguments: [String: ToolValue]
    public init(toolName: String, arguments: [String: ToolValue] = [:]) {
        self.toolName = toolName; self.arguments = arguments
    }
}

/// Result of executing a tool call — passed back into the LLM. The
/// `result` dictionary is the executor's structured return value; UIs
/// that want a raw string can render it as JSON.
public struct ToolCallResult: Sendable {
    public let toolName: String
    public let result: [String: ToolValue]?
    public let success: Bool
    public let error: String?
    public init(toolName: String,
                result: [String: ToolValue]? = nil,
                success: Bool, error: String? = nil) {
        self.toolName = toolName; self.result = result
        self.success = success; self.error = error
    }
}

/// Return type of `generateWithTools(_:options:)` when `options` is a
/// `ToolCallingOptions`. Bundles the final assistant reply together with
/// every tool call/result pair the agent produced.
public struct ToolCallingResult: Sendable {
    public let text: String
    public let toolCalls: [ToolCallInvocation]
    public let toolResults: [ToolCallResult]
    public let generation: LLMGenerationResult
    public init(text: String,
                toolCalls: [ToolCallInvocation],
                toolResults: [ToolCallResult],
                generation: LLMGenerationResult) {
        self.text = text
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.generation = generation
    }
}

/// Dynamic value type used for tool-call arguments. Mirrors the shape
/// main exposed; nested objects stringify to JSON for parity.
public enum ToolValue: Sendable, Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    private enum CodingKeys: String, CodingKey { case kind, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "string": self = .string(try c.decode(String.self, forKey: .value))
        case "number": self = .number(try c.decode(Double.self, forKey: .value))
        case "bool":   self = .bool(try c.decode(Bool.self, forKey: .value))
        default:       self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let s): try c.encode("string", forKey: .kind); try c.encode(s, forKey: .value)
        case .number(let n): try c.encode("number", forKey: .kind); try c.encode(n, forKey: .value)
        case .bool(let b):   try c.encode("bool",   forKey: .kind); try c.encode(b, forKey: .value)
        case .null:          try c.encode("null",   forKey: .kind)
        }
    }

    /// Container case used by the sample app; v2's wire model is flat
    /// so we serialise nested objects to a JSON string for storage.
    public static func object(_ v: [String: ToolValue]) -> ToolValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(v),
           let s = String(data: data, encoding: .utf8) {
            return .string(s)
        }
        return .string("{}")
    }

    /// JSON-encoded string view of this value for prompt formatting.
    public func toJSONString() -> String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .number(let n): return String(n)
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return "null"
        }
    }

    /// Pretty-printable JSON view. Only `.string` values may carry an
    /// embedded JSON object (produced by `.object(_:)`); in that case
    /// we round-trip through `JSONSerialization` to re-indent. Other
    /// variants fall back to the compact form.
    public func toJSONString(pretty: Bool) -> String? {
        guard pretty else { return toJSONString() }
        switch self {
        case .string(let s):
            guard let data = s.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else {
                return toJSONString()
            }
            let out = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys])
            return out.flatMap { String(data: $0, encoding: .utf8) }
        default:
            return toJSONString()
        }
    }

    /// `Any` view used when interop is required.
    public var anyValue: Any? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b):   return b
        case .null:          return nil
        }
    }

    /// Type-accessors used by sample tool executors.
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    public var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

/// Closure-form executor type — matches main-branch sample spelling.
/// Callers pass `{ args in try await … }` where `args` and the return
/// value are `[String: ToolValue]` dictionaries.
public typealias ToolExecutor = @Sendable ([String: ToolValue]) async throws -> [String: ToolValue]

/// Protocol-form executor — kept for code paths that wanted a stateful
/// type. New callers should prefer the `ToolExecutor` closure typealias.
public protocol ToolExecutorProtocol: Sendable {
    var name: String { get }
    func execute(arguments: [String: ToolValue]) async throws -> String
}
