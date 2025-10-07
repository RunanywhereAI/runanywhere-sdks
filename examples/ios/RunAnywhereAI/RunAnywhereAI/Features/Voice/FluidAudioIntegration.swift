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
            // Use a threshold between standard (0.65) and measured distance (0.26)
            // 0.45 provides good balance for similar speakers while avoiding over-segmentation
            let diarization = try await FluidAudioDiarization(threshold: 0.45)
            logger.info("FluidAudioDiarization initialized successfully")
            return diarization
        } catch {
            logger.error("Failed to initialize FluidAudioDiarization: \(error)")
            return nil
        }
    }

    /// Create a voice pipeline with FluidAudio diarization
    static func createVoicePipelineWithDiarization(
        sdk: RunAnywhereSDK,
        config: ModularPipelineConfig
    ) async -> VoicePipelineManager {
        // Try to create FluidAudio diarization
        let diarizationService = await createDiarizationService()

        if let diarization = diarizationService {
            // Use smart phrase segmentation for better diarization accuracy
            let segmentationStrategy = SmartPhraseSegmentation(
                minimumPhraseLength: 3.0,   // Minimum 3 seconds for reliable diarization
                optimalPhraseLength: 8.0,   // 8 seconds is optimal for speaker identification
                phraseEndSilence: 2.0,      // 2 seconds of silence indicates phrase end
                briefPauseThreshold: 0.5    // Brief pauses (breathing) don't trigger processing
            )

            let pipeline = sdk.createVoicePipeline(
                config: config,
                speakerDiarization: diarization,
                segmentationStrategy: segmentationStrategy
            )
            logger.debug("Pipeline created with FluidAudio diarization")
            return pipeline
        } else {
            logger.info("Using default diarization (FluidAudio unavailable)")
            return sdk.createVoicePipeline(config: config)
        }
    }
}
