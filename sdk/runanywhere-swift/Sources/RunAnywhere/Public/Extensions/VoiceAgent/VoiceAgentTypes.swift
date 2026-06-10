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
    // Former RAComponentLoadState.loaded → RAComponentLifecycleState.ready.
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
    // Commons populates `message` via `rac_error_message(code)` at the
    // emission site (voice_agent.cpp::emit_component_failure). Falling back
    // to the empty string keeps `LocalizedError` honest when message is
    // unset.
    public var errorDescription: String? { message.isEmpty ? nil : message }
}
