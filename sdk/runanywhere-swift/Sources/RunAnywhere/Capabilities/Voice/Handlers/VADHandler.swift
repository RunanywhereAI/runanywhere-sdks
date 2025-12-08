import AVFoundation
import Foundation

/// Temporary bridge handler for VAD to work with existing VoicePipelineManager
/// This will be removed once VoicePipelineManager is refactored to use the new component architecture
@MainActor
public final class VADHandler {
    private let logger = SDKLogger(category: "VADHandler")
    private var vadComponent: VADComponent?

    public init() {}

    /// Process audio buffer for VAD
    public func processAudioBuffer(_ buffer: AVAudioPCMBuffer, vadService: VADService?) async throws -> Bool {
        // If a VAD service is provided, use it directly
        if let vadService = vadService {
            vadService.processAudioBuffer(buffer)
            return vadService.isSpeechActive
        }

        // Otherwise, try to use the component
        if vadComponent == nil {
            // Create a default VAD component
            let config = VADConfiguration()
            vadComponent = VADComponent(configuration: config)
            try await vadComponent?.initialize()
        }

        guard let vadComponent = vadComponent else {
            logger.warning("No VAD service available")
            return false
        }

        let output = try await vadComponent.detectSpeech(in: buffer)
        return output.isSpeechDetected
    }


    /// Reset the handler
    public func reset() {
        vadComponent?.reset()
    }
}
