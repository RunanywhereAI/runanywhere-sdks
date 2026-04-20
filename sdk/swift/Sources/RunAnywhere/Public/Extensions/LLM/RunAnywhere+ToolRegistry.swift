// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Main-branch-parity tool registry overloads. Lets sample call sites use:
//   RunAnywhere.registerTool(definition: def,
//                             executor: { args in … })
//   let all = RunAnywhere.getRegisteredTools()  // [ToolDefinition]

import Foundation

@MainActor
public extension RunAnywhere {

    /// Register a tool with the typealias-form `ToolExecutor`. Arguments
    /// and return values are `[String: ToolValue]` dictionaries; this
    /// wrapper serialises the return dictionary to JSON for the LLM.
    static func registerTool(
        definition: ToolDefinition,
        executor: @escaping ToolExecutor
    ) {
        SessionRegistry.registeredTools.removeAll { $0.name == definition.name }
        SessionRegistry.registeredTools.append(definition)
        SessionRegistry.toolExecutors[definition.name] = { anyArgs in
            var typed: [String: ToolValue] = [:]
            for (k, v) in anyArgs {
                if let s = v as? String { typed[k] = .string(s) }
                else if let n = v as? Double { typed[k] = .number(n) }
                else if let b = v as? Bool { typed[k] = .bool(b) }
                else { typed[k] = .null }
            }
            let out = try await executor(typed)
            return ToolValue.object(out).toJSONString()
        }
    }

    /// `[String: Any]` executor variant — kept for internal callers.
    static func registerTool(
        definition: ToolDefinition,
        executor: @escaping @Sendable ([String: Any]) async throws -> String
    ) {
        SessionRegistry.registeredTools.removeAll { $0.name == definition.name }
        SessionRegistry.registeredTools.append(definition)
        SessionRegistry.toolExecutors[definition.name] = executor
    }

    /// Register a tool by name + async executor closure. Auto-creates a
    /// `ToolDefinition` stub; callers that care about the full schema
    /// should prefer the `definition:executor:` overload.
    static func registerTool(
        name: String,
        description: String = "",
        parameters: [ToolParameter] = [],
        executor: @escaping @Sendable ([String: Any]) async throws -> String
    ) {
        let def = ToolDefinition(name: name,
                                  description: description,
                                  parameters: parameters)
        registerTool(definition: def, executor: executor)
    }

    /// Return registered `ToolDefinition`s — main-branch parity. The
    /// existing `getRegisteredTools() -> [String]` accessor remains for
    /// call sites that only need names.
    static func getRegisteredTools() -> [ToolDefinition] {
        SessionRegistry.registeredTools
    }

}
