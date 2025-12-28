//
//  RunAnywhere+STT.swift
//  RunAnywhere SDK
//
//  Public API for Speech-to-Text operations.
//  Events are tracked via EventPublisher.
//

@preconcurrency import AVFoundation
import Foundation

// MARK: - STT Operations

public extension RunAnywhere {

    // MARK: - Simple Transcription

    /// Simple voice transcription using default model
    /// - Parameter audioData: Audio data to transcribe
    /// - Returns: Transcribed text
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    static func transcribe(_ audioData: Data) async throws -> String {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        // STTCapability handles all event tracking automatically
        let result = try await serviceContainer.sttCapability.transcribe(audioData)
        return result.text
    }

    // MARK: - Model Loading

    /// Unload the currently loaded STT model
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    static func unloadSTTModel() async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
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
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    static func transcribeWithOptions(
        _ audioData: Data,
        options: STTOptions
    ) async throws -> STTOutput {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        return try await serviceContainer.sttCapability.transcribe(audioData, options: options)
    }

    /// Transcribe audio buffer to text
    /// - Parameters:
    ///   - buffer: Audio buffer
    ///   - language: Optional language hint
    /// - Returns: Transcription output
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    static func transcribeBuffer(
        _ buffer: AVAudioPCMBuffer,
        language: String? = nil
    ) async throws -> STTOutput {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        // Convert AVAudioPCMBuffer to Data
        guard let channelData = buffer.floatChannelData else {
            throw SDKError.stt(.emptyAudioBuffer, "Audio buffer has no channel data")
        }

        let frameLength = Int(buffer.frameLength)
        let audioData = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)

        // Build options with language if provided
        let options: STTOptions
        if let language = language {
            options = STTOptions(language: language)
        } else {
            options = STTOptions()
        }

        return try await serviceContainer.sttCapability.transcribe(audioData, options: options)
    }

    /// Start streaming transcription
    /// - Parameters:
    ///   - options: Transcription options
    ///   - onPartialResult: Callback for partial transcription results
    ///   - onFinalResult: Callback for final transcription result
    ///   - onError: Callback for errors
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    static func startStreamingTranscription(
        options: STTOptions = STTOptions(),
        onPartialResult: @escaping (STTTranscriptionResult) -> Void,
        onFinalResult: @escaping (STTOutput) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await serviceContainer.sttCapability.startStreamingTranscription(
            options: options,
            onPartialResult: onPartialResult,
            onFinalResult: onFinalResult,
            onError: onError
        )
    }

    /// Process audio samples for streaming transcription
    /// - Parameter samples: Audio samples
    static func processStreamingAudio(_ samples: [Float]) async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await serviceContainer.sttCapability.processStreamingAudio(samples)
    }

    /// Stop streaming transcription
    static func stopStreamingTranscription() async {
        await serviceContainer.sttCapability.stopStreamingTranscription()
    }
}
