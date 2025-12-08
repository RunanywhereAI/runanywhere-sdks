import Foundation
import RunAnywhere

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
    private let logger = SDKLogger(category: "FluidAudioDiarizationProvider")

    // MARK: - Singleton for easy registration

    public static let shared = FluidAudioDiarizationProvider()

    /// Super simple registration - just call this in your app
    @MainActor
    public static func register() {
        ModuleRegistry.shared.registerSpeakerDiarization(shared)
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

        // Create FluidAudioDiarization service directly
        let threshold: Float = 0.65  // Default threshold
        let service = try await FluidAudioDiarization(threshold: threshold)

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
    @MainActor
    public static func autoRegister() {
        FluidAudioDiarizationProvider.register()
    }
}
