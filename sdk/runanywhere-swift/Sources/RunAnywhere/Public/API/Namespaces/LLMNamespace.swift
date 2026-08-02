//
//  LLMNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.llm` — text generation, tool calling, and structured output.
//  Generation auto-loads whatever it needs, downloading when `options.model`
//  names a model that is absent.
//

import Foundation

public extension RunAnywhere {

    /// Text generation.
    static var llm: LLM { LLM() }

    /// Generate text from a prompt or a conversation.
    struct LLM: Sendable {

        /// Tools this SDK instance offers to every generation.
        public var tools: Tools { Tools() }

        /// Generate a reply to one prompt.
        ///
        /// ```swift
        /// let result = try await RunAnywhere.llm.generate(prompt: "Name three colours")
        /// print(result.text)
        /// ```
        ///
        /// - Throws: `SDKException` when no model can be loaded or generation fails.
        public func generate(
            prompt: String,
            options: LlmOptions? = nil
        ) async throws -> GenerationResult {
            try await generate(prompt: prompt, history: [], options: options)
        }

        /// Generate a reply to a conversation.
        ///
        /// System turns become `options.systemPrompt`; the trailing user turn
        /// becomes the prompt and everything between it travels as history.
        ///
        /// - Throws: `SDKException` when the conversation has no user turn, no
        ///   model can be loaded, or generation fails.
        public func generate(
            messages: [ChatMessage],
            options: LlmOptions? = nil
        ) async throws -> GenerationResult {
            let split = try LLM.split(messages: messages, options: options)
            return try await generate(prompt: split.prompt, history: split.history, options: split.options)
        }

        /// Generate a reply to one prompt, streaming tokens as they arrive.
        ///
        /// - Throws: `SDKException` from this call when no model can be loaded,
        ///   and into the returned stream when generation fails.
        public func generateStream(
            prompt: String,
            options: LlmOptions? = nil
        ) async throws -> AsyncThrowingStream<GenerationEvent, Error> {
            try await generateStream(prompt: prompt, history: [], options: options)
        }

        /// Generate a reply to a conversation, streaming tokens as they arrive.
        ///
        /// - Throws: `SDKException` from this call when the conversation has no
        ///   user turn or no model can be loaded, and into the returned stream
        ///   when generation fails.
        public func generateStream(
            messages: [ChatMessage],
            options: LlmOptions? = nil
        ) async throws -> AsyncThrowingStream<GenerationEvent, Error> {
            let split = try LLM.split(messages: messages, options: options)
            return try await generateStream(prompt: split.prompt, history: split.history, options: split.options)
        }

        /// Generate output that satisfies `schema`.
        ///
        /// - Throws: `SDKException` when no model can be loaded, generation
        ///   fails, or the output cannot be parsed.
        public func generateStructured(
            prompt: String,
            schema: JsonSchema,
            options: LlmOptions? = nil
        ) async throws -> StructuredResult {
            var effective = options ?? LlmOptions()
            effective.structuredOutput = StructuredOutput(schema: schema)
            let generation = try await generate(prompt: prompt, history: [], options: effective)
            let parsed = try RunAnywhere.parseStructuredOutput(text: generation.text, schema: schema)
            return StructuredResult(proto: parsed, generation: generation)
        }

        // MARK: - Shared implementation

        private func generate(
            prompt: String,
            history: [RAChatMessage],
            options: LlmOptions?
        ) async throws -> GenerationResult {
            let effective = options ?? LlmOptions()
            let model = try await RunAnywhere.ensureLoaded(
                modelId: effective.model,
                category: .language
            )

            let registered = await ToolRegistry.shared.getAll()
            let activeTools = effective.tools.isEmpty ? registered : effective.tools
            if !activeTools.isEmpty, !LLM.isToolChoiceNone(effective.toolChoice) {
                let loop = try await RunAnywhere.generateWithTools(
                    prompt: prompt,
                    options: effective.toProto(),
                    toolOptions: effective.toolCallingProto(),
                    history: history.map(\.content)
                )
                if loop.hasErrorMessage {
                    throw SDKException(
                        code: RAErrorCode(rawValue: Int(loop.errorCode)) ?? .unspecified,
                        message: loop.errorMessage,
                        category: .component
                    )
                }
                return GenerationResult(proto: loop, requestId: loop.conversationID, model: model)
            }

            var request = RALLMGenerateRequest()
            request.prompt = prompt
            request.options = effective.toProto()
            request.history = history
            request.modelID = model

            let result = try await CppBridge.LLM.shared.generate(request)
            if result.hasError {
                throw SDKException(proto: result.error)
            }
            return GenerationResult(proto: result, requestId: request.requestID)
        }

        private func generateStream(
            prompt: String,
            history: [RAChatMessage],
            options: LlmOptions?
        ) async throws -> AsyncThrowingStream<GenerationEvent, Error> {
            let effective = options ?? LlmOptions()
            let model = try await RunAnywhere.ensureLoaded(
                modelId: effective.model,
                category: .language
            )

            var request = RALLMGenerateRequest()
            request.prompt = prompt
            request.options = effective.toProto()
            request.history = history
            request.modelID = model

            let events = try await CppBridge.LLM.shared.generateStream(request)
            return RunAnywhere.mapGenerationStream(events, model: model)
        }

        private static func isToolChoiceNone(_ choice: ToolChoice) -> Bool {
            if case .none = choice { return true }
            return false
        }

