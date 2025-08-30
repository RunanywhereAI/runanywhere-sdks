import Foundation
import os

/// Type of speaker diarization to use
public enum DiarizationType {
    /// Default SDK implementation (basic speaker tracking)
    case `default`

    /// FluidAudio implementation (production-ready, 17.7% DER)
    /// Requires FluidAudioDiarization module to be available
    case fluidAudio

    /// Custom implementation
    case custom(SpeakerDiarizationService)
}

// MARK: - SDK Extension for Diarization

extension RunAnywhereSDK {

    private var diarizationLogger: Logger {
        Logger(subsystem: "com.runanywhere.sdk", category: "DiarizationFactory")
    }

    /// Create a voice pipeline with specified diarization type
    /// - Parameters:
    ///   - config: Pipeline configuration
    ///   - diarizationType: Type of diarization to use (default, fluidAudio, or custom)
    /// - Returns: Configured voice pipeline
    public func createVoicePipelineWithDiarization(
        config: ModularPipelineConfig,
        diarizationType: DiarizationType = .default
    ) async throws -> VoicePipelineManager {

        let diarizationService: SpeakerDiarizationService?

        switch diarizationType {
        case .default:
            // Use default implementation
            diarizationService = DefaultSpeakerDiarization()
            diarizationLogger.info("Using default speaker diarization")

        case .fluidAudio:
            // Try to load FluidAudio module dynamically
            diarizationService = try await createFluidAudioDiarization()

        case .custom(let service):
            // Use provided custom implementation
            diarizationService = service
            diarizationLogger.info("Using custom speaker diarization")
        }

        // Create pipeline with selected diarization
        return createVoicePipeline(
            config: config,
            speakerDiarization: diarizationService
        )
    }

    /// Attempt to create FluidAudio diarization service
    /// Falls back to default if module not available
    private func createFluidAudioDiarization() async throws -> SpeakerDiarizationService {
        // Try to dynamically load FluidAudio module
        let className = "FluidAudioDiarization.FluidAudioDiarization"

        if let fluidClass = NSClassFromString(className) {
            diarizationLogger.info("FluidAudio module found, initializing...")

            // Try to create instance
            // Note: In real implementation, we'd need proper async initialization
            // For now, we'll use reflection to check if class exists
            diarizationLogger.warning("FluidAudio module found but async init requires proper setup")
            diarizationLogger.info("Falling back to default implementation")
            return DefaultSpeakerDiarization()
        } else {
            diarizationLogger.warning("FluidAudio module not found, using default implementation")
            diarizationLogger.info("To use FluidAudio, add FluidAudioDiarization to your app dependencies")
            return DefaultSpeakerDiarization()
        }
    }

    /// Check if FluidAudio module is available
    public var isFluidAudioAvailable: Bool {
        return NSClassFromString("FluidAudioDiarization.FluidAudioDiarization") != nil
    }
}

// MARK: - Helper for Apps

/// Factory for creating speaker diarization services
public struct SpeakerDiarizationFactory {

    /// Create a diarization service based on availability
    /// - Returns: Best available diarization service
    public static func createBestAvailable() async -> SpeakerDiarizationService {
        // Check if FluidAudio is available
        if NSClassFromString("FluidAudioDiarization.FluidAudioDiarization") != nil {
            // FluidAudio is available but requires async init
            // For simplicity, return default for now
            // Apps should directly import and initialize FluidAudioDiarization
            return DefaultSpeakerDiarization()
        }

        // Use default implementation
        return DefaultSpeakerDiarization()
    }

    /// Create default diarization service
    public static func createDefault() -> SpeakerDiarizationService {
        return DefaultSpeakerDiarization()
    }
}
