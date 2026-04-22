//
//  VoiceAgentTypes.swift
//  RunAnywhere SDK
//
//  Consolidated voice agent and voice session types for public API.
//  Includes: configurations, states, results, events, and errors.
//

import CRACommons
import Foundation

// MARK: - Voice Agent Result

/// Result from voice agent processing
/// Contains all outputs from the voice pipeline: transcription, LLM response, and synthesized audio
public struct VoiceAgentResult: Sendable {
    /// Whether speech was detected in the input audio
    public var speechDetected: Bool

    /// Transcribed text from STT
    public var transcription: String?

    /// Generated response text from LLM
    public var response: String?

    /// Thinking content extracted from `<think>...</think>` tags (nil if none)
    public var thinkingContent: String?

    /// Synthesized audio data from TTS
    public var synthesizedAudio: Data?

    /// Initialize with default values
    public init(
        speechDetected: Bool = false,
        transcription: String? = nil,
        response: String? = nil,
        thinkingContent: String? = nil,
        synthesizedAudio: Data? = nil
    ) {
        self.speechDetected = speechDetected
        self.transcription = transcription
        self.response = response
        self.thinkingContent = thinkingContent
        self.synthesizedAudio = synthesizedAudio
    }

    /// Initialize from C++ rac_voice_agent_result_t
    public init(from cResult: rac_voice_agent_result_t) {
        self.init(
            speechDetected: cResult.speech_detected == RAC_TRUE,
            transcription: cResult.transcription.map { String(cString: $0) },
            response: cResult.response.map { String(cString: $0) },
            synthesizedAudio: {
                guard cResult.synthesized_audio_size > 0, let audioPtr = cResult.synthesized_audio else {
                    return nil
                }
                return Data(bytes: audioPtr, count: cResult.synthesized_audio_size)
            }()
        )
    }
}

// MARK: - Component Load State

/// Represents the loading state of a single model/voice component
public enum ComponentLoadState: Sendable, Equatable {
    case notLoaded
    case loading
    case loaded(modelId: String)
    case error(String)

    /// Whether the component is currently loaded and ready to use
    public var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    /// Whether the component is currently loading
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Get the model ID if loaded
    public var modelId: String? {
        if case .loaded(let id) = self { return id }
        return nil
    }
}

// MARK: - Voice Agent Component States

/// Unified state of all voice agent components
public struct VoiceAgentComponentStates: Sendable {
    /// Speech-to-Text component state
    public let stt: ComponentLoadState

    /// Large Language Model component state
    public let llm: ComponentLoadState

    /// Text-to-Speech component state
    public let tts: ComponentLoadState

    /// Whether all components are loaded and the voice agent is ready to use
    public var isFullyReady: Bool {
        stt.isLoaded && llm.isLoaded && tts.isLoaded
    }

    /// Whether any component is currently loading
    public var isAnyLoading: Bool {
        stt.isLoading || llm.isLoading || tts.isLoading
    }

    /// Get a summary of which components are missing
    public var missingComponents: [String] {
        var missing: [String] = []
        if !stt.isLoaded { missing.append("STT") }
        if !llm.isLoaded { missing.append("LLM") }
        if !tts.isLoaded { missing.append("TTS") }
        return missing
    }

    public init(
        stt: ComponentLoadState = .notLoaded,
        llm: ComponentLoadState = .notLoaded,
        tts: ComponentLoadState = .notLoaded
    ) {
        self.stt = stt
        self.llm = llm
        self.tts = tts
    }
}

// MARK: - Voice Agent Configuration

/// Configuration for the voice agent
/// Uses C++ defaults via rac_voice_agent_config_t
public struct VoiceAgentConfiguration: Sendable {
    /// STT model ID (optional - uses currently loaded model if nil)
    public let sttModelId: String?

    /// LLM model ID (optional - uses currently loaded model if nil)
    public let llmModelId: String?

    /// TTS voice (optional - uses currently loaded voice if nil)
    public let ttsVoice: String?

    /// VAD sample rate
    public let vadSampleRate: Int

    /// VAD frame length in seconds
    public let vadFrameLength: Float

    /// VAD energy threshold
    public let vadEnergyThreshold: Float

    public init(
        sttModelId: String? = nil,
        llmModelId: String? = nil,
        ttsVoice: String? = nil,
        vadSampleRate: Int = 16000,
        vadFrameLength: Float = 0.1,
        vadEnergyThreshold: Float = 0.005
    ) {
        self.sttModelId = sttModelId
        self.llmModelId = llmModelId
        self.ttsVoice = ttsVoice
        self.vadSampleRate = vadSampleRate
        self.vadFrameLength = vadFrameLength
        self.vadEnergyThreshold = vadEnergyThreshold
    }
}

// MARK: - Voice Session Events

