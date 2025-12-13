//
//  RunAnywhere+STT.swift
//  RunAnywhere SDK
//
//  Public API for Speech-to-Text operations
//

@preconcurrency import AVFoundation
import Foundation

// MARK: - STT Operations

public extension RunAnywhere {

    // MARK: - Model Loading
    // Note: loadSTTModel is defined in RunAnywhere.swift

    /// Unload the currently loaded STT model
    static func unloadSTTModel() async throws {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        try await serviceContainer.sttCapability.unload()
    }

    /// Check if an STT model is loaded
    static var isSTTModelLoaded: Bool {
        get async {
            await serviceContainer.sttCapability.isModelLoaded
        }
    }

    // MARK: - Transcription

    /// Transcribe audio data to text (with options)
    /// - Parameters:
    ///   - audioData: Raw audio data
    ///   - options: Transcription options
    /// - Returns: Transcription output with text and metadata
    static func transcribeWithOptions(
        _ audioData: Data,
        options: STTOptions
    ) async throws -> STTOutput {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        events.publishAsync(SDKVoiceEvent.transcriptionStarted)

        do {
            let result = try await serviceContainer.sttCapability.transcribe(audioData, options: options)
            events.publishAsync(SDKVoiceEvent.transcriptionFinal(text: result.text))
            return result
        } catch {
            events.publishAsync(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    /// Transcribe audio buffer to text
    /// - Parameters:
    ///   - buffer: Audio buffer
    ///   - language: Optional language hint
    /// - Returns: Transcription output
    static func transcribeBuffer(
        _ buffer: AVAudioPCMBuffer,
        language: String? = nil
    ) async throws -> STTOutput {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        events.publishAsync(SDKVoiceEvent.transcriptionStarted)

        do {
            let result = try await serviceContainer.sttCapability.transcribe(buffer, language: language)
            events.publishAsync(SDKVoiceEvent.transcriptionFinal(text: result.text))
            return result
        } catch {
            events.publishAsync(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    /// Stream transcription for real-time processing
    /// - Parameters:
    ///   - audioStream: Async stream of audio data chunks
    ///   - options: Transcription options
    /// - Returns: Async stream of transcription text
    static func transcribeStream<S: AsyncSequence>(
        _ audioStream: S,
        options: STTOptions = STTOptions()
    ) async throws -> AsyncThrowingStream<String, Error> where S.Element == Data {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        events.publishAsync(SDKVoiceEvent.transcriptionStarted)

        return await serviceContainer.sttCapability.streamTranscribe(audioStream, options: options)
    }
}
