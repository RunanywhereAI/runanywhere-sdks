//
//  STTService.swift
//  RunAnywhere SDK
//
//  Protocol for speech-to-text services
//

import Foundation

// MARK: - STT Service Protocol

/// Protocol for speech-to-text services
public protocol STTService: AnyObject { // swiftlint:disable:this avoid_any_object
    /// Initialize the service with optional model path
    func initialize(modelPath: String?) async throws

    /// Transcribe audio data (batch mode)
    func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult

    /// Stream transcription for real-time processing (live mode)
    /// Falls back to batch mode if streaming is not supported
    func streamTranscribe<S: AsyncSequence>(
        audioStream: S,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> STTTranscriptionResult where S.Element == Data

    /// Check if service is ready
    var isReady: Bool { get }

    /// Get current model identifier
    var currentModel: String? { get }

    /// Whether this service supports live/streaming transcription
    /// If false, streamTranscribe will fall back to batch mode
    var supportsStreaming: Bool { get }

    /// Cleanup resources
    func cleanup() async
}
