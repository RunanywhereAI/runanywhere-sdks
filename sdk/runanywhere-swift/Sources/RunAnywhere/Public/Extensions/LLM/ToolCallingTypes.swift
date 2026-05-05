//
//  ToolCallingTypes.swift
//  RunAnywhere SDK
//
//  Swift executor helpers for the generated tool-calling proto contracts.
//

import Foundation

// MARK: - Tool Executor Types

/// Function type for Swift-native tool executors.
public typealias ToolExecutor = @Sendable ([String: RAToolValue]) async throws -> [String: RAToolValue]

/// A registered tool with its generated proto definition and Swift executor.
internal struct RegisteredTool: Sendable {
    let definition: RAToolDefinition
    let executor: ToolExecutor
}

// MARK: - RAToolValue Helpers

public extension RAToolValue {
    init(_ value: String) {
        self.init()
        self.stringValue = value
    }

    init(_ value: Int) {
        self.init()
        self.numberValue = Double(value)
    }

    init(_ value: Double) {
        self.init()
        self.numberValue = value
    }

    init(_ value: Bool) {
        self.init()
        self.boolValue = value
    }

    static func array(_ values: [RAToolValue]) -> RAToolValue {
        var array = RAToolValueArray()
        array.values = values
        var value = RAToolValue()
        value.arrayValue = array
        return value
    }

    static func object(_ fields: [String: RAToolValue]) -> RAToolValue {
        var object = RAToolValueObject()
        object.fields = fields
        var value = RAToolValue()
        value.objectValue = object
        return value
    }

    static var null: RAToolValue {
        var value = RAToolValue()
        value.nullValue = true
        return value
    }

    var string: String? {
        if case .stringValue(let value)? = kind { return value }
        return nil
    }

    var number: Double? {
        if case .numberValue(let value)? = kind { return value }
        return nil
    }

    var int: Int? {
        number.map(Int.init)
    }

    var bool: Bool? {
        if case .boolValue(let value)? = kind { return value }
        return nil
    }

    var array: [RAToolValue]? {
        if case .arrayValue(let value)? = kind { return value.values }
        return nil
    }

    var object: [String: RAToolValue]? {
        if case .objectValue(let value)? = kind { return value.fields }
        return nil
    }

    var isNull: Bool {
        if case .nullValue = kind { return true }
        return false
    }

    func toJSONString(pretty: Bool = false) -> String? {
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        guard JSONSerialization.isValidJSONObject(jsonObject) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: options) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func parseObjectJSON(_ json: String) -> [String: RAToolValue] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.mapValues(RAToolValue.fromJSONObject(_:))
    }

    static func jsonString(from object: [String: RAToolValue]) -> String {
        let jsonObject = object.mapValues { $0.jsonObject }
        guard JSONSerialization.isValidJSONObject(jsonObject),
              let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private var jsonObject: Any {
        switch kind {
        case .stringValue(let value): return value
        case .numberValue(let value): return value
        case .boolValue(let value): return value
        case .arrayValue(let value): return value.values.map { $0.jsonObject }
        case .objectValue(let value): return value.fields.mapValues { $0.jsonObject }
        case .nullValue, .none: return NSNull()
        }
    }

    private static func fromJSONObject(_ object: Any) -> RAToolValue {
        switch object {
        case is NSNull:
            return .null
        case let value as Bool:
            return RAToolValue(value)
        case let value as Int:
            return RAToolValue(value)
        case let value as Double:
            return RAToolValue(value)
        case let value as NSNumber:
            return RAToolValue(value.doubleValue)
        case let value as String:
            return RAToolValue(value)
        case let value as [Any]:
            return .array(value.map(RAToolValue.fromJSONObject(_:)))
        case let value as [String: Any]:
            return .object(value.mapValues(RAToolValue.fromJSONObject(_:)))
        default:
            return .null
        }
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
    init(
        name: String,
        description: String,
        parameters: [RAToolParameter],
        category: String? = nil
    ) {
        self.init()
        self.name = name
        self.description_p = description
        self.parameters = parameters
        if let category {
            self.category = category
        }
    }
}

extension RAToolCall {
    init(toolName: String, arguments: [String: RAToolValue], callId: String? = nil) {
        // IDL-13: typed `arguments` map removed — only `argumentsJson` survives.
        self.init()
        self.name = toolName
        self.argumentsJson = RAToolValue.jsonString(from: arguments)
        if let callId {
            self.id = callId
            self.callID = callId
        }
    }
}

public extension RAToolCallingOptions {
    static func defaults() -> RAToolCallingOptions {
        var options = RAToolCallingOptions()
        options.maxIterations = 5
        options.maxToolCalls = 5
        options.autoExecute = true
        options.format = .json
        options.formatHint = "default"
        return options
    }
}

extension RAToolCallingOptions {
    var maxToolCallCount: Int {
        let explicit = hasMaxToolCalls ? maxToolCalls : maxIterations
        return Int(explicit > 0 ? explicit : 5)
    }

    var resolvedFormatName: String {
        if hasFormat {
            switch format {
            case .json: return "default"
            case .openaiFunctions: return "openai"
            case .hermes: return "hermes"
            case .pythonic: return "lfm2"
            default: break
            }
        }
        return formatHint.isEmpty ? "default" : formatHint
    }
}
