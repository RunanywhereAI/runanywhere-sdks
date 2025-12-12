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
    case sttPartialTranscriptWithSpeaker(String, SpeakerDiarizationSpeakerInfo)
    case sttFinalTranscriptWithSpeaker(String, SpeakerDiarizationSpeakerInfo)
    case sttNewSpeakerDetected(SpeakerDiarizationSpeakerInfo)
    case sttSpeakerChanged(from: SpeakerDiarizationSpeakerInfo?, to: SpeakerDiarizationSpeakerInfo)

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

    // Audio control events - Used to prevent feedback loop
    // ViewModel should pause/resume microphone based on these events
    case audioControlPauseRecording   // Stop microphone before TTS starts
    case audioControlResumeRecording  // Resume microphone after TTS completes + cooldown

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
