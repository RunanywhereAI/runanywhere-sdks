//
//  RunAnywhere+StructuredOutput.swift
//  RunAnywhere SDK
//
//  Public API for structured output generation.
//  Calls C++ directly via CapabilityManager (no capabilities layer).
//

import Foundation

// MARK: - Structured Output Extensions

public extension RunAnywhere {

    /// Generate structured output that conforms to a Generatable type (non-streaming)
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options (structured output config will be added automatically)
    /// - Returns: The generated object of the specified type
    /// - Note: Events are automatically dispatched via C++ layer
    static func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> T {
        return try await serviceContainer.structuredOutputService.generateStructured(
            type,
            prompt: prompt,
            options: options
        )
    }

    /// Generate structured output with streaming support
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - content: The content to generate from (e.g., educational content for quiz)
    ///   - options: Generation options (optional)
    /// - Returns: A structured output stream containing tokens and final result
    static func generateStructuredStream<T: Generatable>(
        _ type: T.Type,
        content: String,
        options: LLMGenerationOptions? = nil
    ) -> StructuredOutputStreamResult<T> {
        return serviceContainer.structuredOutputService.generateStructuredStream(
            type,
            content: content,
            options: options
        )
    }

    /// Generate with structured output configuration
    /// - Parameters:
    ///   - prompt: The prompt to generate from
    ///   - structuredOutput: Structured output configuration
    ///   - options: Generation options
    /// - Returns: Generation result with structured data
    /// - Note: Events are automatically dispatched via C++ layer
    static func generateWithStructuredOutput(
        prompt: String,
        structuredOutput: StructuredOutputConfig,
        options: LLMGenerationOptions? = nil
    ) async throws -> LLMGenerationResult {
        return try await serviceContainer.structuredOutputService.generateWithStructuredOutput(
            prompt: prompt,
            structuredOutput: structuredOutput,
            options: options
        )
    }
}
