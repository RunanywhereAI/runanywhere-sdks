//
//  RunAnywhere+AdaptiveContext.swift
//  RunAnywhere SDK
//
//  Public API for adaptive-context (KV cache prefix-caching) —
//  namespaced under `RunAnywhere.adaptiveContext.*`.
//
//  Delegates to the component-layer C ABI through CppBridge.LLM.
//  See rac_llm_component.h for the underlying C documentation.
//

import CRACommons
import Foundation

// MARK: - Adaptive Context Capability Namespace

public extension RunAnywhere {

    /// Capability accessor for adaptive-context (KV cache prefix-caching).
    ///
    /// Provides multi-turn session optimization by preserving the KV cache
    /// across conversational turns. Typical workflow:
    ///
    /// ```swift
    /// // 1. Inject system prompt once at session start (~1100 tokens, ~5s)
    /// try await RunAnywhere.adaptiveContext.injectSystemPrompt(systemPrompt)
    ///
    /// // 2. For each user turn, append + generate (KV cache preserved, ~ms TTFT)
    /// try await RunAnywhere.adaptiveContext.appendContext(userMessage)
    /// let result = try await RunAnywhere.adaptiveContext.generateFromContext(query: "")
    ///
    /// // 3. Clear at session end to reclaim memory
    /// await RunAnywhere.adaptiveContext.clearContext()
    /// ```
    ///
    /// - Important: Only the LlamaCPP backend supports adaptive context today.
    ///   Other backends will return errors with code `RAC_ERROR_NOT_SUPPORTED`.
    static var adaptiveContext: AdaptiveContext { AdaptiveContext() }

    /// Stateless namespace exposing adaptive-context (KV cache) operations.
    ///
    /// Backed by the C ABI via `CppBridge.LLM` component-layer wrappers.
    /// All methods are serialized through the component's internal mutex —
    /// concurrent calls are safe but will queue sequentially.
    struct AdaptiveContext: Sendable {

        // MARK: - Context Management

        /// Inject a system prompt into the KV cache at position 0.
        ///
        /// Clears any existing KV cache and seeds it with the given prompt.
        /// Call once at session start to pay the prefill cost exactly once;
        /// subsequent turns skip re-tokenization entirely.
        ///
        /// - Parameter prompt: System prompt text.
        /// - Throws: ``SDKException`` if the SDK is not initialized, no model
        ///   is loaded, or the backend does not support adaptive context.
        public func injectSystemPrompt(_ prompt: String) async throws {
            guard RunAnywhere.isInitialized else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            try await CppBridge.LLM.shared.injectSystemPrompt(prompt)
        }

        /// Append text to the KV cache after current content.
        ///
        /// Accumulates context incrementally without re-processing previous
        /// turns. Use to append user messages, assistant responses, or RAG
        /// chunks to the preserved KV cache.
        ///
        /// - Warning: The KV cache grows linearly with each call. Callers
        ///   **must** call ``clearContext()`` at session boundaries (user
        ///   switch, session end, or memory pressure) to prevent unbounded
        ///   growth that will cause OS-level OOM (Jetsam) termination.
        ///
        /// - Parameter text: Text to append.
        /// - Throws: ``SDKException`` if the SDK is not initialized, no model
        ///   is loaded, or the backend does not support adaptive context.
        public func appendContext(_ text: String) async throws {
            guard RunAnywhere.isInitialized else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            try await CppBridge.LLM.shared.appendContext(text)
        }

        // MARK: - Generation

        /// Generate a response from accumulated KV cache state.
        ///
        /// Unlike ``RunAnywhere/generate(prompt:options:)``, this does **not**
        /// clear the KV cache first. The cached system prompt and appended
        /// context are preserved, eliminating prefill latency on subsequent
        /// turns.
        ///
        /// - Warning: **Blocking call.** This method monopolizes a cooperative
        ///   thread for the entire decode duration (potentially several seconds
        ///   on mobile hardware). Overlapping generation requests will queue
        ///   behind the component mutex. For streaming UX in production, prefer
        ///   ``RunAnywhere/generateStream(prompt:options:)`` with full prompt
        ///   re-submission until a streaming-from-context variant is available.
        ///
        /// - Parameters:
        ///   - query: Query or suffix text appended before generation begins.
        ///     Pass an empty string to generate purely from accumulated cache.
        ///   - options: Generation options, or `nil` for component defaults.
        /// - Returns: The generation result including text, token counts, and
        ///   timing metrics. Caller owns the result memory.
        /// - Throws: ``SDKException`` if the SDK is not initialized, no model
        ///   is loaded, or the backend does not support adaptive context.
        public func generateFromContext(
            query: String,
            options: UnsafePointer<rac_llm_options_t>? = nil
        ) async throws -> rac_llm_result_t {
            guard RunAnywhere.isInitialized else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            return try await CppBridge.LLM.shared.generateFromContext(query: query, options: options)
        }

        // MARK: - Cleanup

        /// Clear all KV cache state.
        ///
        /// Resets the adaptive context for a fresh session. Call at:
        /// - Session end
        /// - User profile switch
        /// - Memory pressure notifications
        /// - Before loading a different model
        ///
        /// Safe to call when no model is loaded (no-op).
        public func clearContext() async {
            guard RunAnywhere.isInitialized else { return }
            await CppBridge.LLM.shared.clearContext()
        }
    }
}
