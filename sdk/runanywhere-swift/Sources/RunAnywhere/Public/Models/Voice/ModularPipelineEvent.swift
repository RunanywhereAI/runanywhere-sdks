import Foundation

/// Stages in the voice pipeline
public enum PipelineStage: String, CaseIterable {
    case vad = "VAD"
    case transcription = "Speech-to-Text"
    case llmGeneration = "LLM Generation"
    case textToSpeech = "Text-to-Speech"
}

/// Extended events for modular voice pipeline processing
public enum ModularPipelineEvent {
    // VAD events
    case vadSpeechStart
    case vadSpeechEnd
    case vadAudioLevel(Float)

    // STT events
    case sttPartialTranscript(String)
    case sttFinalTranscript(String)
    case sttLanguageDetected(String)

    // STT with Speaker Diarization events
    case sttPartialTranscriptWithSpeaker(String, SpeakerInfo)
    case sttFinalTranscriptWithSpeaker(String, SpeakerInfo)
    case sttNewSpeakerDetected(SpeakerInfo)
    case sttSpeakerChanged(from: SpeakerInfo?, to: SpeakerInfo)

    // LLM events
    case llmThinking
    case llmPartialResponse(String)
    case llmFinalResponse(String)
    case llmStreamStarted
    case llmStreamToken(String)

    // TTS events
    case ttsStarted
    case ttsAudioChunk(Data)
    case ttsCompleted

    // Initialization events
    case componentInitializing(String) // Component name being initialized
    case componentInitialized(String)  // Component name that completed initialization
    case componentInitializationFailed(String, Error) // Component name and error
    case allComponentsInitialized       // All components ready

    // Pipeline events
    case pipelineStarted
    case pipelineError(Error)
    case pipelineCompleted
}

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
