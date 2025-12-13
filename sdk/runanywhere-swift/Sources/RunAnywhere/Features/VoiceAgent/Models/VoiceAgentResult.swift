//
//  VoiceAgentResult.swift
//  RunAnywhere SDK
//
//  Output types for VoiceAgent capability
//

import Foundation

/// Result from voice agent processing
/// Contains all outputs from the voice pipeline: transcription, LLM response, and synthesized audio
public struct VoiceAgentResult: Sendable {
    /// Whether speech was detected in the input audio
    public var speechDetected: Bool

    /// Transcribed text from STT
    public var transcription: String?

    /// Generated response text from LLM
    public var response: String?

    /// Synthesized audio data from TTS
    public var synthesizedAudio: Data?

    /// Initialize with default values
    public init(
        speechDetected: Bool = false,
        transcription: String? = nil,
        response: String? = nil,
        synthesizedAudio: Data? = nil
    ) {
        self.speechDetected = speechDetected
        self.transcription = transcription
        self.response = response
        self.synthesizedAudio = synthesizedAudio
    }
}

/// Events emitted by the voice agent during processing
public enum VoiceAgentEvent: Sendable {
    /// Complete processing result
    case processed(VoiceAgentResult)

    /// VAD triggered (speech detected or ended)
    case vadTriggered(Bool)

    /// Transcription available from STT
    case transcriptionAvailable(String)

    /// Response generated from LLM
    case responseGenerated(String)

    /// Audio synthesized from TTS
    case audioSynthesized(Data)

    /// Error occurred during processing
    case error(Error)
}
