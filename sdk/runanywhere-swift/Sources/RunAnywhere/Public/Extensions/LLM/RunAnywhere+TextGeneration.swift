//
//  RunAnywhere+TextGeneration.swift
//  RunAnywhere SDK
//
//  Deprecated flat text-generation verbs. The v3 surface is `RunAnywhere.llm`.
//

import Foundation

public extension RunAnywhere {

    /// Generate text from a plain prompt.
    @available(*, deprecated, renamed: "llm.generate(prompt:options:)")
    static func generate(
        prompt: String,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RALLMGenerationResult {
        let requestOptions = options ?? .defaults()
        return try await generateProto(requestOptions.toRALLMGenerateRequest(prompt: prompt))
    }

    /// Stream text generation from a plain prompt.
    @available(*, deprecated, renamed: "llm.generateStream(prompt:options:)")
    static func generateStream(
        prompt: String,
        options: RALLMGenerationOptions? = nil
    ) async throws -> AsyncStream<RALLMStreamEvent> {
        let requestOptions = options ?? .defaults()
        return try await generateStreamProto(requestOptions.toRALLMGenerateRequest(prompt: prompt))
    }

    /// Seed the loaded on-device model's adaptive context with a reusable system prompt.
    static func injectSystemPrompt(_ prompt: String) async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        try await CppBridge.LLM.shared.injectSystemPrompt(prompt)
    }

    /// Append text to the loaded on-device model's adaptive context.
    static func appendContext(_ text: String) async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        try await CppBridge.LLM.shared.appendContext(text)
    }

    /// Generate from the accumulated adaptive context without clearing the KV cache first.
    static func generateFromContext(
        query: String,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RALLMGenerationResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        return try await CppBridge.LLM.shared.generateFromContext(query: query, options: options)
    }

    /// Clear the loaded on-device model's adaptive context.
    static func clearContext() async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        try await CppBridge.LLM.shared.clearContext()
    }

    /// Generate text through the generated-proto C++ LLM service ABI.
    @available(*, deprecated, renamed: "llm.generate(prompt:options:)")
    static func generate(_ request: RALLMGenerateRequest) async throws -> RALLMGenerationResult {
        try await generateProto(request)
    }

    /// Stream text generation through the generated-proto C++ LLM service ABI.
    @available(*, deprecated, renamed: "llm.generateStream(prompt:options:)")
    static func generateStream(_ request: RALLMGenerateRequest) async throws -> AsyncStream<RALLMStreamEvent> {
        try await generateStreamProto(request)
    }

    /// Cancel the current text generation.
    @available(*, deprecated, message: "Cancel the Task consuming llm.generateStream instead")
    static func cancelGeneration() async {
        guard isReady else { return }
        do {
            _ = try await CppBridge.LLM.shared.cancelProto()
        } catch {
            SDKLogger.llm.warning("cancelGeneration failed: \(error.localizedDescription)")
        }
    }

    /// Extract structured output from a raw text string using a JSON schema.
    @available(*, deprecated, renamed: "llm.generateStructured(prompt:schema:options:)")
    static func extractStructuredOutput(
        text: String,
        schema: JsonSchema
    ) throws -> RAStructuredOutputResult {
        try parseStructuredOutput(text: text, schema: schema)
    }
}

// MARK: - Internal proto-level helpers

extension RunAnywhere {

    internal static func generateProto(_ request: RALLMGenerateRequest) async throws -> RALLMGenerationResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        logGenerationParams("generate", options: request.options)
        return try await CppBridge.LLM.shared.generate(request)
    }

    internal static func generateStreamProto(
        _ request: RALLMGenerateRequest
    ) async throws -> AsyncStream<RALLMStreamEvent> {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        logGenerationParams("generateStream", options: request.options)
        return try await CppBridge.LLM.shared.generateStream(request)
    }

    private static func logGenerationParams(_ verb: String, options: RALLMGenerationOptions) {
        let systemPromptDesc = options.systemPrompt.isEmpty ? "nil" : "set(\(options.systemPrompt.count) chars)"
        SDKLogger.llm.info(
            "[PARAMS] \(verb): temperature=\(options.temperature), top_p=\(options.topP), "
            + "max_output_tokens=\(options.maxOutputTokens), system_prompt=\(systemPromptDesc)"
        )
    }
}
