import Foundation

/// Events emitted during voice pipeline processing
public enum VoicePipelineEvent {
    /// Pipeline started
    case started(sessionId: String)

    /// Transcription phase events
    case transcriptionStarted
    case transcriptionProgress(text: String, confidence: Float)
    case transcriptionCompleted(result: VoiceTranscriptionResult)

    /// LLM generation phase events
    case llmGenerationStarted
    case llmGenerationProgress(text: String, tokensGenerated: Int)
    case llmGenerationCompleted(text: String)

    /// Text-to-speech phase events
    case ttsStarted
    case ttsProgress(audioChunk: Data, progress: Float)
    case ttsCompleted(audio: Data)

    /// Pipeline completion
    case completed(result: VoicePipelineResult)

    /// Error at specific stage
    case error(stage: PipelineStage, error: Error)
}

/// Stages in the voice pipeline
public enum PipelineStage: String, CaseIterable {
    case vad = "VAD"
    case transcription = "Speech-to-Text"
    case llmGeneration = "LLM Generation"
    case textToSpeech = "Text-to-Speech"
}

/// Complete result from voice pipeline
public struct VoicePipelineResult {
    /// The transcription result from STT
    public let transcription: VoiceTranscriptionResult

    /// The LLM generated response text
    public let llmResponse: String

    /// The synthesized audio output (if TTS enabled)
    public let audioOutput: Data?

    /// Total processing time
    public let processingTime: TimeInterval

    /// Per-stage timing metrics
    public let stageTiming: [PipelineStage: TimeInterval]

    public init(
        transcription: VoiceTranscriptionResult,
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
