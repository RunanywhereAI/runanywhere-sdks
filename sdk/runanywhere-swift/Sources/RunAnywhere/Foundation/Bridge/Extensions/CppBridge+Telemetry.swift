//
//  CppBridge+Telemetry.swift
//  RunAnywhere SDK
//
//  Telemetry and events bridge extensions for C++ interop.
//

import CRACommons
import Foundation

// MARK: - Events Bridge

extension CppBridge {

    /// Analytics events bridge
    /// Receives events from C++ and routes to Swift + Telemetry
    public enum Events {

        private static var isRegistered = false

        /// Register C++ event callback
        static func register() {
            guard !isRegistered else { return }

            let result = rac_analytics_events_set_callback(eventCallback, nil)
            if result == RAC_SUCCESS {
                isRegistered = true
                SDKLogger(category: "CppBridge.Events").debug("Registered C++ event callback")
            }
        }

        /// Unregister C++ event callback
        static func unregister() {
            guard isRegistered else { return }
            _ = rac_analytics_events_set_callback(nil, nil)
            isRegistered = false
        }
    }
}

/// C callback for analytics events
private func eventCallback(
    type: rac_event_type_t,
    data: UnsafePointer<rac_analytics_event_data_t>?,
    userData: UnsafeMutableRawPointer?
) {
    guard let data = data else { return }

    // Forward to telemetry (C++ builds JSON, calls HTTP)
    CppBridge.Telemetry.trackAnalyticsEvent(type: type, data: data)

    // Also publish to Swift EventPublisher (for app developers)
    publishToSwiftEventPublisher(type: type, data: data)
}

// MARK: - Telemetry Bridge

extension CppBridge {

    /// Telemetry bridge
    /// C++ handles JSON building, batching; Swift handles HTTP
    public enum Telemetry {

        private static var manager: OpaquePointer?
        private static let lock = NSLock()

        /// Initialize telemetry manager
        static func initialize(environment: SDKEnvironment) {
            lock.lock()
            defer { lock.unlock() }

            // Destroy existing if any
            if let existing = manager {
                rac_telemetry_manager_destroy(existing)
            }

            let deviceId = DeviceIdentity.persistentUUID
            let deviceInfo = DeviceInfo.current

            manager = deviceId.withCString { did in
                SDKConstants.platform.withCString { plat in
                    SDKConstants.version.withCString { ver in
                        rac_telemetry_manager_create(Environment.toC(environment), did, plat, ver)
                    }
                }
            }

            // Set device info
            deviceInfo.deviceModel.withCString { model in
                deviceInfo.osVersion.withCString { os in
                    rac_telemetry_manager_set_device_info(manager, model, os)
                }
            }

            // Register HTTP callback
            let userData = Unmanaged.passUnretained(Telemetry.self as AnyObject).toOpaque()
            rac_telemetry_manager_set_http_callback(manager, telemetryHttpCallback, userData)
        }

        /// Shutdown telemetry manager
        static func shutdown() {
            lock.lock()
            defer { lock.unlock() }

            if let mgr = manager {
                rac_telemetry_manager_flush(mgr)
                rac_telemetry_manager_destroy(mgr)
                manager = nil
            }
        }

        /// Track analytics event from C++
        static func trackAnalyticsEvent(
            type: rac_event_type_t,
            data: UnsafePointer<rac_analytics_event_data_t>
        ) {
            lock.lock()
            let mgr = manager
            lock.unlock()

            guard let mgr = mgr else { return }
            rac_telemetry_manager_track_analytics(mgr, type, data)
        }

        /// Flush pending events
        public static func flush() {
            lock.lock()
            let mgr = manager
            lock.unlock()

            guard let mgr = mgr else { return }
            rac_telemetry_manager_flush(mgr)
        }
    }
}

/// HTTP callback for telemetry
private func telemetryHttpCallback(
    userData: UnsafeMutableRawPointer?,
    endpoint: UnsafePointer<CChar>?,
    jsonBody: UnsafePointer<CChar>?,
    jsonLength: Int,
    requiresAuth: rac_bool_t
) {
    guard let endpoint = endpoint, let jsonBody = jsonBody else { return }

    let path = String(cString: endpoint)
    let json = String(cString: jsonBody)
    let needsAuth = requiresAuth == RAC_TRUE

    Task {
        await performTelemetryHTTP(path: path, json: json, requiresAuth: needsAuth)
    }
}

private func performTelemetryHTTP(path: String, json: String, requiresAuth: Bool) async {
    do {
        _ = try await CppBridge.HTTP.shared.post(path, json: json, requiresAuth: requiresAuth)
    } catch {
        SDKLogger(category: "CppBridge.Telemetry").warning("HTTP failed: \(error)")
    }
}

// MARK: - Helper to publish to Swift EventPublisher

/// Publish C++ event to Swift EventPublisher for app developers
private func publishToSwiftEventPublisher(
    type: rac_event_type_t,
    data: UnsafePointer<rac_analytics_event_data_t>
) {
    // Convert C++ event to Swift event and publish
    // (This is the existing CppEventBridge logic)

    switch type {
    case RAC_EVENT_LLM_GENERATION_STARTED,
         RAC_EVENT_LLM_GENERATION_COMPLETED,
         RAC_EVENT_LLM_GENERATION_FAILED,
         RAC_EVENT_LLM_FIRST_TOKEN,
         RAC_EVENT_LLM_STREAMING_UPDATE,
         RAC_EVENT_LLM_MODEL_LOAD_STARTED,
         RAC_EVENT_LLM_MODEL_LOAD_COMPLETED,
         RAC_EVENT_LLM_MODEL_LOAD_FAILED,
         RAC_EVENT_LLM_MODEL_UNLOADED:
        publishLLMEvent(type: type, data: data)

    case RAC_EVENT_STT_TRANSCRIPTION_STARTED,
         RAC_EVENT_STT_TRANSCRIPTION_COMPLETED,
         RAC_EVENT_STT_TRANSCRIPTION_FAILED:
        publishSTTEvent(type: type, data: data)

    case RAC_EVENT_TTS_SYNTHESIS_STARTED,
         RAC_EVENT_TTS_SYNTHESIS_COMPLETED,
         RAC_EVENT_TTS_SYNTHESIS_FAILED:
        publishTTSEvent(type: type, data: data)

    case RAC_EVENT_VAD_STARTED,
         RAC_EVENT_VAD_STOPPED,
         RAC_EVENT_VAD_SPEECH_STARTED,
         RAC_EVENT_VAD_SPEECH_ENDED:
        publishVADEvent(type: type, data: data)

    default:
        break
    }
}

// MARK: - Event Publishing Helpers

private func publishLLMEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
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
    case RAC_EVENT_LLM_MODEL_LOAD_COMPLETED:
        let event = data.pointee.data.llm_model
        EventPublisher.shared.track(LLMEvent.modelLoadCompleted(
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            durationMs: event.duration_ms,
            modelSizeBytes: event.model_size_bytes,
            framework: InferenceFramework(from: event.framework)
        ))
    default:
        break
    }
}

private func publishSTTEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
    switch type {
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
    default:
        break
    }
}

private func publishTTSEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
    switch type {
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
    default:
        break
    }
}

private func publishVADEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
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
