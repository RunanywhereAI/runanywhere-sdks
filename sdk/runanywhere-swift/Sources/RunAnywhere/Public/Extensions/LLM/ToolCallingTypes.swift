//
//  ToolCallingTypes.swift — Swift-side helpers for generated tool-calling protos.
//
//  Keep: closures (`ToolExecutor`, `RegisteredTool`), JSON bridge for
//  `argumentsJson` / `resultJson` (IDL-13 oneof tree, no C ABI equivalent),
//  and tight RA* convenience inits/getters consumed by the example app or
//  SDK internals. Do not grow without a real caller.
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

    var string: String? { if case .stringValue(let v)? = kind { return v }; return nil }
    var number: Double? { if case .numberValue(let v)? = kind { return v }; return nil }
    var int: Int? { number.map(Int.init) }
    var bool: Bool? { if case .boolValue(let v)? = kind { return v }; return nil }
    var array: [RAToolValue]? { if case .arrayValue(let v)? = kind { return v.values }; return nil }
    var object: [String: RAToolValue]? { if case .objectValue(let v)? = kind { return v.fields }; return nil }

    // JSON bridge — required by IDL-13 (`argumentsJson` / `resultJson`).
    // Swift consumers see `[String: RAToolValue]`; the wire shape is JSON.

    func toJSONString(pretty: Bool = false) -> String? {
        let opts: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        guard JSONSerialization.isValidJSONObject(jsonObject),
              let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: opts) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func parseObjectJSON(_ json: String) -> [String: RAToolValue] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.mapValues(RAToolValue.fromJSONObject(_:))
    }

    static func jsonString(from object: [String: RAToolValue]) -> String {
        let json = object.mapValues(\.jsonObject)
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private var jsonObject: Any {
        switch kind {
        case .stringValue(let v): return v
        case .numberValue(let v): return v
        case .boolValue(let v): return v
        case .arrayValue(let v): return v.values.map(\.jsonObject)
        case .objectValue(let v): return v.fields.mapValues(\.jsonObject)
        case .nullValue, .none: return NSNull()
        }
    }

    private static func fromJSONObject(_ object: Any) -> RAToolValue {
        switch object {
        case let v as Bool: return RAToolValue(v)
        case let v as Int: return RAToolValue(v)
        case let v as Double: return RAToolValue(v)
        case let v as NSNumber: return RAToolValue(v.doubleValue)
        case let v as String: return RAToolValue(v)
        case let v as [Any]: return .array(v.map(RAToolValue.fromJSONObject(_:)))
        case let v as [String: Any]: return .object(v.mapValues(RAToolValue.fromJSONObject(_:)))
        default:
            var value = RAToolValue(); value.nullValue = true; return value
        }
    }
}

// MARK: - Tool Definition Helpers

public extension RAToolParameter {
    init(name: String, type: RAToolParameterType, description: String,
         required: Bool = true, enumValues: [String] = []) {
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
        var o = RAToolCallingOptions()
        o.maxIterations = 5; o.maxToolCalls = 5; o.autoExecute = true
        o.format = .json; o.formatHint = "default"
        return o
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
