//
//  VoiceAgentTypes.swift
//  RunAnywhere SDK
//
//  Public typealiases + non-trivial helpers for voice agent / voice session
//  proto types. Convenience inits and shorthand accessors with no real value
//  over the canonical RA* proto API have been removed — callers should set
//  proto fields directly (e.g. `config.sttModelID`, `states.sttState`).
//

import Foundation

// MARK: - Canonical Proto Typealiases

public typealias VoiceAgentResult = RAVoiceAgentResult
public typealias VoiceAgentComponentStates = RAVoiceAgentComponentStates
public typealias VoiceAgentConfig = RAVoiceAgentComposeConfig
public typealias VoiceSessionConfig = RAVoiceSessionConfig
public typealias VoiceSessionError = RAVoiceSessionError

// MARK: - RAComponentLifecycleState

public extension RAComponentLifecycleState {
    // IDL-04: former RAComponentLoadState.loaded → RAComponentLifecycleState.ready.
    var isLoaded: Bool { self == .ready }
    var isLoading: Bool { self == .loading }
}

// MARK: - RAVoiceSessionConfig (ms <-> TimeInterval bridges)

public extension RAVoiceSessionConfig {
    var silenceDuration: TimeInterval {
        get { TimeInterval(silenceDurationMs) / 1000.0 }
        set { silenceDurationMs = Int32((newValue * 1000.0).rounded()) }
    }

    var autoPlayTTS: Bool {
        get { autoPlayTts }
        set { autoPlayTts = newValue }
    }
}

// MARK: - RAVoiceSessionError: LocalizedError

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
