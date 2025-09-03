import Foundation
import RunAnywhere
import os

/// FluidAudioDiarization provider for Speaker Diarization services
///
/// Usage:
/// ```swift
/// import FluidAudioDiarization
///
/// // In your app initialization:
/// FluidAudioDiarizationProvider.register()
/// ```
public final class FluidAudioDiarizationProvider: SpeakerDiarizationServiceProvider {
    private let logger = Logger(subsystem: "com.runanywhere.fluiddiarization", category: "FluidAudioDiarizationProvider")

    // MARK: - Singleton for easy registration

    public static let shared = FluidAudioDiarizationProvider()

    /// Super simple registration - just call this in your app
    public static func register() {
        Task { @MainActor in
            ModuleRegistry.shared.registerSpeakerDiarization(shared)
        }
    }

    // MARK: - SpeakerDiarizationServiceProvider Protocol

    public var name: String {
        "FluidAudioDiarization"
    }

    public func canHandle(modelId: String?) -> Bool {
        // FluidAudioDiarization can handle any speaker diarization request
        // It doesn't require specific model IDs
        return true
    }

    public func createSpeakerDiarizationService(configuration: SpeakerDiarizationConfiguration) async throws -> SpeakerDiarizationService {
        logger.info("Creating FluidAudioDiarization service")

        // Create the service
        let service = FluidDiarizationService(
            maxSpeakers: configuration.maxSpeakers,
            minSpeechDuration: configuration.minSpeechDuration
        )

        // Initialize the service
        try await service.initialize()

        logger.info("FluidAudioDiarization service created successfully")
        return service
    }

    // MARK: - Private initializer to enforce singleton

    private init() {
        logger.info("FluidAudioDiarizationProvider initialized")
    }
}

// MARK: - Auto Registration Support

/// Automatic registration when module is imported
public enum FluidAudioDiarizationModule {
    /// Call this to automatically register FluidAudioDiarization with the SDK
    public static func autoRegister() {
        FluidAudioDiarizationProvider.register()
    }
}

// MARK: - FluidDiarizationService Implementation

/// Actual service implementation for FluidAudioDiarization
/// This is a placeholder - the real implementation would be in the external module
private final class FluidDiarizationService: SpeakerDiarizationService {
    private let maxSpeakers: Int
    private let minSpeechDuration: Double
    private var speakers: [SpeakerInfo] = []
    private var isInitialized = false

    init(maxSpeakers: Int, minSpeechDuration: Double) {
        self.maxSpeakers = maxSpeakers
        self.minSpeechDuration = minSpeechDuration
    }

    func initialize() async throws {
        // Initialize the diarization model
        // In real implementation, this would load the model
        isInitialized = true
    }

    func processAudio(_ samples: [Float]) -> SpeakerInfo {
        // Process audio to identify speaker
        // This is a placeholder implementation
        let speakerId = "speaker_1"
        let speaker = SpeakerInfo(
            id: speakerId,
            name: "Speaker 1",
            confidence: 0.95,
            embedding: Array(repeating: 0.0, count: 256)
        )

        if !speakers.contains(where: { $0.id == speakerId }) {
            speakers.append(speaker)
        }

        return speaker
    }

    func reset() {
        speakers.removeAll()
    }

    func getAllSpeakers() -> [SpeakerInfo] {
        return speakers
    }

    var isReady: Bool {
        return isInitialized
    }

    func cleanup() async {
        speakers.removeAll()
        isInitialized = false
    }
}
