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
        /// `mode` picks how the schema is enforced:
        /// - `.validationOnly` (default): generate freely, then validate.
        /// - `.repair`: validate, then retry once with a repair instruction if invalid.
        /// - `.constrained`: engine-constrained decoding — fails preflight
        ///   until a constrained-decoding engine is wired in.
        ///
        /// - Throws: `SDKException` when no model can be loaded, `mode` cannot
        ///   be honored, generation fails, or the output cannot be parsed.
        public func generateStructured(
            prompt: String,
            schema: JsonSchema,
            mode: StructuredEnforcementMode = .validationOnly,
            options: LlmOptions? = nil
        ) async throws -> StructuredResult {
            guard mode != .constrained else {
                throw SDKException(
                    code: .notSupported,
                    message: "generateStructured(mode: .constrained) needs engine-level constrained decoding, " +
                        "which is not wired in yet; use .validationOnly or .repair",
                    category: .validation
                )
            }

            var effective = options ?? LlmOptions()
            effective.structuredOutput = StructuredOutput(schema: schema)

            var generation = try await generate(prompt: prompt, history: [], options: effective)
            var parsed = try RunAnywhere.parseStructuredOutput(text: generation.text, schema: schema)

            let isValid = parsed.hasValidation ? parsed.validation.isValid : false
            if mode == .repair, !isValid {
                let repairPrompt = RunAnywhere.structuredRepairPrompt(
                    original: prompt,
                    invalidOutput: generation.text,
                    schema: schema
                )
                generation = try await generate(prompt: repairPrompt, history: [], options: effective)
                parsed = try RunAnywhere.parseStructuredOutput(text: generation.text, schema: schema)
            }

            return StructuredResult(proto: parsed, generation: generation, mode: mode)
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
                // idl/tool_calling.proto deleted RAToolCallingResult's
                // conversation-id-bearing predecessor outright; the result
                // carries no correlation id at all now, so mint one locally
                // purely for GenerationResult's requestId field.
                let requestId = UUID().uuidString
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
                return GenerationResult(proto: loop, requestId: requestId, model: model)
            }

            var request = RALLMGenerateRequest()
            request.options = effective.toProto()
            request.messages = LLM.makeMessages(history: history, prompt: prompt)
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
            request.options = effective.toProto()
            request.messages = LLM.makeMessages(history: history, prompt: prompt)
            request.modelID = model

            let events = try await CppBridge.LLM.shared.generateStream(request)
            return RunAnywhere.mapGenerationStream(events, model: model)
        }

        /// Fold prior turns plus the current prompt into the single
        /// `messages` array `RALLMGenerateRequest` now carries — oldest
        /// first, ending with the turn the model must answer. Replaces the
        /// deleted `RALLMGenerateRequest.prompt`/`.history` pair.
        private static func makeMessages(history: [RAChatMessage], prompt: String) -> [RAChatMessage] {
            var messages = history
            var userTurn = RAChatMessage()
            userTurn.role = .user
            userTurn.content = prompt
            messages.append(userTurn)
            return messages
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
    /// Fold the native LLM stream onto the spec event grammar. Never
    /// fabricates a successful `completed` when the producer did not report
    /// one — the stream ends in `completed`, `failed`, or `cancelled`.
    internal static func mapGenerationStream(
        _ events: AsyncStream<RALLMStreamEvent>,
        model: String
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var sawStart = false
                var accumulatedText = ""
                var accumulatedThinking = ""
                var requestId = ""
                var sawTerminal = false
                var toolCallIndex = 0
                let textItemId = UUID().uuidString
                let reasoningItemId = UUID().uuidString

                func partialOrNil() -> String? { accumulatedText.isEmpty ? nil : accumulatedText }

                func emitToken(_ event: RALLMStreamEvent, sequence: Int64) {
                    guard !event.token.isEmpty else { return }
                    // RALLMStreamEvent's discriminator is event-level
                    // (eventKind: RALLMStreamEventKind — started/token/
                    // thinking/toolCall/progress/completed/error), not a
                    // per-token RATokenKind field.
                    if event.eventKind == .thinking {
                        accumulatedThinking += event.token
                        continuation.yield(.reasoningDelta(
                            requestId: requestId,
                            sequence: sequence,
                            itemId: reasoningItemId,
                            index: 0,
                            text: event.token
                        ))
                    } else if event.eventKind != .toolCall {
                        accumulatedText += event.token
                        continuation.yield(.textDelta(
                            requestId: requestId,
                            sequence: sequence,
                            itemId: textItemId,
                            index: 0,
                            text: event.token
                        ))
                    }
                }

                for await event in events {
                    if Task.isCancelled { break }
                    if !event.requestID.isEmpty { requestId = event.requestID }
                    let sequence = Int64(event.seq)

                    if event.hasError || event.eventKind == .error {
                        continuation.yield(.failed(
                            requestId: requestId,
                            partial: partialOrNil(),
                            error: SDKException(proto: event.error)
                        ))
                        sawTerminal = true
                        break
                    }

                    if !sawStart {
                        sawStart = true
                        continuation.yield(.started(requestId: requestId))
                    }

                    if event.hasToolCall {
                        let itemId = event.toolCall.id.isEmpty ? "tool-\(toolCallIndex)" : event.toolCall.id
                        continuation.yield(.toolCallAdded(
                            requestId: requestId,
                            sequence: sequence,
                            itemId: itemId,
                            index: toolCallIndex,
                            call: event.toolCall
                        ))
                        toolCallIndex += 1
                    }

                    emitToken(event, sequence: sequence)

                    // LLMStreamFinalResult is deleted: the stream terminates
                    // with event_kind == COMPLETED (result set) — there is
                    // no separate isFinal flag anymore.
                    if event.eventKind == .completed {
                        let result = RunAnywhere.generationResultFromStreamTerminal(
                            proto: event.hasResult ? event.result : nil,
                            accumulatedText: accumulatedText,
                            accumulatedThinking: accumulatedThinking,
                            finishReason: event.finishReason,
                            requestId: requestId,
                            model: model
                        )
                        continuation.yield(.completed(requestId: requestId, result: result))
                        sawTerminal = true
                        break
                    }
                }

                // Never fabricate `completed` on a stream end without a
                // producer terminal: emit `cancelled` for caller-initiated
                // cancellation, `failed` otherwise.
                if !sawTerminal {
                    if Task.isCancelled {
                        continuation.yield(.cancelled(requestId: requestId, partial: partialOrNil()))
                    } else if sawStart {
                        continuation.yield(.failed(
                            requestId: requestId,
                            partial: partialOrNil(),
                            error: SDKException(
                                code: .generationFailed,
                                message: "Generation stream ended before a terminal event",
                                category: .component
                            )
                        ))
                    } else {
                        continuation.yield(.failed(
                            requestId: requestId,
                            partial: nil,
                            error: SDKException(
                                code: .generationFailed,
                                message: "Generation ended before producing any output",
                                category: .component
                            )
                        ))
                    }
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

    /// Prefer commons terminal metrics; keep streamed text/thinking only when
    /// the terminal payload is empty or weaker. Never invent wall-clock rates.
    internal static func generationResultFromStreamTerminal(
        proto: RALLMGenerationResult?,
        accumulatedText: String,
        accumulatedThinking: String,
        finishReason: RAFinishReason,
        requestId: String,
        model: String
    ) -> GenerationResult {
        if var terminal = proto {
            if preferStreamedContent(accumulatedText, over: terminal.text) {
                terminal.text = accumulatedText
            }
            let terminalThinking = terminal.hasThinkingContent ? terminal.thinkingContent : ""
            if preferStreamedContent(accumulatedThinking, over: terminalThinking) {
                terminal.thinkingContent = accumulatedThinking
            }
            return GenerationResult(proto: terminal, requestId: requestId, model: model)
        }
        return GenerationResult(
            text: accumulatedText,
            thinkingText: accumulatedThinking.isEmpty ? nil : accumulatedThinking,
            toolCalls: [],
            finishReason: FinishReason(proto: finishReason),
            inputTokens: 0,
            outputTokens: 0,
            timeToFirstTokenMs: 0,
            tokensPerSecond: 0,
            requestId: requestId,
            model: model
        )
    }

    /// Transport-integrity fallback: keep the longer non-empty stream transcript
    /// when the terminal text is missing or truncated.
    private static func preferStreamedContent(_ streamed: String, over terminal: String) -> Bool {
        !streamed.isEmpty && (terminal.isEmpty || streamed.count > terminal.count)
    }

    internal static func parseStructuredOutput(
        text: String,
        schema: JsonSchema
    ) throws -> RAStructuredOutputResult {
        try CppBridge.StructuredOutput.parse(
            CppBridge.StructuredOutput.makeParseRequest(text: text, schema: schema)
        )
    }

    /// Build the one retry prompt `generateStructured(mode: .repair)` sends
    /// when the first pass did not validate against `schema`.
    internal static func structuredRepairPrompt(
        original: String,
        invalidOutput: String,
        schema: JsonSchema
    ) -> String {
        """
        \(original)

        Your previous answer did not match the required JSON schema. Reply again with ONLY JSON that satisfies this schema.

        Schema: \(schema)
        Previous invalid answer: \(invalidOutput)
        """
    }
}
