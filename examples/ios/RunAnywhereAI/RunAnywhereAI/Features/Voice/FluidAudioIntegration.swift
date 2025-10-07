import Foundation
import RunAnywhere
import os
import FluidAudioDiarization  // Direct import since it's added to the project

/// Helper class to integrate FluidAudioDiarization with the app
@MainActor
class FluidAudioIntegration {
    private static let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "FluidAudioIntegration")

    /// Create FluidAudioDiarization service
    static func createDiarizationService() async -> SpeakerDiarizationService? {
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
        config: ModularPipelineConfig
    ) async -> ModularVoicePipeline? {
        // Try to create FluidAudio diarization
        let diarizationService = await createDiarizationService()

        do {
            // Create pipeline with diarization service
            if let diarization = diarizationService {
                logger.info("Creating voice pipeline with FluidAudio diarization")
                let pipeline = try await ModularVoicePipeline(
                    config: config,
                    speakerDiarization: diarization
                )

                // Enable speaker diarization
                pipeline.enableSpeakerDiarization(true)

                return pipeline
            } else {
                logger.info("Creating standard voice pipeline (diarization not available)")
                return try await RunAnywhere.createVoicePipeline(config: config)
            }
        } catch {
            logger.error("Failed to create voice pipeline: \(error)")
            return nil
        }
    }
}
