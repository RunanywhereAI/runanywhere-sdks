//
//  CppEventBridge.swift
//  RunAnywhere SDK
//
//  Bridges C++ analytics events to Swift EventPublisher.
//  C++ is the canonical source of truth for all analytics events.
//  This bridge converts C++ events to Swift events and publishes them.
//

import CRACommons
import Foundation

/// Bridge that receives events from C++ and publishes them to Swift EventPublisher
public final class CppEventBridge {

    // MARK: - Singleton

    /// Shared instance
    public static let shared = CppEventBridge()

    /// Whether the bridge is registered with C++
    private(set) var isRegistered = false

    private init() {}

    // MARK: - Registration

    /// Register the Swift callback with C++ event system.
    /// Called during SDK initialization.
    public func register() {
        guard !isRegistered else { return }

        // Register our C callback with the C++ analytics event system
        let result = rac_analytics_events_set_callback(cppEventCallback, nil)

        if result == RAC_SUCCESS {
            isRegistered = true
            SDKLogger(category: "CppEventBridge").debug("Registered C++ event callback")
        } else {
            SDKLogger(category: "CppEventBridge").warning("Failed to register C++ event callback: \(result)")
        }
    }

    /// Unregister the callback (called during SDK shutdown)
    public func unregister() {
        guard isRegistered else { return }

        _ = rac_analytics_events_set_callback(nil, nil)
        isRegistered = false
        SDKLogger(category: "CppEventBridge").debug("Unregistered C++ event callback")
    }
}

// MARK: - C Callback Function

/// C callback function that receives events from C++
/// This function is called on whichever thread C++ emits events from
private func cppEventCallback(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>?, userData: UnsafeMutableRawPointer?) {
    guard let data = data else { return }

    // Convert C++ event to Swift event and publish via category handlers
    switch type {
    // LLM Events
    case RAC_EVENT_LLM_GENERATION_STARTED,
         RAC_EVENT_LLM_GENERATION_COMPLETED,
         RAC_EVENT_LLM_GENERATION_FAILED,
         RAC_EVENT_LLM_FIRST_TOKEN,
         RAC_EVENT_LLM_STREAMING_UPDATE,
         RAC_EVENT_LLM_MODEL_LOAD_STARTED,
         RAC_EVENT_LLM_MODEL_LOAD_COMPLETED,
         RAC_EVENT_LLM_MODEL_LOAD_FAILED,
         RAC_EVENT_LLM_MODEL_UNLOADED:
        handleLLMEvent(type: type, data: data)

    // STT Events
    case RAC_EVENT_STT_TRANSCRIPTION_STARTED,
         RAC_EVENT_STT_TRANSCRIPTION_COMPLETED,
         RAC_EVENT_STT_TRANSCRIPTION_FAILED:
        handleSTTEvent(type: type, data: data)

    // TTS Events
    case RAC_EVENT_TTS_SYNTHESIS_STARTED,
         RAC_EVENT_TTS_SYNTHESIS_COMPLETED,
         RAC_EVENT_TTS_SYNTHESIS_FAILED:
        handleTTSEvent(type: type, data: data)

    // VAD Events
    case RAC_EVENT_VAD_STARTED,
         RAC_EVENT_VAD_STOPPED,
         RAC_EVENT_VAD_SPEECH_STARTED,
         RAC_EVENT_VAD_SPEECH_ENDED:
        handleVADEvent(type: type, data: data)

    default:
        // Unknown event type - ignore
        break
    }
}

// MARK: - LLM Event Handler

