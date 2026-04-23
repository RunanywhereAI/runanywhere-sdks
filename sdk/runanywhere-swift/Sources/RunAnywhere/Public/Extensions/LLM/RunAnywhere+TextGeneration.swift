//
//  RunAnywhere+TextGeneration.swift
//  RunAnywhere SDK
//
//  Public API for text generation (LLM) operations.
//  Calls C++ directly via CppBridge.LLM for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//
//  v2 close-out Phase G-2: the direct-C-callback streaming plumbing
//  (`createTokenStream` + `LLMStreamCallbackContext` + `LLMStreamCallbacks`
//  + `LLMStreamingMetricsCollector`) was DELETED from this file. The
//  public `generateStream` now returns the proto-encoded event stream
//  emitted by `LLMStreamAdapter` (which is the single C-callback
//  registration path — no parallel hand-rolled shim remains).
//

import CRACommons
import Foundation

// MARK: - Text Generation

public extension RunAnywhere {

    /// Simple text generation with automatic event publishing.
    /// - Parameter prompt: The text prompt
    /// - Returns: Generated response (text only)
    static func chat(_ prompt: String) async throws -> String {
        let result = try await generate(prompt, options: nil)
        return result.text
    }

    /// Generate text with full metrics and analytics.
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: GenerationResult with full metrics including thinking tokens, timing, performance, etc.
    /// - Note: Events are automatically dispatched via C++ layer
    static func generate(
        _ prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> LLMGenerationResult {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        let handle = try await CppBridge.LLM.shared.getHandle()

        guard await CppBridge.LLM.shared.isLoaded else {
            throw SDKError.llm(.notInitialized, "LLM model not loaded")
        }

        let modelId = await CppBridge.LLM.shared.currentModelId ?? "unknown"
        let opts = options ?? LLMGenerationOptions()

        let startTime = Date()

        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(opts.maxTokens)
        cOptions.temperature = opts.temperature
        cOptions.top_p = opts.topP
        cOptions.streaming_enabled = RAC_FALSE

        let systemPromptDesc = opts.systemPrompt.map { "set(\($0.count) chars)" } ?? "nil"
        SDKLogger.llm.info(
            "[PARAMS] generate: temperature=\(cOptions.temperature), top_p=\(cOptions.top_p), "
            + "max_tokens=\(cOptions.max_tokens), system_prompt=\(systemPromptDesc), "
            + "streaming=\(cOptions.streaming_enabled == RAC_TRUE)"
        )

        var llmResult = rac_llm_result_t()
        let generateResult: rac_result_t
        if let systemPrompt = opts.systemPrompt {
            generateResult = systemPrompt.withCString { sysPromptPtr in
                cOptions.system_prompt = sysPromptPtr
                return prompt.withCString { promptPtr in
                    rac_llm_component_generate(handle, promptPtr, &cOptions, &llmResult)
                }
            }
        } else {
            cOptions.system_prompt = nil
            generateResult = prompt.withCString { promptPtr in
                rac_llm_component_generate(handle, promptPtr, &cOptions, &llmResult)
            }
        }

        guard generateResult == RAC_SUCCESS else {
            throw SDKError.llm(.generationFailed, "Generation failed: \(generateResult)")
        }

        let endTime = Date()
        let totalTimeMs = endTime.timeIntervalSince(startTime) * 1000

        let rawText: String
        if let textPtr = llmResult.text {
            rawText = String(cString: textPtr)
        } else {
            rawText = ""
        }
        let inputTokens = Int(llmResult.prompt_tokens)
        let outputTokens = Int(llmResult.completion_tokens)
        let tokensPerSecond = llmResult.tokens_per_second > 0 ? Double(llmResult.tokens_per_second) : 0

        let (generatedText, thinkingContent) = ThinkingContentParser.extract(from: rawText)
        let (thinkingTokens, responseTokens) = ThinkingContentParser.splitTokens(
            totalCompletionTokens: outputTokens,
            responseText: generatedText,
            thinkingContent: thinkingContent
        )

        return LLMGenerationResult(
            text: generatedText,
            thinkingContent: thinkingContent,
            inputTokens: inputTokens,
            tokensUsed: outputTokens,
            modelUsed: modelId,
            latencyMs: totalTimeMs,
            framework: "llamacpp",
            tokensPerSecond: tokensPerSecond,
            timeToFirstTokenMs: nil,
            thinkingTokens: thinkingTokens,
            responseTokens: responseTokens
        )
    }

    /// Streaming text generation using the Phase G-2 proto-byte event
    /// stream. Returns an `AsyncStream<RALLMStreamEvent>` — one event per
    /// generated token, plus a terminal event (`isFinal == true`) that
    /// carries the `finish_reason` ("stop" / "length" / "cancelled" /
    /// "error") and optional `error_message`.
    ///
    /// Under the hood this delegates to [`LLMStreamAdapter`] which owns
    /// the single `rac_llm_set_stream_proto_callback` registration for
    /// the handle. There is no parallel hand-rolled streaming path; this
    /// is the single C-callback-to-Swift path for LLM tokens.
    ///
    /// Example:
    /// ```swift
    /// let stream = try await RunAnywhere.generateStream(prompt)
    /// for await event in stream {
    ///     if event.isFinal { break }
    ///     print(event.token, terminator: "")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: `AsyncStream<RALLMStreamEvent>` of proto-decoded events.
    static func generateStream(
        _ prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> AsyncStream<RALLMStreamEvent> {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        let handle = try await CppBridge.LLM.shared.getHandle()

        guard await CppBridge.LLM.shared.isLoaded else {
            throw SDKError.llm(.notInitialized, "LLM model not loaded")
        }

        let opts = options ?? LLMGenerationOptions()

        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(opts.maxTokens)
        cOptions.temperature = opts.temperature
        cOptions.top_p = opts.topP
        cOptions.streaming_enabled = RAC_TRUE

        let systemPromptDesc = opts.systemPrompt.map { "set(\($0.count) chars)" } ?? "nil"
        SDKLogger.llm.info(
            "[PARAMS] generateStream: temperature=\(cOptions.temperature), top_p=\(cOptions.top_p), "
            + "max_tokens=\(cOptions.max_tokens), system_prompt=\(systemPromptDesc), "
            + "streaming=\(cOptions.streaming_enabled == RAC_TRUE)"
        )

        // Subscribe BEFORE kicking off the generation so we never miss
        // early tokens that the engine emits synchronously from inside
        // rac_llm_component_generate_stream().
        let adapter = LLMStreamAdapter(handle: handle)
        let stream = adapter.stream()

        let capturedPrompt = prompt
        let capturedSystemPrompt = opts.systemPrompt
        var capturedOptions = cOptions
        Task.detached {
            _ = capturedPrompt.withCString { promptPtr -> rac_result_t in
                if let sysPrompt = capturedSystemPrompt {
                    return sysPrompt.withCString { sysPtr in
                        capturedOptions.system_prompt = sysPtr
                        return rac_llm_component_generate_stream(
                            handle,
                            promptPtr,
                            &capturedOptions,
                            nil, nil, nil, nil)
                    }
                } else {
                    capturedOptions.system_prompt = nil
                    return rac_llm_component_generate_stream(
                        handle,
                        promptPtr,
                        &capturedOptions,
                        nil, nil, nil, nil)
                }
            }
        }

        return stream
    }
}

// v2 close-out Phase 9 (P2-4): the in-Swift `ThinkingContentParser` enum
// was deleted from this file (~80 LOC). The replacement, with the same
// public API and byte-equivalent behavior, lives in
// `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+LLMThinking.swift`
// and delegates to the `rac_llm_*` C ABI in
// `rac/features/llm/rac_llm_thinking.h`.