        /// Fold a message list into the prompt/history/system-prompt shape the
        /// commons generate ABI accepts.
        private static func split(
            messages: [ChatMessage],
            options: LlmOptions?
        ) throws -> (prompt: String, history: [RAChatMessage], options: LlmOptions) {
            var effective = options ?? LlmOptions()

            let systemTurns = messages.filter { $0.role == .system }
            if !systemTurns.isEmpty, effective.systemPrompt == nil {
                effective.systemPrompt = systemTurns.map(\.content).joined(separator: "\n\n")
            }

            let conversation = messages.filter { $0.role != .system }
            guard let last = conversation.last, last.role == .user else {
                throw SDKException(
                    code: .invalidInput,
                    message: "The message list must end with a user turn",
                    category: .validation
                )
            }
            let history = conversation.dropLast().map { $0.toProto() }
            return (last.content, Array(history), effective)
        }
    }

    /// Register, list, and remove the tools the model may call.
    struct Tools: Sendable {

        /// Make `tool` callable, running `executor` when the model invokes it.
        public func register(_ tool: ToolDefinition, executor: @escaping ToolExecutor) async {
            await ToolRegistry.shared.register(tool, executor: executor)
        }

        /// Stop offering the tool called `name`.
        public func unregister(name: String) async {
            await ToolRegistry.shared.unregister(name)
        }

        /// List every registered tool.
        public func list() async -> [ToolDefinition] {
            await ToolRegistry.shared.getAll()
        }

        /// Remove every registered tool.
        public func clear() async {
            await ToolRegistry.shared.clear()
        }
    }
}

// MARK: - Internal proto-level helpers

extension RunAnywhere {

    // swiftlint:disable function_body_length
    /// Fold the native LLM stream onto the spec event grammar, throwing on
    /// terminal error events instead of leaking them through a payload field.
    internal static func mapGenerationStream(
        _ events: AsyncStream<RALLMStreamEvent>,
        model: String
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var sawStart = false
                var accumulatedText = ""
                var accumulatedThinking = ""
                var tokenCount = 0
                let startedAt = Date()
                var firstTokenAt: Date?
                var requestId = ""
                var sawCompletion = false

                for await event in events {
                    if Task.isCancelled { break }
                    requestId = event.requestID

                    if event.hasError || event.eventKind == .error {
                        continuation.finish(throwing: SDKException(proto: event.error))
                        return
                    }

                    if !sawStart {
                        sawStart = true
                        continuation.yield(.started(requestId: requestId))
                    }

                    if event.hasToolCall {
                        continuation.yield(.toolCall(event.toolCall))
                    }

                    if !event.token.isEmpty {
                        if firstTokenAt == nil { firstTokenAt = Date() }
                        tokenCount += 1
                        let kind = TokenKind(proto: event.kind)
                        if kind == .thought {
                            accumulatedThinking += event.token
                        } else if event.kind != .toolCall {
                            accumulatedText += event.token
                        }
                        continuation.yield(.token(text: event.token, kind: kind))
                    }

                    if event.isFinal {
                        let result: GenerationResult
                        if event.hasResult {
                            result = GenerationResult(
                                proto: event.result,
                                requestId: requestId,
                                model: model
                            )
                        } else {
                            result = RunAnywhere.synthesizeResult(
                                text: accumulatedText,
                                thinking: accumulatedThinking,
                                tokenCount: tokenCount,
                                startedAt: startedAt,
                                firstTokenAt: firstTokenAt,
                                finishReason: event.finishReason,
                                requestId: requestId,
                                model: model
                            )
                        }
                        continuation.yield(.completed(result))
                        sawCompletion = true
                        break
                    }
                }

                // The grammar ends in `completed` or a thrown error, never a
                // silent finish: a backend that drops the stream without a
                // terminal event still gets a wall-clock result, and one that
                // produced nothing at all is a failure.
                if !sawCompletion, !Task.isCancelled {
                    guard sawStart else {
                        continuation.finish(throwing: SDKException(
                            code: .generationFailed,
                            message: "Generation ended before producing any output",
                            category: .component
                        ))
                        return
                    }
                    continuation.yield(.completed(RunAnywhere.synthesizeResult(
                        text: accumulatedText,
                        thinking: accumulatedThinking,
                        tokenCount: tokenCount,
                        startedAt: startedAt,
                        firstTokenAt: firstTokenAt,
                        finishReason: "",
                        requestId: requestId,
                        model: model
                    )))
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable termination in
                task.cancel()
                if case .cancelled = termination {
                    Task { _ = try? await CppBridge.LLM.shared.cancelProto() }
                }
            }
        }
    }
    // swiftlint:enable function_body_length

    /// Wall-clock metrics for backends that end a stream without a terminal
    /// aggregate result.
    internal static func synthesizeResult(
        text: String,
        thinking: String,
        tokenCount: Int,
        startedAt: Date,
        firstTokenAt: Date?,
        finishReason: String,
        requestId: String,
        model: String
    ) -> GenerationResult {
        let totalSeconds = Date().timeIntervalSince(startedAt)
        let ttft = firstTokenAt.map { Int64(($0.timeIntervalSince(startedAt) * 1000).rounded()) } ?? 0
        let throughput = totalSeconds > 0 ? Float(Double(tokenCount) / totalSeconds) : 0
        return GenerationResult(
            text: text,
            thinkingText: thinking.isEmpty ? nil : thinking,
            toolCalls: [],
            finishReason: FinishReason.parse(finishReason),
            inputTokens: 0,
            outputTokens: tokenCount,
            timeToFirstTokenMs: ttft,
            tokensPerSecond: throughput,
            requestId: requestId,
            model: model
        )
    }

    internal static func parseStructuredOutput(
        text: String,
        schema: RAJSONSchema
    ) throws -> RAStructuredOutputResult {
        try CppBridge.StructuredOutput.parse(
            CppBridge.StructuredOutput.makeParseRequest(text: text, schema: schema)
        )
    }
}
