import Foundation
import os

/// Handles speaker diarization processing in the voice pipeline
public class SpeakerDiarizationHandler {
    private let logger = SDKLogger(category: "SpeakerDiarizationHandler")

    public init() {}

    /// Detect speaker from audio samples
    /// - Parameters:
    ///   - samples: Audio samples to analyze
    ///   - service: Speaker diarization service
    ///   - sampleRate: Audio sample rate
    /// - Returns: Detected speaker information
    public func detectSpeaker(
        from samples: [Float],
        service: SpeakerDiarizationService,
        sampleRate: Int = 16000
    ) -> SpeakerInfo {
        // Process audio to identify speaker
        return service.processAudio(samples)
    }

    /// Handle speaker change detection and notification
    /// - Parameters:
    ///   - previous: Previous speaker (if any)
    ///   - current: Current speaker
    ///   - continuation: Event stream continuation
    public func handleSpeakerChange(
        previous: SpeakerInfo?,
        current: SpeakerInfo,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) {
        if previous?.id != current.id {
            continuation.yield(.sttSpeakerChanged(from: previous, to: current))
            logger.info("Speaker changed from \(previous?.name ?? previous?.id ?? "unknown") to \(current.name ?? current.id)")
        }
    }

    /// Emit transcript with speaker information
    /// - Parameters:
    ///   - transcript: The transcript text
    ///   - speaker: Speaker information
    ///   - continuation: Event stream continuation
    public func emitTranscriptWithSpeaker(
        transcript: String,
        speaker: SpeakerInfo,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) {
        continuation.yield(.sttFinalTranscriptWithSpeaker(transcript, speaker))
        logger.info("Transcript with speaker \(speaker.name ?? speaker.id): '\(transcript)'")
    }
}
