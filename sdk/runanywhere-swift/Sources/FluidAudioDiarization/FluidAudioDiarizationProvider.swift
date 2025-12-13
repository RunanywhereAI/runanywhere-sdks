//
//  FluidAudioDiarizationModule.swift
//  FluidAudioDiarization Module
//
//  Simple registration for FluidAudio Speaker Diarization services
//

import Foundation
import RunAnywhere

// MARK: - FluidAudio Module Registration

/// FluidAudio module for Speaker Diarization
///
/// Usage:
/// ```swift
/// import FluidAudioDiarization
///
/// // Register at app startup
/// FluidAudio.register()
///
/// // Then use via RunAnywhere
/// let capability = SpeakerDiarizationCapability()
/// try await capability.initialize()
/// let speaker = try await capability.processAudio(samples)
/// ```
public enum FluidAudio {
    private static let logger = SDKLogger(category: "FluidAudio")

    /// Register FluidAudio Speaker Diarization service with the SDK
    @MainActor
    public static func register(priority: Int = 100) {
        ServiceRegistry.shared.registerSpeakerDiarization(
            name: "FluidAudio",
            priority: priority,
            canHandle: { _ in true }, // FluidAudio can handle all diarization requests
            factory: { config in
                try await createService(config: config)
            }
        )
        logger.info("FluidAudio Speaker Diarization registered")
    }

    // MARK: - Private Helpers

    private static func createService(config: SpeakerDiarizationConfiguration) async throws -> SpeakerDiarizationService {
        logger.info("Creating FluidAudio diarization service")

        let threshold: Float = 0.65 // Default threshold
        let service = try await FluidAudioDiarization(threshold: threshold)

        logger.info("FluidAudio service created successfully")
        return service
    }
}
