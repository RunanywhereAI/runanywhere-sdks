// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation

/// Chat-style wrapper over `LLMSession` — manages message history and
/// exposes a familiar `generate(messages:)` → `AsyncThrowingStream<String, Error>`
/// that yields token text.
///
///     let chat = try ChatSession(modelId: "qwen3-4b", modelPath: path,
///                                 systemPrompt: "You are a helpful assistant.")
///     let messages: [ChatMessage] = [.user("What is 2+2?")]
///     for try await token in chat.generate(messages: messages) {
///         print(token, terminator: "")
///     }
public final class ChatSession: @unchecked Sendable {

    public enum Role: String, Sendable {
        case system, user, assistant, tool
    }

    public struct Message: Sendable {
        public let role: Role
        public let content: String
        public init(role: Role, content: String) {
            self.role = role
            self.content = content
        }
    }

    public struct SamplingConfig: Sendable {
        public var temperature: Float
        public var maxTokens: Int
        public var useContextInjection: Bool

        public init(temperature: Float = 0.7, maxTokens: Int = 2048,
                    useContextInjection: Bool = true) {
            self.temperature = temperature
            self.maxTokens = maxTokens
            self.useContextInjection = useContextInjection
        }
    }

    private let llm: LLMSession
    private let samplingConfig: SamplingConfig
    private var systemPromptInjected = false

    public init(modelId: String, modelPath: String,
                systemPrompt: String? = nil,
                llmConfig: LLMSession.Config = .init(),
                samplingConfig: SamplingConfig = .init()) throws {
        self.llm = try LLMSession(modelId: modelId, modelPath: modelPath,
                                    config: llmConfig)
        self.samplingConfig = samplingConfig

        if let sys = systemPrompt, samplingConfig.useContextInjection {
            // Best-effort: engines that don't implement context injection
            // fall back to inline rendering in `renderMessages`.
            do {
                try llm.injectSystemPrompt(sys)
                systemPromptInjected = true
            } catch RunAnywhereError.internalError {
                // Engine returned RA_ERR_CAPABILITY_UNSUPPORTED (mapped).
                systemPromptInjected = false
            }
        }
    }

    /// Streams the model's token text for the given message history. The
    /// underlying LLMSession receives a rendered prompt; token boundaries
    /// are preserved in the yielded strings.
    public func generate(messages: [Message])
        -> AsyncThrowingStream<String, Error>
    {
        let rendered = ChatSession.renderMessages(messages,
            skipSystem: systemPromptInjected)

        return AsyncThrowingStream { continuation in
            let stream: AsyncThrowingStream<LLMSession.Token, Error>
            if systemPromptInjected {
                stream = llm.generateFromContext(query: rendered)
            } else {
                stream = llm.generate(prompt: rendered)
            }

            Task {
                do {
                    for try await token in stream {
                        if token.kind == .answer {
                            continuation.yield(token.text)
                        }
                        if token.isFinal {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { [weak self] _ in self?.cancel() }
        }
    }

    /// Collects tokens into a single String. Blocks until generation
    /// finishes or throws.
    public func generateText(messages: [Message]) async throws -> String {
        var collected = ""
        for try await chunk in generate(messages: messages) {
            collected += chunk
        }
        return collected
    }

    public func cancel() {
        llm.cancel()
    }

    public func resetHistory() throws {
        try llm.clearContext()
        systemPromptInjected = false
    }

    // MARK: - Prompt rendering

    /// Minimal ChatML-style renderer — sufficient for Qwen/Llama templates
    /// with inline system prompts. Engines that accept raw prompts consume
    /// this; engines that tokenize with a built-in template may reject
    /// it, in which case the caller should use context-injection mode.
    internal static func renderMessages(_ messages: [Message],
                                          skipSystem: Bool) -> String {
        var out = ""
        for m in messages {
            if skipSystem && m.role == .system { continue }
            out += "<|im_start|>\(m.role.rawValue)\n\(m.content)<|im_end|>\n"
        }
        out += "<|im_start|>assistant\n"
        return out
    }
}

extension ChatSession.Message {
    public static func system(_ content: String) -> Self { .init(role: .system, content: content) }
    public static func user(_ content: String)   -> Self { .init(role: .user, content: content) }
    public static func assistant(_ content: String) -> Self { .init(role: .assistant, content: content) }
    public static func tool(_ content: String)   -> Self { .init(role: .tool, content: content) }
}
