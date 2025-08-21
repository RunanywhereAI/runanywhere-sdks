import Foundation
import RunAnywhereSDK
import os
import FluidAudioDiarization  // Direct import since it's added to the project

/// Helper class to integrate FluidAudioDiarization with the app
@MainActor
class FluidAudioIntegration {
    private static let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "FluidAudioIntegration")

    /// Create FluidAudioDiarization service
    static func createDiarizationService() async -> SpeakerDiarizationProtocol? {
        do {
            logger.info("Initializing FluidAudioDiarization...")
            let diarization = try await FluidAudioDiarization(threshold: 0.65)  // Lower threshold for better speaker separation
            logger.info("✅ FluidAudioDiarization initialized successfully")
            return diarization
        } catch {
            logger.error("Failed to initialize FluidAudioDiarization: \(error)")
            logger.error("Falling back to default diarization")
            return nil
        }
    }

    /// Create a voice pipeline with FluidAudio diarization
    static func createVoicePipelineWithDiarization(
        sdk: RunAnywhereSDK,
        config: ModularPipelineConfig
    ) async -> ModularVoicePipeline {
        // Try to create FluidAudio diarization
        let diarizationService = await createDiarizationService()

        if let diarization = diarizationService {
            logger.info("Creating voice pipeline with FluidAudioDiarization")
            return sdk.createVoicePipeline(
                config: config,
                speakerDiarization: diarization
            )
        } else {
            logger.info("Creating voice pipeline with default diarization")
            return sdk.createVoicePipeline(config: config)
        }
    }
}
