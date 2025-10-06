import Foundation

// Import STT result type
import struct RunAnywhere.STTResult

// MARK: - Pipeline Stages

/// Stages in the voice pipeline
public enum PipelineStage: String, CaseIterable {
    case vad = "VAD"
    case transcription = "Speech-to-Text"
    case llmGeneration = "LLM Generation"
    case textToSpeech = "Text-to-Speech"
}

// MARK: - Voice Pipeline Result

/// Complete result from voice pipeline
public struct VoicePipelineResult {
    /// The transcription result from STT
    public let transcription: STTResult

    /// The LLM generated response text
    public let llmResponse: String

    /// The synthesized audio output (if TTS enabled)
    public let audioOutput: Data?

    /// Total processing time
    public let processingTime: TimeInterval

    /// Per-stage timing metrics
    public let stageTiming: [PipelineStage: TimeInterval]

    public init(
        transcription: STTResult,
        llmResponse: String,
        audioOutput: Data? = nil,
        processingTime: TimeInterval = 0,
        stageTiming: [PipelineStage: TimeInterval] = [:]
    ) {
        self.transcription = transcription
        self.llmResponse = llmResponse
        self.audioOutput = audioOutput
        self.processingTime = processingTime
        self.stageTiming = stageTiming
    }
}
