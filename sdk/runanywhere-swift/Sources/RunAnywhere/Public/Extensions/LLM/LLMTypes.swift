//
//  LLMTypes.swift
//  RunAnywhere SDK
//
//  Public types for LLM text generation.
//  These are thin wrappers over C++ types in rac_llm_types.h
//

import CRACommons
import Foundation

// MARK: - LLM Configuration

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
            throw SDKError.general(.validationFailed, "Context length must be between 1 and 32768")
        }
        guard temperature >= 0 && temperature <= 2.0 else {
            throw SDKError.general(.validationFailed, "Temperature must be between 0 and 2.0")
        }
        guard maxTokens > 0 && maxTokens <= contextLength else {
            throw SDKError.general(.validationFailed, "Max tokens must be between 1 and context length")
        }
    }
}

// MARK: - LLMConfiguration Builder

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

// MARK: - LLM Generation Options

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
    public func withCOptions<T>(_ body: (UnsafePointer<rac_llm_options_t>) throws -> T) rethrows -> T {
        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(maxTokens)
        cOptions.temperature = temperature
        cOptions.top_p = topP
        cOptions.streaming_enabled = streamingEnabled ? RAC_TRUE : RAC_FALSE
        cOptions.stop_sequences = nil
        cOptions.num_stop_sequences = 0

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

// MARK: - LLM Generation Result

/// Result of a text generation request
public struct LLMGenerationResult: Sendable {

    /// Generated text (with thinking content removed if extracted)
    public let text: String

    /// Thinking/reasoning content extracted from the response
    public let thinkingContent: String?

    /// Number of input/prompt tokens (from tokenizer)
    public let inputTokens: Int

    /// Number of tokens used (output tokens)
    public let tokensUsed: Int

    /// Model used for generation
    public let modelUsed: String

    /// Total latency in milliseconds
    public let latencyMs: TimeInterval

    /// Framework used for generation
    public let framework: String?

    /// Tokens generated per second
    public let tokensPerSecond: Double

    /// Time to first token in milliseconds (only for streaming)
    public let timeToFirstTokenMs: Double?

    /// Structured output validation result
    public var structuredOutputValidation: StructuredOutputValidation?

    /// Number of tokens used for thinking/reasoning
    public let thinkingTokens: Int?

    /// Number of tokens in the actual response content
    public let responseTokens: Int

    public init(
        text: String,
        thinkingContent: String? = nil,
        inputTokens: Int = 0,
        tokensUsed: Int,
        modelUsed: String,
        latencyMs: TimeInterval,
        framework: String? = nil,
        tokensPerSecond: Double = 0,
        timeToFirstTokenMs: Double? = nil,
        structuredOutputValidation: StructuredOutputValidation? = nil,
        thinkingTokens: Int? = nil,
        responseTokens: Int? = nil
    ) {
        self.text = text
        self.thinkingContent = thinkingContent
        self.inputTokens = inputTokens
        self.tokensUsed = tokensUsed
        self.modelUsed = modelUsed
        self.latencyMs = latencyMs
        self.framework = framework
        self.tokensPerSecond = tokensPerSecond
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.structuredOutputValidation = structuredOutputValidation
        self.thinkingTokens = thinkingTokens
        self.responseTokens = responseTokens ?? tokensUsed
    }

    // MARK: - C++ Bridge (rac_llm_result_t)

    /// Initialize from C++ rac_llm_result_t
    public init(from cResult: rac_llm_result_t, modelId: String) {
        self.init(
            text: cResult.text.map { String(cString: $0) } ?? "",
            thinkingContent: nil,
            inputTokens: Int(cResult.prompt_tokens),
            tokensUsed: Int(cResult.completion_tokens),
            modelUsed: modelId,
            latencyMs: TimeInterval(cResult.total_time_ms),
            framework: nil,
            tokensPerSecond: Double(cResult.tokens_per_second),
            timeToFirstTokenMs: cResult.time_to_first_token_ms > 0
                ? Double(cResult.time_to_first_token_ms) : nil,
            structuredOutputValidation: nil,
            thinkingTokens: nil,
            responseTokens: Int(cResult.completion_tokens)
        )
    }

    /// Initialize from C++ rac_llm_stream_result_t
    public init(from cStreamResult: rac_llm_stream_result_t, modelId: String) {
        let metrics = cStreamResult.metrics
        self.init(
            text: cStreamResult.text.map { String(cString: $0) } ?? "",
            thinkingContent: cStreamResult.thinking_content.map { String(cString: $0) },
            inputTokens: Int(metrics.prompt_tokens),
            tokensUsed: Int(metrics.tokens_generated),
            modelUsed: modelId,
            latencyMs: TimeInterval(metrics.total_time_ms),
            framework: nil,
            tokensPerSecond: Double(metrics.tokens_per_second),
            timeToFirstTokenMs: metrics.time_to_first_token_ms > 0
                ? Double(metrics.time_to_first_token_ms) : nil,
            structuredOutputValidation: nil,
            thinkingTokens: metrics.thinking_tokens > 0 ? Int(metrics.thinking_tokens) : nil,
            responseTokens: Int(metrics.response_tokens)
        )
    }
}

// MARK: - LLM Streaming Result

/// Container for streaming generation with metrics
public struct LLMStreamingResult: Sendable {

    /// Stream of tokens as they are generated
    public let stream: AsyncThrowingStream<String, Error>

    /// Task that completes with final generation result including metrics
    public let result: Task<LLMGenerationResult, Error>

    public init(
        stream: AsyncThrowingStream<String, Error>,
        result: Task<LLMGenerationResult, Error>
    ) {
        self.stream = stream
        self.result = result
    }
}

// MARK: - Thinking Tag Pattern

/// Pattern for extracting thinking/reasoning content from model output
public struct ThinkingTagPattern: Codable, Sendable {

    public let openingTag: String
    public let closingTag: String

    public init(openingTag: String, closingTag: String) {
        self.openingTag = openingTag
        self.closingTag = closingTag
    }

    /// Default pattern used by models like DeepSeek and Hermes
    public static let defaultPattern = ThinkingTagPattern(
        openingTag: "<think>",
        closingTag: "</think>"
    )

    /// Alternative pattern with full "thinking" word
    public static let thinkingPattern = ThinkingTagPattern(
        openingTag: "<thinking>",
        closingTag: "</thinking>"
    )

    /// Custom pattern for models that use different tags
    public static func custom(opening: String, closing: String) -> ThinkingTagPattern {
        ThinkingTagPattern(openingTag: opening, closingTag: closing)
    }

    // MARK: - C++ Bridge (rac_thinking_tag_pattern_t)

    /// Execute a closure with the C++ equivalent pattern struct
    public func withCPattern<T>(_ body: (UnsafePointer<rac_thinking_tag_pattern_t>) throws -> T) rethrows -> T {
        return try openingTag.withCString { openingPtr in
            return try closingTag.withCString { closingPtr in
                var cPattern = rac_thinking_tag_pattern_t()
                cPattern.opening_tag = openingPtr
                cPattern.closing_tag = closingPtr
                return try body(&cPattern)
            }
        }
    }

    /// Initialize from C++ rac_thinking_tag_pattern_t
    public init(from cPattern: rac_thinking_tag_pattern_t) {
        self.init(
            openingTag: cPattern.opening_tag.map { String(cString: $0) } ?? "<think>",
            closingTag: cPattern.closing_tag.map { String(cString: $0) } ?? "</think>"
        )
    }
}

// MARK: - LoRA Adapter Types

/// Configuration for loading a LoRA adapter.
public struct LoRAAdapterConfig: Sendable {

    /// Path to the LoRA adapter GGUF file
    public let path: String

    /// Scale factor (0.0 to 1.0+, default 1.0). Higher = stronger adapter effect.
    public let scale: Float

    public init(path: String, scale: Float = 1.0) {
        precondition(!path.isEmpty, "LoRA adapter path cannot be empty")
        self.path = path
        self.scale = scale
    }
}

/// Info about a loaded LoRA adapter (read-only).
public struct LoRAAdapterInfo: Sendable {

    /// Path used when loading the adapter
    public let path: String

    /// Active scale factor
    public let scale: Float

    /// Whether the adapter is currently applied to the context
    public let applied: Bool
}

/// Catalog entry for a LoRA adapter registered with the SDK.
/// Register adapters at app startup via RunAnywhere.registerLoraAdapter(_:).
public struct LoraAdapterCatalogEntry: Sendable {

    /// Unique adapter identifier
    public let id: String

    /// Human-readable display name
    public let name: String

    /// Short description of what this adapter does
    public let adapterDescription: String

    /// Direct download URL for the GGUF file
    public let downloadURL: URL

    /// Filename to save as on disk
    public let filename: String

    /// Model IDs this adapter is compatible with
    public let compatibleModelIds: [String]

    /// File size in bytes (0 if unknown)
    public let fileSize: Int64

    /// Recommended LoRA scale (e.g. 0.3 for F16 adapters on quantized bases)
    public let defaultScale: Float

    public init(
        id: String,
        name: String,
        description: String,
        downloadURL: URL,
        filename: String,
        compatibleModelIds: [String],
        fileSize: Int64 = 0,
        defaultScale: Float = 1.0
    ) {
        self.id = id
        self.name = name
        self.adapterDescription = description
        self.downloadURL = downloadURL
        self.filename = filename
        self.compatibleModelIds = compatibleModelIds
        self.fileSize = fileSize
        self.defaultScale = defaultScale
    }

    // Internal init from C struct
    init(from cEntry: rac_lora_entry_t) {
        self.id = String(cString: cEntry.id)
        self.name = String(cString: cEntry.name)
        self.adapterDescription = String(cString: cEntry.description)
        self.downloadURL = URL(string: String(cString: cEntry.download_url)) ?? URL(fileURLWithPath: "")
        self.filename = String(cString: cEntry.filename)
        var modelIds: [String] = []
        if let ids = cEntry.compatible_model_ids {
            for i in 0..<cEntry.compatible_model_count {
                if let ptr = ids[i] { modelIds.append(String(cString: ptr)) }
            }
        }
        self.compatibleModelIds = modelIds
        self.fileSize = cEntry.file_size
        self.defaultScale = cEntry.default_scale
    }
}

/// Result of a LoRA compatibility pre-check.
public struct LoraCompatibilityResult: Sendable {

    /// Whether the adapter is compatible with the currently loaded model
    public let isCompatible: Bool

    /// Error message if not compatible
    public let error: String?

    public init(isCompatible: Bool, error: String? = nil) {
        self.isCompatible = isCompatible
        self.error = error
    }
}

// MARK: - Structured Output Types

/// Protocol for types that can be generated as structured output from LLMs
public protocol Generatable: Codable {
    /// The JSON schema for this type
    static var jsonSchema: String { get }
}

public extension Generatable {
    /// Generate a basic JSON schema from the type
    static var jsonSchema: String {
        return """
        {
          "type": "object",
          "additionalProperties": false
        }
        """
    }

    /// Type-specific generation hints
    static var generationHints: GenerationHints? {
        return nil
    }
}

/// Structured output configuration
public struct StructuredOutputConfig: @unchecked Sendable {
    /// The type to generate
    public let type: Generatable.Type

    /// Whether to include schema in prompt
    public let includeSchemaInPrompt: Bool

    public init(
        type: Generatable.Type,
        includeSchemaInPrompt: Bool = true
    ) {
        self.type = type
        self.includeSchemaInPrompt = includeSchemaInPrompt
    }
}

/// Hints for customizing structured output generation
public struct GenerationHints: Sendable {
    public let temperature: Float?
    public let maxTokens: Int?
    public let systemRole: String?

    public init(temperature: Float? = nil, maxTokens: Int? = nil, systemRole: String? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemRole = systemRole
    }
}

/// Token emitted during streaming
public struct StreamToken: Sendable {
    public let text: String
    public let timestamp: Date
    public let tokenIndex: Int

    public init(text: String, timestamp: Date = Date(), tokenIndex: Int) {
        self.text = text
        self.timestamp = timestamp
        self.tokenIndex = tokenIndex
    }
}

/// Result containing both the token stream and final parsed result
public struct StructuredOutputStreamResult<T: Generatable>: @unchecked Sendable {
    /// Stream of tokens as they're generated
    public let tokenStream: AsyncThrowingStream<StreamToken, Error>

    /// Final parsed result (available after stream completes)
    public let result: Task<T, Error>
}

/// Structured output validation result
public struct StructuredOutputValidation: Sendable {
    public let isValid: Bool
    public let containsJSON: Bool
    public let error: String?

    public init(isValid: Bool, containsJSON: Bool, error: String?) {
        self.isValid = isValid
        self.containsJSON = containsJSON
        self.error = error
    }
}

// MARK: - Stream Accumulator

/// Accumulates tokens during streaming for later parsing
public actor StreamAccumulator {
    private var text = ""
    private var isComplete = false
    private var completionContinuation: CheckedContinuation<Void, Never>?

    public init() {}

    public func append(_ token: String) {
        text += token
    }

    public var fullText: String {
        return text
    }

    public func markComplete() {
        guard !isComplete else { return }
        isComplete = true
        completionContinuation?.resume()
        completionContinuation = nil
    }

    public func waitForCompletion() async {
        guard !isComplete else { return }

        await withCheckedContinuation { continuation in
            if isComplete {
                continuation.resume()
            } else {
                completionContinuation = continuation
            }
        }
    }
}
