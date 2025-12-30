//
//  VoiceAgentResult.swift
//  RunAnywhere SDK
//
//  Output types for VoiceAgent capability
//
//  🟢 BRIDGE: Thin wrapper over C++ rac_voice_agent_result_t
//  C++ Source: include/rac/features/voice_agent/rac_voice_agent.h
//

import CRACommons
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

    // MARK: - C++ Bridge (rac_voice_agent_result_t)

    /// Initialize from C++ rac_voice_agent_result_t
    /// - Parameter cResult: The C++ result struct
    public init(from cResult: rac_voice_agent_result_t) {
        self.init(
            speechDetected: cResult.speech_detected == RAC_TRUE,
            transcription: cResult.transcription.map { String(cString: $0) },
            response: cResult.response.map { String(cString: $0) },
            synthesizedAudio: {
                guard cResult.synthesized_audio_size > 0, let audioPtr = cResult.synthesized_audio else {
                    return nil
                }
                return Data(bytes: audioPtr, count: cResult.synthesized_audio_size)
            }()
        )
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
