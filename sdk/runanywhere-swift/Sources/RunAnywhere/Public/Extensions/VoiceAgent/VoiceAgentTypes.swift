//
//  VoiceAgentTypes.swift
//  RunAnywhere SDK
//
//  Consolidated voice agent and voice session types for public API.
//  Includes: configurations, states, results, events, and errors.
//

import CRACommons
import Foundation

// MARK: - Canonical Proto Typealiases

public typealias VoiceAgentResult = RAVoiceAgentResult
public typealias VoiceAgentComponentStates = RAVoiceAgentComponentStates
public typealias VoiceAgentConfig = RAVoiceAgentComposeConfig

public extension RAVoiceAgentResult {
    init(
        speechDetected: Bool = false,
        transcription: String? = nil,
        response: String? = nil,
        thinkingContent: String? = nil,
        synthesizedAudio: Data? = nil,
        finalState: RAVoiceAgentComponentStates? = nil
    ) {
        self.init()
        self.speechDetected = speechDetected
        if let transcription { self.transcription = transcription }
        if let response { self.assistantResponse = response }
        if let thinkingContent { self.thinkingContent = thinkingContent }
        if let synthesizedAudio { self.synthesizedAudio = synthesizedAudio }
        if let finalState { self.finalState = finalState }
    }

    var response: String? {
        get { hasAssistantResponse ? assistantResponse : nil }
        set {
            if let newValue {
                assistantResponse = newValue
            } else {
                clearAssistantResponse()
            }
        }
    }
}

public extension RAComponentLifecycleState {
    // IDL-04: former RAComponentLoadState.loaded → RAComponentLifecycleState.ready.
    var isLoaded: Bool { self == .ready }
    var isLoading: Bool { self == .loading }
}

public extension RAVoiceAgentComponentStates {
    var stt: RAComponentLifecycleState {
        get { sttState }
        set { sttState = newValue }
    }

    var llm: RAComponentLifecycleState {
        get { llmState }
        set { llmState = newValue }
    }

    var tts: RAComponentLifecycleState {
        get { ttsState }
        set { ttsState = newValue }
    }

    var vad: RAComponentLifecycleState {
        get { vadState }
        set { vadState = newValue }
    }

    var isFullyReady: Bool { ready }
    var isAnyLoading: Bool { anyLoading }

    var missingComponents: [String] {
        var missing: [String] = []
        if !sttState.isLoaded { missing.append("STT") }
        if !llmState.isLoaded { missing.append("LLM") }
        if !ttsState.isLoaded { missing.append("TTS") }
        if !vadState.isLoaded { missing.append("VAD") }
        return missing
    }

    init(
        stt: RAComponentLifecycleState = .notLoaded,
        llm: RAComponentLifecycleState = .notLoaded,
        tts: RAComponentLifecycleState = .notLoaded,
        vad: RAComponentLifecycleState = .notLoaded
    ) {
        self.init()
        self.sttState = stt
        self.llmState = llm
        self.ttsState = tts
        self.vadState = vad
        self.ready = stt.isLoaded && llm.isLoaded && tts.isLoaded && vad.isLoaded
        self.anyLoading = stt.isLoading || llm.isLoading || tts.isLoading || vad.isLoading
    }
}

public extension RAVoiceAgentComposeConfig {
    init(
        sttModelId: String? = nil,
        llmModelId: String? = nil,
        ttsVoice: String? = nil,
        vadSampleRate: Int = 16000,
        vadFrameLength: Float = 0.1,
        vadEnergyThreshold: Float = 0.005
    ) {
        self.init()
        if let sttModelId { self.sttModelID = sttModelId }
        if let llmModelId { self.llmModelID = llmModelId }
        if let ttsVoice { self.ttsVoiceID = ttsVoice }
        self.vadSampleRate = Int32(vadSampleRate)
        self.vadFrameLength = vadFrameLength
        self.vadEnergyThreshold = vadEnergyThreshold
    }

    var sttModelId: String? {
        get { hasSttModelID ? sttModelID : nil }
        set {
            if let newValue { sttModelID = newValue } else { clearSttModelID() }
        }
    }

    var llmModelId: String? {
        get { hasLlmModelID ? llmModelID : nil }
        set {
            if let newValue { llmModelID = newValue } else { clearLlmModelID() }
        }
    }

    var ttsVoice: String? {
        get { hasTtsVoiceID ? ttsVoiceID : nil }
        set {
            if let newValue { ttsVoiceID = newValue } else { clearTtsVoiceID() }
        }
    }
}

// v3.1: VoiceSessionEvent enum + `from(_:)` mapper DELETED. Use
// RAVoiceEvent (the proto-generated type) via
// VoiceAgentStreamAdapter(handle:).stream().

// MARK: - Voice Session Configuration

public typealias VoiceSessionConfig = RAVoiceSessionConfig

public extension RAVoiceSessionConfig {
    init(
        silenceDuration: TimeInterval = 1.5,
        speechThreshold: Float = 0.1,
        autoPlayTTS: Bool = true,
        continuousMode: Bool = true,
        thinkingModeEnabled: Bool = false,
        maxTokens _: Int? = nil
    ) {
        self.init()
        self.silenceDuration = silenceDuration
        self.speechThreshold = speechThreshold
        self.autoPlayTts = autoPlayTTS
        self.continuousMode = continuousMode
        self.thinkingModeEnabled = thinkingModeEnabled
    }

    var silenceDuration: TimeInterval {
        get { TimeInterval(silenceDurationMs) / 1000.0 }
        set { silenceDurationMs = Int32((newValue * 1000.0).rounded()) }
    }

    var autoPlayTTS: Bool {
        get { autoPlayTts }
        set { autoPlayTts = newValue }
    }

    static let `default` = RAVoiceSessionConfig(
        silenceDuration: 1.5,
        speechThreshold: 0.1,
        autoPlayTTS: true,
        continuousMode: true,
        thinkingModeEnabled: false
    )
}

// MARK: - Voice Session Errors

public typealias VoiceSessionError = RAVoiceSessionError

extension RAVoiceSessionError: LocalizedError {
    public var errorDescription: String? {
        if !message.isEmpty { return message }
        // IDL-08: VoiceSessionError.code is now the canonical RAErrorCode.
        switch code {
        case .microphonePermissionDenied:
            return "Microphone permission denied"
        case .componentNotReady:
            return "Voice agent not ready. Load VAD, STT, LLM, and TTS models first."
        case .serviceBusy:
            return "Voice session already running"
        case .processingFailed:
            return failedComponent.isEmpty
                ? "Voice agent component failed"
                : "Voice agent component failed: \(failedComponent)"
        default:
            return "Voice session error"
        }
    }
}
