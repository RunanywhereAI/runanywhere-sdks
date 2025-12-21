//
//  LlamaCPPCoreAdapter.swift
//  LlamaCPPRuntime Module
//
//  LLMService protocol conformance for LlamaCPPService
//

import Foundation
import RunAnywhere

// MARK: - LLM Service Conformance

extension LlamaCPPService: LLMService {
    // Note: isReady, currentModel, and initialize(modelPath:) are already defined in LlamaCPPService

    /// LlamaCPP supports true token-by-token streaming
    public var supportsStreaming: Bool { true }

    /// Context length for the loaded model
    /// Returns the actual context size being used by llama.cpp
    /// Note: llama.cpp typically caps at 8192 for most mobile devices
    public var contextLength: Int? {
        guard isReady else { return nil }
        // Default to 8192 which is the typical capped value for mobile
        // TODO: Get actual value from C bridge when ra_get_context_length is available
        return 8192
    }

    public func generate(prompt: String, options: LLMGenerationOptions) async throws -> String {
        let config = LlamaCPPGenerationConfig(
            maxTokens: options.maxTokens,
            temperature: options.temperature,
            systemPrompt: options.systemPrompt
        )
        return try await generate(prompt: prompt, config: config)
    }

    public func streamGenerate(
        prompt: String,
        options: LLMGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        let config = LlamaCPPGenerationConfig(
            maxTokens: options.maxTokens,
            temperature: options.temperature,
            systemPrompt: options.systemPrompt
        )

        for try await token in generateStream(prompt: prompt, config: config) {
            onToken(token)
        }
    }

    public func cleanup() async {
        try? await unloadModel()
    }
}
