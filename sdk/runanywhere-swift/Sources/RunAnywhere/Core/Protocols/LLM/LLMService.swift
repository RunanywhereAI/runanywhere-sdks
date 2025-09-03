import Foundation

// MARK: - LLM Service Errors

/// Errors that can occur in LLM services
public enum LLMServiceError: LocalizedError {
    case notInitialized
    case modelNotFound(String)
    case generationFailed(Error)
    case streamingNotSupported
    case contextLengthExceeded
    case invalidOptions

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "LLM service is not initialized"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .generationFailed(let error):
            return "Generation failed: \(error.localizedDescription)"
        case .streamingNotSupported:
            return "Streaming generation is not supported"
        case .contextLengthExceeded:
            return "Context length exceeded"
        case .invalidOptions:
            return "Invalid generation options"
        }
    }
}

// MARK: - LLM Initialization Parameters

/// Initialization parameters specific to LLM component
public struct LLMInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.llm
    public let modelId: String?

    // LLM-specific parameters
    public let contextLength: Int
    public let useGPUIfAvailable: Bool
    public let quantizationLevel: QuantizationLevel?
    public let cacheSize: Int // Token cache size in MB
    public let preloadContext: String? // Optional system prompt to preload

    // Generation parameters
    public let temperature: Double
    public let maxTokens: Int
    public let systemPrompt: String?
    public let streamingEnabled: Bool

    public enum QuantizationLevel: String, Sendable {
        case q4_0 = "Q4_0"
        case q4_k_m = "Q4_K_M"
        case q5_k_m = "Q5_K_M"
        case q6_k = "Q6_K"
        case q8_0 = "Q8_0"
        case f16 = "F16"
        case f32 = "F32"
    }

    public init(
        modelId: String? = nil,
        contextLength: Int = 2048,
        useGPUIfAvailable: Bool = true,
        quantizationLevel: QuantizationLevel? = nil,
        cacheSize: Int = 100,
        preloadContext: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 100,
        systemPrompt: String? = nil,
        streamingEnabled: Bool = true
    ) {
        self.modelId = modelId
        self.contextLength = contextLength
        self.useGPUIfAvailable = useGPUIfAvailable
        self.quantizationLevel = quantizationLevel
        self.cacheSize = cacheSize
        self.preloadContext = preloadContext
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt ?? preloadContext
        self.streamingEnabled = streamingEnabled
    }

    public func validate() throws {
        guard contextLength > 0 && contextLength <= 32768 else {
            throw SDKError.validationFailed("Context length must be between 1 and 32768")
        }
        guard cacheSize >= 0 && cacheSize <= 1000 else {
            throw SDKError.validationFailed("Cache size must be between 0 and 1000 MB")
        }
    }
}

// MARK: - LLM Service Protocol

/// Protocol for language model services
public protocol LLMService: AnyObject {
    /// Initialize the LLM service
    func initialize(modelPath: String?) async throws

    /// Generate text from a prompt
    func generate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ) async throws -> String

    /// Stream generation token by token
    func streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws

    /// Check if service is ready
    var isReady: Bool { get }

    /// Get current model identifier
    var currentModel: String? { get }

    /// Cleanup resources
    func cleanup() async
}
