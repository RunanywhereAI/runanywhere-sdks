//
//  RunAnywhere+VoiceSession.swift
//  RunAnywhere SDK
//
//  v2 close-out Phase 10 (P2-5). The pre-Phase-10 implementation was a
//  ~310-LOC `VoiceSessionHandle` actor that re-implemented the entire
//  STT → LLM → TTS pipeline in Swift: audio capture management,
//  RMS-based speech detection, silence-window monitoring, continuous-mode
//  resume, ThinkingContentParser invocation, TTS playback, error fan-out.
//
//  All of that duplicates the C++ voice agent (rac_voice_agent_*) and
//  the GAP 09 streaming adapters. New code MUST use the
//  [VoiceAgentStreamAdapter] from Wave C; the pre-existing public
//  surface is preserved here as a thin deprecation shell so existing
//  callers compile.
//

import Foundation

@available(*, deprecated, message: "Use VoiceAgentStreamAdapter for streaming voice events.")
public actor VoiceSessionHandle {
    private let logger = SDKLogger(category: "VoiceSession")
    private let config: VoiceSessionConfig
    private var isRunning = false

    private var eventContinuation: AsyncStream<VoiceSessionEvent>.Continuation?

    /// Stream of session events — kept as the public API contract.
    public nonisolated let events: AsyncStream<VoiceSessionEvent>

    init(config: VoiceSessionConfig) {
        self.config = config
        var continuation: AsyncStream<VoiceSessionEvent>.Continuation!
        self.events = AsyncStream { cont in continuation = cont }
        self.eventContinuation = continuation
    }

    /// Starts a session. The orchestration body was deleted; this method
    /// emits Started + a deprecation-warning event and returns. Real
    /// streaming flows through VoiceAgentStreamAdapter (Wave C).
    func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        logger.warning(
            "VoiceSessionHandle.start: orchestration deleted in v2 close-out Phase 10. " +
            "Migrate to VoiceAgentStreamAdapter(handle:).stream()."
        )
        eventContinuation?.yield(.started)
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        eventContinuation?.yield(.stopped)
        eventContinuation?.finish()
    }

    /// Preserved for source compatibility — no-op since the audio playback
    /// component was deleted with the orchestrator.
    public func interruptPlayback() {
        logger.debug("interruptPlayback: no-op since v2 close-out — handled by C++ voice agent now.")
    }

    /// Preserved for source compatibility — no-op.
    public func sendNow() async {
        logger.debug("sendNow: no-op since v2 close-out — push-to-talk handled by C++ voice agent now.")
    }

    /// Preserved for source compatibility — no-op.
    public func resumeListening() async {
        logger.debug("resumeListening: no-op since v2 close-out — handled by C++ voice agent now.")
    }
}

// MARK: - RunAnywhere Extension

public extension RunAnywhere {
    /// Start a voice session. Returns a handle; consumers iterate
    /// `session.events`. New code should use [VoiceAgentStreamAdapter]
    /// instead — this method is kept for API compatibility.
    @available(*, deprecated, message: "Use VoiceAgentStreamAdapter(handle:).stream() — Swift orchestration retired in v2 close-out.")
    static func startVoiceSession(
        config: VoiceSessionConfig = .default
    ) async throws -> VoiceSessionHandle {
        let session = VoiceSessionHandle(config: config)
        try await session.start()
        return session
    }

    /// Callback-based variant — same deprecation as the AsyncStream variant.
    @available(*, deprecated, message: "Use VoiceAgentStreamAdapter(handle:).stream() — Swift orchestration retired in v2 close-out.")
    static func startVoiceSession(
        config: VoiceSessionConfig = .default,
        onEvent: @escaping @Sendable (VoiceSessionEvent) -> Void
    ) async throws -> VoiceSessionHandle {
        let session = VoiceSessionHandle(config: config)
        Task {
            for await event in session.events { onEvent(event) }
        }
        try await session.start()
        return session
    }
}
