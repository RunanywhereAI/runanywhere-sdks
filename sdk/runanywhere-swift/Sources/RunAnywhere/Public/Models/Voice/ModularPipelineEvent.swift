import Foundation

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
