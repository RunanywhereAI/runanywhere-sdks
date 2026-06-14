//
//  CppBridge+LLM.swift
//  RunAnywhere SDK
//
//  LLM component bridge - manages C++ LLM component lifecycle.
//
//  All generic scaffolding (handle creation, isLoaded, loadModel,
//  unload, destroy) lives in `CppBridge.ComponentActor`; this file
//  only adds the LLM-specific `cancel()` op on top.
//

import CRACommons

// MARK: - LLM Component Bridge

extension CppBridge {

    /// LLM component manager
    /// Provides thread-safe access to the C++ LLM component
    public actor LLM {

        /// Shared LLM component instance
        public static let shared = LLM()

        /// Generic scaffold (handle / isLoaded / loadModel / unload / destroy).
        private let inner = ComponentActor(vtable: .llm)

        private init() {}

        // MARK: - Handle Management

        /// Get or create the LLM component handle
        public func getHandle() async throws -> rac_handle_t {
            try await inner.getHandle()
        }

        // MARK: - State

        /// Check if a model is loaded
        public var isLoaded: Bool {
            get async { await inner.isLoaded }
        }

        /// Get the currently loaded model ID
        public var currentModelId: String? {
            get async { await inner.currentAssetId }
        }

        // MARK: - Model Lifecycle

        /// Load an LLM model
        public func loadModel(_ modelPath: String, modelId: String, modelName: String) async throws {
            try await inner.loadModel(path: modelPath, id: modelId, name: modelName)
        }

        /// Unload the current model
        public func unload() async {
            await inner.unload()
        }

        /// Cancel ongoing generation
        public func cancel() async {
            guard let handle = await inner.existingHandle() else { return }
            rac_llm_component_cancel(handle)
        }

        // MARK: - Adaptive Context (KV Cache Prefix-Caching)

        /// Inject a system prompt into the KV cache at position 0.
        ///
        /// Clears existing KV cache, then seeds with the given prompt.
        /// Call once at session start to avoid re-tokenizing the prompt every turn.
        ///
        /// - Parameter prompt: System prompt text.
        /// - Throws: `SDKException` if no model is loaded or the backend
        ///   does not support adaptive context.
        public func injectSystemPrompt(_ prompt: String) async throws {
            let handle = try await getHandle()
            let result = rac_llm_component_inject_system_prompt(handle, prompt)
            guard result == RAC_SUCCESS else {
                throw SDKException(
                    code: .processingFailed,
                    message: "Failed to inject system prompt (rc=\(result))",
                    category: .component
                )
            }
        }

        /// Append text to the KV cache after current content.
        ///
        /// Accumulates context incrementally without re-processing previous turns.
        ///
        /// - Warning: Callers **must** call ``clearContext()`` at session boundaries
        ///   to prevent unbounded KV cache growth leading to OS-level OOM termination.
        ///
        /// - Parameter text: Text to append (user turn, assistant response, etc.).
        /// - Throws: `SDKException` if no model is loaded or the backend
        ///   does not support adaptive context.
        public func appendContext(_ text: String) async throws {
            let handle = try await getHandle()
            let result = rac_llm_component_append_context(handle, text)
            guard result == RAC_SUCCESS else {
                throw SDKException(
                    code: .processingFailed,
                    message: "Failed to append context (rc=\(result))",
                    category: .component
                )
            }
        }

        /// Generate a response from accumulated KV cache state.
        ///
        /// Unlike ``generate(_:)``, this does **not** clear the KV cache first.
        /// Use after ``injectSystemPrompt(_:)`` + ``appendContext(_:)`` to
        /// generate from preserved context.
        ///
        /// - Warning: This call is **blocking** (non-streaming). It will monopolize
        ///   the calling cooperative thread for the entire decode duration (potentially
        ///   several seconds). Overlapping generation requests while this call is
        ///   in-flight will queue behind the component mutex. A streaming variant
        ///   is planned as a follow-up.
        ///
        /// - Parameters:
        ///   - query: Query/suffix text to append before generation.
        ///   - options: Generation options, or `nil` for component defaults.
        /// - Returns: Swift-native generation result with text and metrics.
        /// - Throws: `SDKException` if no model is loaded or the backend
        ///   does not support adaptive context.
        public func generateFromContext(
            query: String,
            options: RALLMGenerationOptions? = nil
        ) async throws -> RALLMGenerationResult {
            let handle = try await getHandle()
            var cResult = rac_llm_result_t()

            let status: rac_result_t
            if let options = options {
                var cOptions = rac_llm_options_t()
                cOptions.max_tokens = options.maxTokens
                cOptions.temperature = options.temperature
                cOptions.top_p = options.topP
                cOptions.top_k = options.topK
                cOptions.repetition_penalty = options.repetitionPenalty
                cOptions.frequency_penalty = options.frequencyPenalty
                cOptions.presence_penalty = options.presencePenalty
                cOptions.min_p = options.minP
                cOptions.seed = options.seed
                cOptions.n_threads = options.nThreads
                cOptions.disable_thinking = options.disableThinking ? RAC_TRUE : RAC_FALSE
                status = withUnsafePointer(to: &cOptions) { optsPtr in
                    rac_llm_component_generate_from_context(handle, query, optsPtr, &cResult)
                }
            } else {
                status = rac_llm_component_generate_from_context(handle, query, nil, &cResult)
            }

            // Always convert + free the C result, even on success
            defer { rac_llm_result_free(&cResult) }

            guard status == RAC_SUCCESS else {
                throw SDKException(
                    code: .processingFailed,
                    message: "Failed to generate from context (rc=\(status))",
                    category: .component
                )
            }

            // Marshal C result → Swift proto result (memory is copied)
            var swiftResult = RALLMGenerationResult()
            swiftResult.text = cResult.text.map { String(cString: $0) } ?? ""
            swiftResult.inputTokens = cResult.prompt_tokens
            swiftResult.tokensGenerated = cResult.completion_tokens
            swiftResult.totalTokens = cResult.total_tokens
            swiftResult.generationTimeMs = Double(cResult.total_time_ms)
            swiftResult.ttftMs = Double(cResult.time_to_first_token_ms)
            swiftResult.tokensPerSecond = Double(cResult.tokens_per_second)
            return swiftResult
        }

        /// Clear all KV cache state.
        ///
        /// Resets the context for a fresh adaptive query cycle. Call at session
        /// boundaries, on user switch, or when memory pressure is detected.
        public func clearContext() async {
            guard let handle = await inner.existingHandle() else { return }
            rac_llm_component_clear_context(handle)
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() async {
            await inner.destroy()
        }
    }
}
