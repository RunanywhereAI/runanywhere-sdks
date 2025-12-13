//
//  LLMConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration for LLM component
//

import Foundation

/// Configuration for LLM component
public struct LLMConfiguration: ComponentConfiguration, Sendable {

    // MARK: - ComponentConfiguration

    /// Component type
    public var componentType: SDKComponent { .llm }

    /// Model ID (optional - uses default if not specified)
    public let modelId: String?

    /// Preferred framework for generation
    public let preferredFramework: InferenceFramework?

    // MARK: - Model Parameters

    /// Context length (max tokens the model can handle)
    public let contextLength: Int

    // MARK: - Default Generation Parameters

    /// Temperature for sampling (0.0 - 2.0)
    public let temperature: Double

    /// Maximum tokens to generate
    public let maxTokens: Int

    /// System prompt for generation
    public let systemPrompt: String?

    /// Enable streaming mode
    public let streamingEnabled: Bool

    // MARK: - Initialization

    public init(
        modelId: String? = nil,
        contextLength: Int = 2048,
        temperature: Double = 0.7,
        maxTokens: Int = 100,
        systemPrompt: String? = nil,
        streamingEnabled: Bool = true,
        preferredFramework: InferenceFramework? = nil
    ) {
        self.modelId = modelId
        self.contextLength = contextLength
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.streamingEnabled = streamingEnabled
        self.preferredFramework = preferredFramework
    }

    // MARK: - Validation

    public func validate() throws {
        guard contextLength > 0 && contextLength <= 32768 else {
            throw RunAnywhereError.validationFailed("Context length must be between 1 and 32768")
        }
        guard temperature >= 0 && temperature <= 2.0 else {
            throw RunAnywhereError.validationFailed("Temperature must be between 0 and 2.0")
        }
        guard maxTokens > 0 && maxTokens <= contextLength else {
            throw RunAnywhereError.validationFailed("Max tokens must be between 1 and context length")
        }
    }
}

// MARK: - Builder Pattern

extension LLMConfiguration {

    /// Create configuration with builder pattern
    public static func builder(modelId: String? = nil) -> Builder {
        Builder(modelId: modelId)
    }

    public class Builder {
        private var modelId: String?
        private var contextLength: Int = 2048
        private var temperature: Double = 0.7
        private var maxTokens: Int = 100
        private var systemPrompt: String?
        private var streamingEnabled: Bool = true
        private var preferredFramework: InferenceFramework?

        init(modelId: String?) {
            self.modelId = modelId
        }

        public func contextLength(_ length: Int) -> Builder {
            self.contextLength = length
            return self
        }

        public func temperature(_ temp: Double) -> Builder {
            self.temperature = temp
            return self
        }

        public func maxTokens(_ tokens: Int) -> Builder {
            self.maxTokens = tokens
            return self
        }

        public func systemPrompt(_ prompt: String?) -> Builder {
            self.systemPrompt = prompt
            return self
        }

        public func streamingEnabled(_ enabled: Bool) -> Builder {
            self.streamingEnabled = enabled
            return self
        }

        public func preferredFramework(_ framework: InferenceFramework?) -> Builder {
            self.preferredFramework = framework
            return self
        }

        public func build() -> LLMConfiguration {
            LLMConfiguration(
                modelId: modelId,
                contextLength: contextLength,
                temperature: temperature,
                maxTokens: maxTokens,
                systemPrompt: systemPrompt,
                streamingEnabled: streamingEnabled,
                preferredFramework: preferredFramework
            )
        }
    }
}