private func handleLLMEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
    switch type {
    case RAC_EVENT_LLM_GENERATION_STARTED:
        let event = data.pointee.data.llm_generation
        EventPublisher.shared.track(LLMEvent.generationStarted(
            generationId: event.generation_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            prompt: nil,
            isStreaming: event.is_streaming == RAC_TRUE,
            framework: InferenceFramework(from: event.framework)
        ))

    case RAC_EVENT_LLM_GENERATION_COMPLETED:
        let event = data.pointee.data.llm_generation
        EventPublisher.shared.track(LLMEvent.generationCompleted(
            generationId: event.generation_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            inputTokens: Int(event.input_tokens),
            outputTokens: Int(event.output_tokens),
            durationMs: event.duration_ms,
            tokensPerSecond: event.tokens_per_second,
            isStreaming: event.is_streaming == RAC_TRUE,
            timeToFirstTokenMs: event.time_to_first_token_ms > 0 ? event.time_to_first_token_ms : nil,
            framework: InferenceFramework(from: event.framework),
            temperature: event.temperature > 0 ? event.temperature : nil,
            maxTokens: event.max_tokens > 0 ? Int(event.max_tokens) : nil,
            contextLength: event.context_length > 0 ? Int(event.context_length) : nil
        ))

    case RAC_EVENT_LLM_GENERATION_FAILED:
        let event = data.pointee.data.llm_generation
        let errorMessage = event.error_message.map { String(cString: $0) } ?? "Unknown error"
        EventPublisher.shared.track(LLMEvent.generationFailed(
            generationId: event.generation_id.map { String(cString: $0) } ?? "",
            error: SDKError.llm(.generationFailed, errorMessage)
        ))

    case RAC_EVENT_LLM_FIRST_TOKEN:
        let event = data.pointee.data.llm_generation
        EventPublisher.shared.track(LLMEvent.firstToken(
            generationId: event.generation_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            timeToFirstTokenMs: event.time_to_first_token_ms,
            framework: InferenceFramework(from: event.framework)
        ))

    case RAC_EVENT_LLM_STREAMING_UPDATE:
        let event = data.pointee.data.llm_generation
        EventPublisher.shared.track(LLMEvent.streamingUpdate(
            generationId: event.generation_id.map { String(cString: $0) } ?? "",
            tokensGenerated: Int(event.output_tokens)
        ))

    case RAC_EVENT_LLM_MODEL_LOAD_STARTED:
        let event = data.pointee.data.llm_model
        EventPublisher.shared.track(LLMEvent.modelLoadStarted(
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            modelSizeBytes: event.model_size_bytes,
            framework: InferenceFramework(from: event.framework)
        ))

    case RAC_EVENT_LLM_MODEL_LOAD_COMPLETED:
        let event = data.pointee.data.llm_model
        EventPublisher.shared.track(LLMEvent.modelLoadCompleted(
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            durationMs: event.duration_ms,
            modelSizeBytes: event.model_size_bytes,
            framework: InferenceFramework(from: event.framework)
        ))

    case RAC_EVENT_LLM_MODEL_LOAD_FAILED:
        let event = data.pointee.data.llm_model
        let errorMessage = event.error_message.map { String(cString: $0) } ?? "Load failed"
        EventPublisher.shared.track(LLMEvent.modelLoadFailed(
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            error: SDKError.llm(.modelLoadFailed, errorMessage),
            framework: InferenceFramework(from: event.framework)
        ))

    case RAC_EVENT_LLM_MODEL_UNLOADED:
        let event = data.pointee.data.llm_model
        EventPublisher.shared.track(LLMEvent.modelUnloaded(
            modelId: event.model_id.map { String(cString: $0) } ?? ""
        ))

    default:
        break
    }
}

// MARK: - STT Event Handler

