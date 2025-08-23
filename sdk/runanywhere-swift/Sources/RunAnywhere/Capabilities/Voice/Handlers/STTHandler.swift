import Foundation
import os

/// Handles Speech-to-Text processing in the voice pipeline
public class STTHandler {
    private let logger = SDKLogger(category: "STTHandler")
    private let voiceAnalytics: VoiceAnalyticsService?
    private let sttAnalytics: STTAnalyticsService?

    public init(
        voiceAnalytics: VoiceAnalyticsService? = nil,
        sttAnalytics: STTAnalyticsService? = nil
    ) {
        self.voiceAnalytics = voiceAnalytics
        self.sttAnalytics = sttAnalytics
    }

    /// Transcribe audio samples to text
    /// - Parameters:
    ///   - samples: Audio samples to transcribe
    ///   - service: Voice service to use for transcription
    ///   - options: Transcription options
    ///   - speakerDiarization: Optional speaker diarization service
    ///   - continuation: Event stream continuation
    /// - Returns: Transcription result
    public func transcribeAudio(
        samples: [Float],
        service: VoiceService,
        options: VoiceTranscriptionOptions,
        speakerDiarization: SpeakerDiarizationProtocol?,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws -> String {

        guard !samples.isEmpty else {
            logger.debug("transcribeAudio called with empty samples, skipping")
            return ""
        }

        logger.debug("Starting transcription with \(samples.count) samples")

        // Calculate audio length
        let audioLength = TimeInterval(samples.count) / 16000.0 // Assuming 16kHz sample rate

        // Track transcription start
        await sttAnalytics?.trackTranscriptionStarted(audioLength: audioLength)
        await voiceAnalytics?.trackTranscriptionStarted(audioLength: audioLength)

        let startTime = Date()

        do {
            // Get transcription result based on service's preferred format
            let result = try await performTranscription(
                samples: samples,
                service: service,
                options: options
            )

            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)

            let transcript = result.text
            logger.info("STT transcription result: '\(transcript)'")

            if !transcript.isEmpty {
                // Track successful transcription completion
                let wordCount = transcript.split(separator: " ").count
                let confidence = result.confidence ?? 0.8 // Default confidence if not provided

                await sttAnalytics?.trackTranscription(
                    text: transcript,
                    confidence: confidence,
                    duration: duration,
                    audioLength: audioLength
                )

                await voiceAnalytics?.trackTranscription(
                    duration: duration,
                    wordCount: wordCount,
                    audioLength: audioLength
                )

                await sttAnalytics?.trackFinalTranscript(
                    text: transcript,
                    confidence: confidence
                )
                // Handle speaker diarization if available
                if let diarizationService = speakerDiarization,
                   options.enableSpeakerDiarization {
                    handleSpeakerDiarization(
                        samples: samples,
                        transcript: transcript,
                        service: diarizationService,
                        continuation: continuation
                    )
                } else {
                    // Regular transcript without speaker info
                    continuation.yield(.sttFinalTranscript(transcript))
                }
                return transcript
            } else {
                logger.warning("STT returned empty transcript")
                return ""
            }
        } catch {
            logger.error("STT transcription failed: \(error)")

            // Track transcription error
            await sttAnalytics?.trackError(error: error, context: .transcription)
            await voiceAnalytics?.trackError(error: error, context: .transcription)

            throw error
        }
    }

    // MARK: - Private Methods

    private func performTranscription(
        samples: [Float],
        service: VoiceService,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {

        let preferredFormat = service.preferredAudioFormat
        logger.debug("STT service prefers \(preferredFormat) format")

        if preferredFormat == .floatArray {
            // Service prefers Float arrays - pass directly
            logger.debug("Using Float array transcription with \(samples.count) samples")
            return try await service.transcribe(
                samples: samples,
                options: options
            )
        } else {
            // Service prefers Data - convert Float array to Data
            logger.debug("Converting \(samples.count) float samples to Data")
            let audioData = convertAudioFormat(samples: samples)
            logger.debug("Calling STT.transcribe with \(audioData.count) bytes")
            return try await service.transcribe(
                audio: audioData,
                options: options
            )
        }
    }

    private func convertAudioFormat(samples: [Float]) -> Data {
        return samples.withUnsafeBytes { bytes in
            Data(bytes)
        }
    }

    private func handleSpeakerDiarization(
        samples: [Float],
        transcript: String,
        service: SpeakerDiarizationProtocol,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) {
        // Detect speaker from audio features
        let speaker = service.detectSpeaker(
            from: samples,
            sampleRate: 16000
        )

        // Track speaker detection
        Task {
            await sttAnalytics?.trackSpeakerDetection(
                speaker: speaker.id,
                confidence: 0.8 // Default confidence for speaker detection
            )
        }

        // Check if speaker changed
        let previousSpeaker = service.getCurrentSpeaker()
        if previousSpeaker?.id != speaker.id {
            continuation.yield(.sttSpeakerChanged(from: previousSpeaker, to: speaker))

            // Track speaker change
            Task {
                await sttAnalytics?.trackSpeakerChange(
                    from: previousSpeaker?.id,
                    to: speaker.id
                )
            }
        }

        // Emit transcript with speaker info
        continuation.yield(.sttFinalTranscriptWithSpeaker(transcript, speaker))
        logger.info("Transcript with speaker \(speaker.name ?? speaker.id): '\(transcript)'")
    }
}
