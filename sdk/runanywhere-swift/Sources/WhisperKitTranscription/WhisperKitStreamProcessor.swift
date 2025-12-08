import Foundation
import RunAnywhere
import WhisperKit

/// Helper for processing streaming audio with WhisperKit
struct WhisperKitStreamProcessor {
    private let logger = SDKLogger(category: "WhisperKitStream")
    private let minAudioLength = 8000  // 500ms at 16kHz
    private let contextOverlap = 1600   // 100ms overlap for context

    func processStream(
        whisperKit: WhisperKit,
        audioStream: AsyncStream<VoiceAudioChunk>,
        options: STTOptions,
        continuation: AsyncThrowingStream<STTSegment, Error>.Continuation
    ) async throws {
        var audioBuffer = Data()
        var lastTranscript = ""

        for await chunk in audioStream {
            audioBuffer.append(chunk.data)

            // Process when we have enough audio (500ms)
            if audioBuffer.count >= minAudioLength {
                if let segment = try await processAudioChunk(
                    whisperKit: whisperKit,
                    audioBuffer: audioBuffer,
                    lastTranscript: lastTranscript,
                    timestamp: chunk.timestamp,
                    options: options
                ) {
                    continuation.yield(segment)
                    lastTranscript = segment.text
                }

                // Keep last 100ms for context continuity
                audioBuffer = Data(audioBuffer.suffix(contextOverlap))
            }
        }

        // Process any remaining audio
        if !audioBuffer.isEmpty {
            if let segment = try await processFinalChunk(
                whisperKit: whisperKit,
                audioBuffer: audioBuffer,
                options: options
            ) {
                continuation.yield(segment)
            }
        }

        continuation.finish()
    }

    private func processAudioChunk(
        whisperKit: WhisperKit,
        audioBuffer: Data,
        lastTranscript: String,
        timestamp: TimeInterval,
        options: STTOptions
    ) async throws -> STTSegment? {
        let floatArray = audioBuffer.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        let decodingOptions = createStreamingDecodingOptions(language: options.language)
        let results = try await whisperKit.transcribe(audioArray: floatArray, decodeOptions: decodingOptions)

        // Get the transcribed text
        if let result = results.first {
            let newText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Only yield if there's new content
            if !newText.isEmpty && newText != lastTranscript {
                return STTSegment(
                    text: newText,
                    startTime: timestamp - 0.5,
                    endTime: timestamp,
                    confidence: 0.95
                )
            }
        }

        return nil
    }

    private func processFinalChunk(
        whisperKit: WhisperKit,
        audioBuffer: Data,
        options: STTOptions
    ) async throws -> STTSegment? {
        let floatArray = audioBuffer.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        let decodingOptions = createStreamingDecodingOptions(language: options.language)
        let results = try await whisperKit.transcribe(audioArray: floatArray, decodeOptions: decodingOptions)

        if let result = results.first {
            return STTSegment(
                text: result.text,
                startTime: Date().timeIntervalSince1970 - 0.1,
                endTime: Date().timeIntervalSince1970,
                confidence: 0.95
            )
        }

        return nil
    }

    private func createStreamingDecodingOptions(language: String) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            temperatureFallbackCount: 0,
            sampleLength: 224,
            usePrefillPrompt: false,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false
        )
    }
}
