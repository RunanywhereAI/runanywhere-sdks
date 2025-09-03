import Foundation

// MARK: - Speaker Diarization Component

/// Speaker Diarization component implementation
@MainActor
public final class SpeakerDiarizationComponent: BaseComponent, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .speakerDiarization }

    private nonisolated(unsafe) var diarizationService: SpeakerDiarizationService?

    // MARK: - Component Implementation

    public override func initialize(with parameters: any ComponentInitParameters) async throws {
        guard parameters is SpeakerDiarizationInitParameters else {
            throw SDKError.validationFailed("Invalid parameters type for Speaker Diarization")
        }

        try await super.initialize(with: parameters)

        // Speaker diarization typically uses built-in service, not adapter
        // Initialize with DefaultSpeakerDiarization
        if let container = serviceContainer {
            diarizationService = DefaultSpeakerDiarization()
        }

        await transitionTo(state: .ready)
    }

    public override func cleanup() async throws {
        diarizationService = nil
        try await super.cleanup()
    }

    public func getService() -> SpeakerDiarizationService? {
        return diarizationService
    }
}

// MARK: - Speaker Diarization Initialization Parameters

/// Initialization parameters for Speaker Diarization component
public struct SpeakerDiarizationInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.speakerDiarization
    public let modelId: String? = nil // Uses lightweight built-in algorithm

    // Speaker Diarization-specific parameters
    public let maxSpeakers: Int
    public let minSpeechDuration: TimeInterval
    public let speakerChangeThreshold: Float
    public let clusteringAlgorithm: ClusteringAlgorithm
    public let embeddingWindowSize: TimeInterval

    public enum ClusteringAlgorithm: String, Sendable {
        case agglomerative = "agglomerative"
        case spectral = "spectral"
        case kmeans = "kmeans"
    }

    public init(
        maxSpeakers: Int = 4,
        minSpeechDuration: TimeInterval = 0.5,
        speakerChangeThreshold: Float = 0.5,
        clusteringAlgorithm: ClusteringAlgorithm = .agglomerative,
        embeddingWindowSize: TimeInterval = 1.5
    ) {
        self.maxSpeakers = maxSpeakers
        self.minSpeechDuration = minSpeechDuration
        self.speakerChangeThreshold = speakerChangeThreshold
        self.clusteringAlgorithm = clusteringAlgorithm
        self.embeddingWindowSize = embeddingWindowSize
    }

    public func validate() throws {
        guard maxSpeakers > 0 && maxSpeakers <= 10 else {
            throw SDKError.validationFailed("Max speakers must be between 1 and 10")
        }
        guard minSpeechDuration > 0 && minSpeechDuration <= 5.0 else {
            throw SDKError.validationFailed("Min speech duration must be between 0 and 5 seconds")
        }
        guard speakerChangeThreshold >= 0.0 && speakerChangeThreshold <= 1.0 else {
            throw SDKError.validationFailed("Speaker change threshold must be between 0.0 and 1.0")
        }
        guard embeddingWindowSize > 0 && embeddingWindowSize <= 10.0 else {
            throw SDKError.validationFailed("Embedding window size must be between 0 and 10 seconds")
        }
    }
}
