// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Public `RunAnywhere` tool-calling registry surface. The registry lives
// in memory; registered `ToolExecutor` instances are invoked when the
// LLM emits a tool-call block during generation.

import Foundation

@MainActor
internal enum ToolRegistry {
    static var executors: [String: any ToolExecutorProtocol] = [:]
}

@MainActor
public extension RunAnywhere {

    /// Register a protocol-form `ToolExecutorProtocol` implementation.
    /// The LLM pipeline looks it up by `executor.name`.
    static func registerTool(_ executor: any ToolExecutorProtocol) {
        ToolRegistry.executors[executor.name] = executor
    }

    /// Main-branch parity overload — takes an unlabeled
    /// `ToolDefinition` and a closure `ToolExecutor`. Matches the
    /// sample's `RunAnywhere.registerTool(tool.definition, executor:
    /// tool.executor)` call site.
    static func registerTool(_ definition: ToolDefinition,
                              executor: @escaping ToolExecutor) async {
        registerTool(definition: definition, executor: executor)
    }

    /// Async no-op overload for `clearTools()` to match main-branch
    /// sample call sites that `await` the operation.
    static func clearTools() async {
        ToolRegistry.executors.removeAll()
        SessionRegistry.registeredTools.removeAll()
        SessionRegistry.toolExecutors.removeAll()
    }

    /// Registered tool names. Use `getRegisteredTools()` in
    /// [RunAnywhere+ToolRegistry.swift](x-source-tag://tool-registry) for
    /// the `[ToolDefinition]` variant that matches main-branch samples.
    static func getRegisteredToolExecutorNames() -> [String] {
        Array(ToolRegistry.executors.keys).sorted()
    }

}

/// Parser extracting `<think>...</think>` and similar thinking blocks
/// from LLM output. Mirrors the main-branch `ThinkingContentParser`.
public final class ThinkingContentParser {
    public init() {}

    /// Parse a raw LLM response into `(thinking, answer)`. Everything
    /// between the outermost `<think>`/`</think>` tags goes into
    /// `thinking`; the rest is `answer`. If no think tags are present,
    /// `thinking` is empty.
    public func parse(_ text: String) -> (thinking: String, answer: String) {
        guard let openRange = text.range(of: "<think>"),
              let closeRange = text.range(of: "</think>") else {
            return (thinking: "", answer: text)
        }
        let thinking = String(text[openRange.upperBound..<closeRange.lowerBound])
        var answer = text
        answer.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        return (thinking: thinking.trimmingCharacters(in: .whitespacesAndNewlines),
                answer: answer.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Legacy entry points matching main's API shape.
    public func extract(from text: String) -> (thinking: String, answer: String) {
        parse(text)
    }
    public func strip(from text: String) -> String {
        parse(text).answer
    }
}
