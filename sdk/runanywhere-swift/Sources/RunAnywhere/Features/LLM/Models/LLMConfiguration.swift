//
//  LLMConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration for LLM component
//

import Foundation

/// Configuration for LLM component
public struct LLMConfiguration: ComponentConfiguration, ComponentInitParameters, Sendable {

    // MARK: - ComponentConfiguration

    /// Component type
    public var componentType: SDKComponent { .llm }

    // MARK: - Required Properties

    /// Model ID (optional - uses default if not specified)
    public let modelId: String?

    // MARK: - Model Loading Parameters

    /// Context length (max tokens the model can handle)
    public let contextLength: Int

    /// Quantization level for the model
    public let quantizationLevel: QuantizationLevel?

    /// Token cache size in MB
    public let cacheSize: Int

    /// Optional system prompt to preload
    public let preloadContext: String?

    // MARK: - Default Generation Parameters

    /// Temperature for sampling (0.0 - 2.0)
    public let temperature: Double

    /// Maximum tokens to generate
    public let maxTokens: Int

    /// System prompt for generation
    public let systemPrompt: String?

    /// Enable streaming mode
    public let streamingEnabled: Bool

    /// Preferred framework for generation
    public let preferredFramework: InferenceFramework?

    // MARK: - Initialization

    public init(
        modelId: String? = nil,
        contextLength: Int = 2048,
        quantizationLevel: QuantizationLevel? = nil,
        cacheSize: Int = 100,
        preloadContext: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 100,
        systemPrompt: String? = nil,
        streamingEnabled: Bool = true,
        preferredFramework: InferenceFramework? = nil
    ) {
        self.modelId = modelId
        self.contextLength = contextLength
        self.quantizationLevel = quantizationLevel
        self.cacheSize = cacheSize
        self.preloadContext = preloadContext
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt ?? preloadContext
        self.streamingEnabled = streamingEnabled
        self.preferredFramework = preferredFramework
    }

    // MARK: - ComponentConfiguration

    public func validate() throws {
        guard contextLength > 0 && contextLength <= 32768 else {
            throw RunAnywhereError.validationFailed("Context length must be between 1 and 32768")
        }
        guard cacheSize >= 0 && cacheSize <= 1000 else {
            throw RunAnywhereError.validationFailed("Cache size must be between 0 and 1000 MB")
        }
        guard temperature >= 0 && temperature <= 2.0 else {
            throw RunAnywhereError.validationFailed("Temperature must be between 0 and 2.0")
        }
        guard maxTokens > 0 && maxTokens <= contextLength else {
            throw RunAnywhereError.validationFailed("Max tokens must be between 1 and context length")
        }
    }
}

// MARK: - Quantization Level

extension LLMConfiguration {

    /// Quantization levels for LLM models
    public enum QuantizationLevel: String, Sendable {
        case q4v0 = "Q4_0"
        case q4KM = "Q4_K_M"
        case q5KM = "Q5_K_M"
        case q6K = "Q6_K"
        case q8v0 = "Q8_0"
        case f16 = "F16"
        case f32 = "F32"
    }
}

// MARK: - Builder Pattern

extension LLMConfiguration {

    /// Create configuration with builder pattern
    public static func builder(modelId: String? = nil) -> Builder {
        Builder(modelId: modelId)
    }

    public class Builder {
        private var config: LLMConfiguration

        init(modelId: String?) {
            self.config = LLMConfiguration(modelId: modelId)
        }

        public func contextLength(_ length: Int) -> Builder {
            config = LLMConfiguration(
                modelId: config.modelId,
                contextLength: length,
                quantizationLevel: config.quantizationLevel,
                cacheSize: config.cacheSize,
                preloadContext: config.preloadContext,
                temperature: config.temperature,
                maxTokens: config.maxTokens,
                systemPrompt: config.systemPrompt,
                streamingEnabled: config.streamingEnabled,
                preferredFramework: config.preferredFramework
            )
            return self
        }

        public func temperature(_ temp: Double) -> Builder {
            config = LLMConfiguration(
                modelId: config.modelId,
                contextLength: config.contextLength,
                quantizationLevel: config.quantizationLevel,
                cacheSize: config.cacheSize,
                preloadContext: config.preloadContext,
                temperature: temp,
                maxTokens: config.maxTokens,
                systemPrompt: config.systemPrompt,
                streamingEnabled: config.streamingEnabled,
                preferredFramework: config.preferredFramework
            )
            return self
        }

        public func maxTokens(_ tokens: Int) -> Builder {
            config = LLMConfiguration(
                modelId: config.modelId,
                contextLength: config.contextLength,
                quantizationLevel: config.quantizationLevel,
                cacheSize: config.cacheSize,
                preloadContext: config.preloadContext,
                temperature: config.temperature,
                maxTokens: tokens,
                systemPrompt: config.systemPrompt,
                streamingEnabled: config.streamingEnabled,
                preferredFramework: config.preferredFramework
            )
            return self
        }

        public func systemPrompt(_ prompt: String?) -> Builder {
            config = LLMConfiguration(
                modelId: config.modelId,
                contextLength: config.contextLength,
                quantizationLevel: config.quantizationLevel,
                cacheSize: config.cacheSize,
                preloadContext: config.preloadContext,
                temperature: config.temperature,
                maxTokens: config.maxTokens,
                systemPrompt: prompt,
                streamingEnabled: config.streamingEnabled,
                preferredFramework: config.preferredFramework
            )
            return self
        }

        public func streamingEnabled(_ enabled: Bool) -> Builder {
            config = LLMConfiguration(
                modelId: config.modelId,
                contextLength: config.contextLength,
                quantizationLevel: config.quantizationLevel,
                cacheSize: config.cacheSize,
                preloadContext: config.preloadContext,
                temperature: config.temperature,
                maxTokens: config.maxTokens,
                systemPrompt: config.systemPrompt,
                streamingEnabled: enabled,
                preferredFramework: config.preferredFramework
            )
            return self
        }

        public func preferredFramework(_ framework: InferenceFramework?) -> Builder {
            config = LLMConfiguration(
                modelId: config.modelId,
                contextLength: config.contextLength,
                quantizationLevel: config.quantizationLevel,
                cacheSize: config.cacheSize,
                preloadContext: config.preloadContext,
                temperature: config.temperature,
                maxTokens: config.maxTokens,
                systemPrompt: config.systemPrompt,
                streamingEnabled: config.streamingEnabled,
                preferredFramework: framework
            )
            return self
        }

        public func build() -> LLMConfiguration {
            config
        }
    }
}
