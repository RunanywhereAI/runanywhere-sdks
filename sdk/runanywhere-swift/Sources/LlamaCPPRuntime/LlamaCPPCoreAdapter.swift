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
