import Foundation

// MARK: - Base Protocol for Component Parameters

/// Base protocol for all component initialization parameters
public protocol ComponentInitParameters: Sendable {
    /// The component type this configuration is for
    var componentType: SDKComponent { get }

    /// Model ID if required by the component
    var modelId: String? { get }

    /// Validate the parameters
    func validate() throws
}

// NOTE: Component-specific parameters are defined in their respective files:
// - LLMInitParameters: Components/LLM/LLMComponent.swift
// - STTInitParameters: Components/STT/STTInitParameters.swift
// - TTSInitParameters: Components/TTS/TTSInitParameters.swift
// - VADInitParameters: Components/VAD/VADInitParameters.swift
// - SpeakerDiarizationInitParameters: Components/SpeakerDiarization/SpeakerDiarizationComponent.swift


// MARK: - Embedding Component Parameters

/// Initialization parameters for Embedding component
public struct EmbeddingInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.embedding
    public let modelId: String?

    // Embedding-specific parameters
    public let dimensions: Int
    public let maxSequenceLength: Int
    public let poolingStrategy: PoolingStrategy
    public let normalize: Bool
    public let useGPUIfAvailable: Bool

    public enum PoolingStrategy: String, Sendable {
        case mean = "mean"
        case max = "max"
        case cls = "cls" // Use CLS token (for BERT-like models)
        case lastToken = "last_token"
    }

    public init(
        modelId: String? = nil,
        dimensions: Int = 768,
        maxSequenceLength: Int = 512,
        poolingStrategy: PoolingStrategy = .mean,
        normalize: Bool = true,
        useGPUIfAvailable: Bool = true
    ) {
        self.modelId = modelId
        self.dimensions = dimensions
        self.maxSequenceLength = maxSequenceLength
        self.poolingStrategy = poolingStrategy
        self.normalize = normalize
        self.useGPUIfAvailable = useGPUIfAvailable
    }

    public func validate() throws {
        let validDimensions = [128, 256, 384, 512, 768, 1024, 1536, 2048]
        guard validDimensions.contains(dimensions) else {
            throw SDKError.validationFailed("Dimensions must be one of: \(validDimensions)")
        }
        guard maxSequenceLength > 0 && maxSequenceLength <= 8192 else {
            throw SDKError.validationFailed("Max sequence length must be between 1 and 8192")
        }
    }
}

// MARK: - Unified Configuration

/// Unified configuration that can hold any component's parameters
public struct UnifiedComponentConfig: Sendable {
    public let component: SDKComponent
    public let parameters: any ComponentInitParameters
    public let priority: InitializationPriority
    public let downloadPolicy: DownloadPolicy

    public init(
        parameters: any ComponentInitParameters,
        priority: InitializationPriority = .normal,
        downloadPolicy: DownloadPolicy = .automatic
    ) {
        self.component = parameters.componentType
        self.parameters = parameters
        self.priority = priority
        self.downloadPolicy = downloadPolicy
    }

    /// Convenience initializers for each component type
    public static func llm(
        _ params: LLMInitParameters,
        priority: InitializationPriority = .normal,
        downloadPolicy: DownloadPolicy = .automatic
    ) -> UnifiedComponentConfig {
        UnifiedComponentConfig(parameters: params, priority: priority, downloadPolicy: downloadPolicy)
    }

    public static func stt(
        _ params: STTInitParameters,
        priority: InitializationPriority = .normal,
        downloadPolicy: DownloadPolicy = .automatic
    ) -> UnifiedComponentConfig {
        UnifiedComponentConfig(parameters: params, priority: priority, downloadPolicy: downloadPolicy)
    }

    public static func tts(
        _ params: TTSInitParameters,
        priority: InitializationPriority = .normal
    ) -> UnifiedComponentConfig {
        UnifiedComponentConfig(parameters: params, priority: priority)
    }

    public static func vad(
        _ params: VADInitParameters,
        priority: InitializationPriority = .normal
    ) -> UnifiedComponentConfig {
        UnifiedComponentConfig(parameters: params, priority: priority)
    }

    public static func vlm(
        _ params: VLMInitParameters,
        priority: InitializationPriority = .normal,
        downloadPolicy: DownloadPolicy = .automatic
    ) -> UnifiedComponentConfig {
        UnifiedComponentConfig(parameters: params, priority: priority, downloadPolicy: downloadPolicy)
    }

    public static func embedding(
        _ params: EmbeddingInitParameters,
        priority: InitializationPriority = .normal,
        downloadPolicy: DownloadPolicy = .automatic
    ) -> UnifiedComponentConfig {
        UnifiedComponentConfig(parameters: params, priority: priority, downloadPolicy: downloadPolicy)
    }

    public static func speakerDiarization(
        _ params: SpeakerDiarizationInitParameters,
        priority: InitializationPriority = .normal
    ) -> UnifiedComponentConfig {
        UnifiedComponentConfig(parameters: params, priority: priority)
    }
}
