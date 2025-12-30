//
//  LLMGenerationOptions.swift
//  RunAnywhere SDK
//
//  Options for text generation
//
//  🟢 BRIDGE: Thin wrapper over C++ rac_llm_options_t
//  C++ Source: include/rac/features/llm/rac_llm_types.h
//

import CRACommons
import Foundation

/// Options for text generation
public struct LLMGenerationOptions: Sendable {

    /// Maximum number of tokens to generate
    public let maxTokens: Int

    /// Temperature for sampling (0.0 - 2.0)
    public let temperature: Float

    /// Top-p sampling parameter
    public let topP: Float

    /// Stop sequences
    public let stopSequences: [String]

    /// Enable streaming mode
    public let streamingEnabled: Bool

    /// Preferred framework for generation
    public let preferredFramework: InferenceFramework?

    /// Structured output configuration (optional)
    public let structuredOutput: StructuredOutputConfig?

    /// System prompt to define AI behavior and formatting rules
    public let systemPrompt: String?

    /// Initialize generation options
    /// - Parameters:
    ///   - maxTokens: Maximum tokens to generate (default: 100)
    ///   - temperature: Sampling temperature (default: 0.8)
    ///   - topP: Top-p sampling (default: 1.0)
    ///   - stopSequences: Stop generation at these sequences (default: empty)
    ///   - streamingEnabled: Enable streaming mode (default: false)
    ///   - preferredFramework: Preferred framework adapter (optional)
    ///   - structuredOutput: Structured output configuration (optional)
    ///   - systemPrompt: System prompt for AI behavior (optional)
    public init(
        maxTokens: Int = 100,
        temperature: Float = 0.8,
        topP: Float = 1.0,
        stopSequences: [String] = [],
        streamingEnabled: Bool = false,
        preferredFramework: InferenceFramework? = nil,
        structuredOutput: StructuredOutputConfig? = nil,
        systemPrompt: String? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
        self.streamingEnabled = streamingEnabled
        self.preferredFramework = preferredFramework
        self.structuredOutput = structuredOutput
        self.systemPrompt = systemPrompt
    }

    // MARK: - C++ Bridge (rac_llm_options_t)

    /// Execute a closure with the C++ equivalent options struct
    /// - Parameter body: Closure that receives pointer to rac_llm_options_t
    /// - Returns: The result of the closure
    public func withCOptions<T>(_ body: (UnsafePointer<rac_llm_options_t>) throws -> T) rethrows -> T {
        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(maxTokens)
        cOptions.temperature = temperature
        cOptions.top_p = topP
        cOptions.streaming_enabled = streamingEnabled ? RAC_TRUE : RAC_FALSE

        // Note: stop_sequences requires careful memory management
        // For now, we don't pass stop sequences to C++ - they can be handled by Swift
        cOptions.stop_sequences = nil
        cOptions.num_stop_sequences = 0

        // Handle system prompt
        if let prompt = systemPrompt {
            return try prompt.withCString { promptPtr in
                cOptions.system_prompt = promptPtr
                return try body(&cOptions)
            }
        } else {
            cOptions.system_prompt = nil
            return try body(&cOptions)
        }
    }
}
