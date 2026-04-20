// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Voice-agent session handle + config. Returned from
// `RunAnywhere.startVoiceSession(config:)`.

import Foundation

/// Persistent handle for a voice-agent session. Holds the underlying
/// `VoiceSession` and re-exposes its event stream as a non-throwing
/// `AsyncStream` — any pipeline failures are translated into
/// `VoiceSession.Event.error(_:)` values.
public final class VoiceSessionHandle: @unchecked Sendable {
    public let session: VoiceSession
    public let events: AsyncStream<VoiceSession.Event>

    internal init(session: VoiceSession) {
        self.session = session
        self.events = AsyncStream { continuation in
            Task {
                do {
                    for try await event in session.run() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.error(String(describing: error)))
                    continuation.finish()
                }
            }
        }
    }

    /// Stop the underlying pipeline.
    public func stop() { session.stop() }
}

/// Configuration for `RunAnywhere.startVoiceSession`.
public struct VoiceSessionConfig: Sendable {
    public var llmModelId:   String
    public var sttModelId:   String
    public var vadModelId:   String
    public var ttsModelId:   String
    public var systemPrompt: String
    public var enableBargeIn: Bool
    public var emitPartials: Bool
    public var continuousMode: Bool
    public var thinkingModeEnabled: Bool
    public var maxTokens: Int

    public init(llmModelId:   String = "qwen3-4b",
                sttModelId:   String = "whisper-base",
                vadModelId:   String = "silero-v5",
                ttsModelId:   String = "kokoro",
                systemPrompt: String = "",
                enableBargeIn: Bool = true,
                emitPartials:  Bool = true,
                continuousMode: Bool = false,
                thinkingModeEnabled: Bool = false,
                maxTokens: Int = 512) {
        self.llmModelId = llmModelId
        self.sttModelId = sttModelId
        self.vadModelId = vadModelId
        self.ttsModelId = ttsModelId
        self.systemPrompt = systemPrompt
        self.enableBargeIn = enableBargeIn
        self.emitPartials = emitPartials
        self.continuousMode = continuousMode
        self.thinkingModeEnabled = thinkingModeEnabled
        self.maxTokens = maxTokens
    }

    /// Main-branch parity initialiser — bare-bones, resolves model ids
    /// from the currently-loaded sessions.
    public init(continuousMode: Bool,
                thinkingModeEnabled: Bool,
                maxTokens: Int) {
        self.init(systemPrompt: "",
                  enableBargeIn: true, emitPartials: true,
                  continuousMode: continuousMode,
                  thinkingModeEnabled: thinkingModeEnabled,
                  maxTokens: maxTokens)
    }
}

/// Legacy name alias used by the sample apps.
public typealias VoiceSessionEvent = VoiceSession.Event
