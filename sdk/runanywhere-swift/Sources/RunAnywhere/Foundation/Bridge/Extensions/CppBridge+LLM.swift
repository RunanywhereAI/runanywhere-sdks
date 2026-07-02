//
//  CppBridge+LLM.swift
//  RunAnywhere SDK
//
//  LLM component bridge - manages C++ LLM component lifecycle.
//
//  All generic scaffolding (handle creation, isLoaded, loadModel,
//  unload, destroy) lives in `CppBridge.ComponentActor`; this file
//  adds LLM-specific operations such as cancel and adaptive context on top.
//

import CRACommons

private enum LLMAdaptiveContextABI {
    typealias StringCall = @convention(c) (UnsafePointer<CChar>?) -> rac_result_t
    typealias VoidCall = @convention(c) () -> rac_result_t
    typealias Generate = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let injectSystemPromptName = "rac_llm_inject_system_prompt_lifecycle"
    static let appendContextName = "rac_llm_append_context_lifecycle"
    static let generateFromContextName = "rac_llm_generate_from_context_proto"
    static let clearContextName = "rac_llm_clear_context_lifecycle"

    static let injectSystemPrompt = NativeProtoABI.load(injectSystemPromptName, as: StringCall.self)
    static let appendContext = NativeProtoABI.load(appendContextName, as: StringCall.self)
    static let generateFromContext = NativeProtoABI.load(generateFromContextName, as: Generate.self)
    static let clearContext = NativeProtoABI.load(clearContextName, as: VoidCall.self)
}

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

        // MARK: - Adaptive Context

        /// Seed the lifecycle-owned LLM context with a reusable system prompt.
        public func injectSystemPrompt(_ prompt: String) async throws {
            let symbol = try NativeProtoABI.require(
                LLMAdaptiveContextABI.injectSystemPrompt,
                named: LLMAdaptiveContextABI.injectSystemPromptName
            )
            let status = prompt.withCString {
                symbol($0)
            }
            try Self.throwIfFailed(status, operation: "inject system prompt")
        }

        /// Append user or retrieval text to the lifecycle-owned LLM context.
        public func appendContext(_ text: String) async throws {
            let symbol = try NativeProtoABI.require(
                LLMAdaptiveContextABI.appendContext,
                named: LLMAdaptiveContextABI.appendContextName
            )
            let status = text.withCString {
                symbol($0)
            }
            try Self.throwIfFailed(status, operation: "append context")
        }

        /// Generate without clearing the accumulated lifecycle-owned LLM context.
        public func generateFromContext(
            query: String,
            options: RALLMGenerationOptions? = nil
        ) async throws -> RALLMGenerationResult {
            var request = (options ?? .defaults()).toRALLMGenerateRequest(prompt: query)
            request.streamingEnabled = false
            return try NativeProtoABI.invoke(
                request,
                symbol: LLMAdaptiveContextABI.generateFromContext,
                symbolName: LLMAdaptiveContextABI.generateFromContextName,
                responseType: RALLMGenerationResult.self
            )
        }

        /// Clear accumulated adaptive context on the lifecycle-owned LLM.
        public func clearContext() async throws {
            let symbol = try NativeProtoABI.require(
                LLMAdaptiveContextABI.clearContext,
                named: LLMAdaptiveContextABI.clearContextName
            )
            let status = symbol()
            try Self.throwIfFailed(status, operation: "clear context")
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() async {
            await inner.destroy()
        }

        private static func throwIfFailed(_ status: rac_result_t, operation: String) throws {
            guard status == RAC_SUCCESS else {
                let nativeMessage = String(cString: rac_error_message(status))
                throw SDKException(
                    code: .processingFailed,
                    message: "LLM adaptive context \(operation) failed: \(nativeMessage) (\(status))",
                    category: .component
                )
            }
        }
    }
}
