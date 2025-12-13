//
//  VoiceService.swift
//  RunAnywhere SDK
//
//  Voice service protocol for voice agent orchestration
//

import Foundation

// MARK: - Voice Service Protocol

/// Protocol defining voice agent service operations
/// Voice agent orchestrates VAD, STT, LLM, and TTS components
@MainActor
public protocol VoiceService: AnyObject {

    /// Process audio through the full voice pipeline
    /// - Parameter audioData: Raw audio data
    /// - Returns: Result containing transcription, response, and synthesized audio
    func processAudio(_ audioData: Data) async throws -> VoiceAgentResult

    /// Process audio stream for continuous conversation
    /// - Parameter audioStream: Async stream of audio data chunks
    /// - Returns: Async stream of voice agent events
    func processStream(_ audioStream: AsyncStream<Data>) -> AsyncThrowingStream<VoiceAgentEvent, Error>

    /// Detect voice activity in audio data
    /// - Parameter audioData: Raw audio data
    /// - Returns: Whether speech was detected
    func detectVoiceActivity(_ audioData: Data) -> Bool

    /// Transcribe audio data
    /// - Parameter audioData: Raw audio data
    /// - Returns: Transcribed text
    func transcribe(_ audioData: Data) async throws -> String?

    /// Generate response using LLM
    /// - Parameter prompt: Input prompt
    /// - Returns: Generated response
    func generateResponse(_ prompt: String) async throws -> String?

    /// Synthesize speech from text
    /// - Parameter text: Text to synthesize
    /// - Returns: Synthesized audio data
    func synthesizeSpeech(_ text: String) async throws -> Data?

    /// Cleanup resources
    func cleanup() async throws
}
