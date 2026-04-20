// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Public `RunAnywhere` voice-agent surface.

import Foundation

/// Per-component load state reported by `getVoiceAgentComponentStates`.
/// Matches main's shape — `.loaded` carries the model id; `.error` carries
/// the error message.
public enum ComponentLoadState: Sendable {
    case notLoaded
    case loading
    case loaded(modelId: String)
    case error(String)

    public var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    public var displayName: String {
        switch self {
        case .notLoaded:      return "Not loaded"
        case .loading:        return "Loading"
        case .loaded(let id): return id.isEmpty ? "Loaded" : "Loaded (\(id))"
        case .error(let m):   return "Error: \(m)"
        }
    }
}

/// Aggregate return type for `getVoiceAgentComponentStates()`. Exposes the
/// per-component state via named properties so call sites can pattern
/// match without string-keyed lookups.
public struct VoiceAgentComponentStates: Sendable {
    public var stt: ComponentLoadState
    public var llm: ComponentLoadState
    public var tts: ComponentLoadState
    public var vad: ComponentLoadState
}

@MainActor
public extension RunAnywhere {

    /// Start a voice-agent session. Returns a `VoiceSessionHandle` whose
    /// `.events` stream yields `VoiceSession.Event` values until the
    /// caller invokes `.stop()`.
    static func startVoiceSession(config: VoiceSessionConfig) async throws
        -> VoiceSessionHandle
    {
        let agentConfig = VoiceAgentConfig(
            llm: config.llmModelId,
            stt: config.sttModelId,
            tts: config.ttsModelId,
            vad: config.vadModelId,
            enableBargeIn: config.enableBargeIn,
            emitPartials: config.emitPartials,
            systemPrompt: config.systemPrompt)
        let session = try await VoiceSession.create(from: .voiceAgent(agentConfig))
        return VoiceSessionHandle(session: session)
    }

    /// Report the current load state of the voice-agent components
    /// (llm / stt / tts / vad). The sample UI uses this to render
    /// per-component progress. v2 tracks loaded-ness via
    /// `SessionRegistry.current*`; this function translates that into
    /// the map shape the sample expects.
    static func getVoiceAgentComponentStates() async -> VoiceAgentComponentStates {
        func state(loaded: Bool, id: String) -> ComponentLoadState {
            loaded ? .loaded(modelId: id) : .notLoaded
        }
        let llmId = SessionRegistry.currentModelId
        let sttId = SessionRegistry.currentSTTModelId
        let ttsId = SessionRegistry.currentTTSVoiceId
        let vadId = SessionRegistry.currentVADModelId
        return VoiceAgentComponentStates(
            stt: state(loaded: !sttId.isEmpty, id: sttId),
            llm: state(loaded: SessionRegistry.currentLLM != nil, id: llmId),
            tts: state(loaded: !ttsId.isEmpty, id: ttsId),
            vad: state(loaded: !vadId.isEmpty, id: vadId)
        )
    }
}
