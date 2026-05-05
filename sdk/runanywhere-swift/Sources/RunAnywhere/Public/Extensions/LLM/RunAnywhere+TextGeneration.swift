//
//  RunAnywhere+TextGeneration.swift
//  RunAnywhere SDK
//
//  Public API for text generation (LLM) operations.
//  Calls C++ directly via CppBridge.LLM for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//

import CRACommons
import Foundation

// MARK: - Text Generation

public extension RunAnywhere {

    /// Generate text through the generated-proto C++ LLM service ABI.
    static func generate(_ request: RALLMGenerateRequest) async throws -> RALLMGenerationResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        let systemPromptDesc = request.systemPrompt.isEmpty ? "nil" : "set(\(request.systemPrompt.count) chars)"
        SDKLogger.llm.info(
            "[PARAMS] generate: temperature=\(request.temperature), top_p=\(request.topP), "
            + "max_tokens=\(request.maxTokens), system_prompt=\(systemPromptDesc), "
            + "streaming=\(request.streamingEnabled)"
        )

        return try await CppBridge.LLM.shared.generate(request)
    }

    /// Stream text generation through the generated-proto C++ LLM service ABI.
    static func generateStream(_ request: RALLMGenerateRequest) async throws -> AsyncStream<RALLMStreamEvent> {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        let systemPromptDesc = request.systemPrompt.isEmpty ? "nil" : "set(\(request.systemPrompt.count) chars)"
        SDKLogger.llm.info(
            "[PARAMS] generateStream: temperature=\(request.temperature), top_p=\(request.topP), "
            + "max_tokens=\(request.maxTokens), system_prompt=\(systemPromptDesc), "
            + "streaming=\(request.streamingEnabled)"
        )

        return try await CppBridge.LLM.shared.generateStream(request)
    }

    /// Cancel the current text generation
    static func cancelGeneration() async {
        guard isInitialized else { return }
        await CppBridge.LLM.shared.cancel()
    }
}

// MARK: - Structured Output Extraction

public extension RunAnywhere {

    /// Extract structured output from a raw text string using a JSON schema.
    ///
    /// Delegates to the generated structured-output parse proto ABI so commons
    /// owns extraction, canonicalization, and schema validation.
    static func extractStructuredOutput(
        text: String,
        schema: RAJSONSchema
    ) throws -> RAStructuredOutputResult {
        try CppBridge.StructuredOutput.parse(
            CppBridge.StructuredOutput.makeParseRequest(text: text, schema: schema)
        )
    }
}
