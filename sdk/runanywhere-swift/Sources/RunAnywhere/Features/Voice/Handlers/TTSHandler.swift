import Foundation

/// Handles Text-to-Speech processing in the voice pipeline
public class TTSHandler {
    private let logger = SDKLogger(category: "TTSHandler")

    public init() {}

    /// Convert text to speech
    /// - Parameters:
    ///   - text: Text to speak
    ///   - service: TTS service to use
    ///   - config: TTS configuration
    ///   - continuation: Event stream continuation
    public func speakText(
        text: String,
        service: TTSService,
        config: TTSConfiguration?,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws {

        guard !text.isEmpty else {
            logger.debug("speakText called with empty text, skipping")
            return
        }

        continuation.yield(.ttsStarted)

        let ttsOptions = createTTSOptions(config: config)

        do {
            // Synthesize the text to audio
            _ = try await service.synthesize(text: text, options: ttsOptions)
            continuation.yield(.ttsCompleted)
            logger.info("TTS completed for text: \(text.prefix(50))...")
        } catch {
            logger.error("TTS failed: \(error)")
            throw error
        }
    }

    /// Create TTS options from configuration
    /// - Parameter config: TTS configuration
    /// - Returns: TTS options
    public func createTTSOptions(config: TTSConfiguration?) -> TTSOptions {
        return TTSOptions(
            voice: config?.voice,
            language: config?.language ?? "en",
            rate: config?.speakingRate ?? 1.0,
            pitch: config?.pitch ?? 1.0,
            volume: config?.volume ?? 1.0
        )
    }
}
