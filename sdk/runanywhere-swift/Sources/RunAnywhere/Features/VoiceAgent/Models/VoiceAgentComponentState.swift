//
//  VoiceAgentComponentState.swift
//  RunAnywhere SDK
//
//  Unified state for voice agent components (STT, LLM, TTS)
//  Provides a clean API for apps to track model loading states
//

import Foundation

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
/// Use this to track which models are loaded and ready for the voice pipeline
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

// MARK: - Voice Agent State Event

/// Event emitted when any voice agent component state changes
/// Apps can subscribe to this for reactive UI updates
public enum VoiceAgentStateEvent: SDKEvent {
    case sttStateChanged(ComponentLoadState)
    case llmStateChanged(ComponentLoadState)
    case ttsStateChanged(ComponentLoadState)
    case allComponentsReady

    public var type: String {
        switch self {
        case .sttStateChanged: return "voice_agent_stt_state_changed"
        case .llmStateChanged: return "voice_agent_llm_state_changed"
        case .ttsStateChanged: return "voice_agent_tts_state_changed"
        case .allComponentsReady: return "voice_agent_all_components_ready"
        }
    }

    public var category: EventCategory { .voice }

    public var destination: EventDestination { .publicOnly }

    public var properties: [String: String] {
        switch self {
        case .sttStateChanged(let state):
            return ["component": "stt", "state": stateString(state)]
        case .llmStateChanged(let state):
            return ["component": "llm", "state": stateString(state)]
        case .ttsStateChanged(let state):
            return ["component": "tts", "state": stateString(state)]
        case .allComponentsReady:
            return ["ready": "true"]
        }
    }

    private func stateString(_ state: ComponentLoadState) -> String {
        switch state {
        case .notLoaded: return "not_loaded"
        case .loading: return "loading"
        case .loaded(let modelId): return "loaded:\(modelId)"
        case .error(let msg): return "error:\(msg)"
        }
    }
}
