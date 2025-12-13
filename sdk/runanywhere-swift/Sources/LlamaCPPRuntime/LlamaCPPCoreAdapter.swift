//
//  LlamaCPPService+LLMService.swift
//  LlamaCPPRuntime Module
//
//  LLMService protocol conformance for LlamaCPPService
//

import Foundation
import RunAnywhere

// MARK: - LLM Service Conformance

extension LlamaCPPService: LLMService {
    // Note: isReady, currentModel, and initialize(modelPath:) are already defined in LlamaCPPService

    public func generate(prompt: String, options: LLMGenerationOptions) async throws -> String {
        let config = LlamaCPPGenerationConfig(
            maxTokens: options.maxTokens,
            temperature: options.temperature,
            systemPrompt: nil
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
            systemPrompt: nil
        )

        for try await token in generateStream(prompt: prompt, config: config) {
            onToken(token)
        }
    }

    public func cleanup() async {
        try? await unloadModel()
    }
}