/// Events emitted during a voice session.
///
/// **v2.1-1 deprecation (GAP 09 #6)**: This enum is now a *derived view*
/// over the canonical `RAVoiceEvent` proto (codegen'd from
/// `idl/voice_events.proto`). The codegen'd type is the single source
/// of truth; this UX-shaped enum is kept as a backward-compatibility
/// shim so v2.x consumers don't break. New code should subscribe to
/// `VoiceAgentStreamAdapter.stream()` and switch on
/// `event.payload` directly.
///
/// See `docs/migrations/VoiceSessionEvent.md` for the mapping table
/// and migration guide.
///
/// v3.0.0 (C2): retention NOTE — `VoiceSessionEvent` is retained as a
/// derived view because the v2-era `VoiceSessionHandle` actor (see
/// `RunAnywhere+VoiceSession.swift`) + the sample-app voice-agent UI
/// still consume it. A follow-up PR migrates both to
/// `VoiceAgentStreamAdapter` + proto events and deletes this enum
/// along with VoiceSessionHandle. Keeping it as a deprecated derived
/// view (unchanged since v2.1-1) is the intermediate-state commitment.
@available(*, deprecated,
    message: "Use RAVoiceEvent via VoiceAgentStreamAdapter.stream(). " +
             "VoiceSessionEvent is a derived view — see " +
             "docs/migrations/VoiceSessionEvent.md")
public enum VoiceSessionEvent: Sendable {
    /// Session started and ready
    case started

    /// Listening for speech with current audio level (0.0 - 1.0)
    case listening(audioLevel: Float)

    /// Speech detected, started accumulating audio
    case speechStarted

    /// Speech ended, processing audio
    case processing

    /// Got transcription from STT
    case transcribed(text: String)

    /// Got response from LLM (with optional thinking content)
    case responded(text: String, thinkingContent: String? = nil)

    /// Playing TTS audio
    case speaking

    /// Complete turn result (with optional thinking content)
    case turnCompleted(transcript: String, response: String, thinkingContent: String? = nil, audio: Data?)

    /// Session stopped
    case stopped

    /// Error occurred
    case error(String)
}

// MARK: - VoiceSessionEvent ← RAVoiceEvent mapper (v2.1-1)

@available(*, deprecated, message: "Derived view over RAVoiceEvent; prefer the proto directly.")
extension VoiceSessionEvent {
    /// Derive a `VoiceSessionEvent` from the canonical `RAVoiceEvent`.
    /// Returns `nil` for proto events without a UX-visible counterpart.
    /// See the migration doc for the full mapping + dropout list.
    public static func from(_ event: RAVoiceEvent) -> VoiceSessionEvent? {
        switch event.payload {
        case let .userSaid(e):
            return .transcribed(text: e.text)

        case let .assistantToken(e):
            return .responded(text: e.text, thinkingContent: nil)

        case .audio:
            return .speaking

        case let .vad(v):
            switch v.type {
            case .vadEventVoiceStart:          return .speechStarted
            case .vadEventVoiceEndOfUtterance: return .processing
            default:                           return nil
            }

        case let .state(s):
            switch s.current {
            case .idle:      return .started
            case .listening: return .listening(audioLevel: 0)
            case .speaking:  return .speaking
            case .stopped:   return .stopped
            default:         return nil
            }

        case let .error(e):
            return .error(e.message)

        case .interrupted, .metrics, .none:
            return nil

        @unknown default:
            return nil
        }
    }
}

// MARK: - Voice Session Configuration

/// Configuration for voice session behavior
public struct VoiceSessionConfig: Sendable {
    /// Silence duration (seconds) before processing speech
    public var silenceDuration: TimeInterval

    /// Minimum audio level to detect speech (0.0 - 1.0)
    public var speechThreshold: Float

    /// Whether to auto-play TTS response
    public var autoPlayTTS: Bool

    /// Whether to auto-resume listening after TTS playback
    public var continuousMode: Bool

    /// Whether thinking mode is enabled for the LLM.
    public var thinkingModeEnabled: Bool

    /// Maximum tokens for LLM generation (nil uses SDK default of 100)
    public var maxTokens: Int?

    public init(
        silenceDuration: TimeInterval = 1.5,
        speechThreshold: Float = 0.1,
        autoPlayTTS: Bool = true,
        continuousMode: Bool = true,
        thinkingModeEnabled: Bool = false,
        maxTokens: Int? = nil
    ) {
        self.silenceDuration = silenceDuration
        self.speechThreshold = speechThreshold
        self.autoPlayTTS = autoPlayTTS
        self.continuousMode = continuousMode
        self.thinkingModeEnabled = thinkingModeEnabled
        self.maxTokens = maxTokens
    }

    /// Default configuration
    public static let `default` = VoiceSessionConfig()
}

// MARK: - Voice Session Errors

/// Errors that can occur during a voice session
public enum VoiceSessionError: LocalizedError {
    case microphonePermissionDenied
    case notReady
    case alreadyRunning

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied"
        case .notReady:
            return "Voice agent not ready. Load STT, LLM, and TTS models first."
        case .alreadyRunning:
            return "Voice session already running"
        }
    }
}