private func handleSTTEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
    switch type {
    case RAC_EVENT_STT_TRANSCRIPTION_STARTED:
        let event = data.pointee.data.stt_transcription
        EventPublisher.shared.track(STTEvent.transcriptionStarted(
            transcriptionId: event.transcription_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            audioLengthMs: event.audio_length_ms,
            audioSizeBytes: Int(event.audio_size_bytes),
            language: event.language.map { String(cString: $0) } ?? "en-US",
            isStreaming: event.is_streaming == RAC_TRUE,
            framework: InferenceFramework(from: event.framework)
        ))

    case RAC_EVENT_STT_TRANSCRIPTION_COMPLETED:
        let event = data.pointee.data.stt_transcription
        EventPublisher.shared.track(STTEvent.transcriptionCompleted(
            transcriptionId: event.transcription_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            text: event.text.map { String(cString: $0) } ?? "",
            confidence: event.confidence,
            durationMs: event.duration_ms,
            audioLengthMs: event.audio_length_ms,
            audioSizeBytes: Int(event.audio_size_bytes),
            wordCount: Int(event.word_count),
            realTimeFactor: event.real_time_factor,
            language: event.language.map { String(cString: $0) } ?? "en-US"
        ))

    case RAC_EVENT_STT_TRANSCRIPTION_FAILED:
        let event = data.pointee.data.stt_transcription
        let errorMessage = event.error_message.map { String(cString: $0) } ?? "Transcription failed"
        EventPublisher.shared.track(STTEvent.transcriptionFailed(
            transcriptionId: event.transcription_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            error: SDKError.stt(.processingFailed, errorMessage)
        ))

    default:
        break
    }
}

// MARK: - TTS Event Handler

private func handleTTSEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
    switch type {
    case RAC_EVENT_TTS_SYNTHESIS_STARTED:
        let event = data.pointee.data.tts_synthesis
        EventPublisher.shared.track(TTSEvent.synthesisStarted(
            synthesisId: event.synthesis_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            characterCount: Int(event.character_count),
            sampleRate: Int(event.sample_rate),
            framework: InferenceFramework(from: event.framework)
        ))

    case RAC_EVENT_TTS_SYNTHESIS_COMPLETED:
        let event = data.pointee.data.tts_synthesis
        EventPublisher.shared.track(TTSEvent.synthesisCompleted(
            synthesisId: event.synthesis_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            characterCount: Int(event.character_count),
            audioDurationMs: event.audio_duration_ms,
            audioSizeBytes: Int(event.audio_size_bytes),
            processingDurationMs: event.processing_duration_ms,
            charactersPerSecond: event.characters_per_second,
            sampleRate: Int(event.sample_rate),
            framework: InferenceFramework(from: event.framework)
        ))

    case RAC_EVENT_TTS_SYNTHESIS_FAILED:
        let event = data.pointee.data.tts_synthesis
        let errorMessage = event.error_message.map { String(cString: $0) } ?? "Synthesis failed"
        EventPublisher.shared.track(TTSEvent.synthesisFailed(
            synthesisId: event.synthesis_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            error: SDKError.tts(.processingFailed, errorMessage)
        ))

    default:
        break
    }
}

// MARK: - VAD Event Handler

private func handleVADEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
    switch type {
    case RAC_EVENT_VAD_STARTED:
        EventPublisher.shared.track(VADEvent.started)

    case RAC_EVENT_VAD_STOPPED:
        EventPublisher.shared.track(VADEvent.stopped)

    case RAC_EVENT_VAD_SPEECH_STARTED:
        EventPublisher.shared.track(VADEvent.speechStarted)

    case RAC_EVENT_VAD_SPEECH_ENDED:
        let event = data.pointee.data.vad
        EventPublisher.shared.track(VADEvent.speechEnded(durationMs: event.speech_duration_ms))

    default:
        break
    }
}

// MARK: - InferenceFramework Extension

extension InferenceFramework {
    /// Initialize from C++ rac_inference_framework_t
    init(from cppFramework: rac_inference_framework_t) {
        switch cppFramework {
        case RAC_FRAMEWORK_LLAMACPP:
            self = .llamaCpp
        case RAC_FRAMEWORK_ONNX:
            self = .onnx
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            self = .foundationModels
        case RAC_FRAMEWORK_SYSTEM_TTS:
            self = .systemTTS
        case RAC_FRAMEWORK_FLUID_AUDIO:
            self = .fluidAudio
        case RAC_FRAMEWORK_BUILTIN:
            self = .builtIn
        case RAC_FRAMEWORK_NONE:
            self = .none
        default:
            self = .unknown
        }
    }
}
