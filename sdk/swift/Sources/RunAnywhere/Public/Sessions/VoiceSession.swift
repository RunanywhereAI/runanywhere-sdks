// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation
import CRACommonsCore

/// A live VoiceAgent session. Events stream via `run()`. The underlying C
/// pipeline is created lazily on first `run()` call and torn down on
/// deinit.
public final class VoiceSession: @unchecked Sendable {

    /// Public event stream surface — matches the main-branch sample's
    /// switch cases exactly so sample code compiles without a
    /// `@unknown default` arm. Internal v2-style events
    /// (`userSaid` / `assistantToken` / `audio` / …) are translated into
    /// these at the `VoiceSession.run()` boundary.
    public enum Event: Sendable {
        case started
        case listening(level: Float)
        case speechStarted
        case processing
        case transcribed(String)
        case responded(String, String)
        case speaking
        case turnCompleted(transcript: String, response: String,
                            ttftMs: Double, totalMs: Double)
        case stopped
        case error(String)

        /// Convenience initialiser that wraps an arbitrary Error into the
        /// String-form `.error(_:)`.
        public static func error(_ e: any Error) -> Event {
            .error(String(describing: e))
        }
    }

    public enum TokenKind: Sendable {
        case answer, thought, toolCall

        internal init(raw: Int32) {
            switch raw {
            case 2:  self = .thought
            case 3:  self = .toolCall
            default: self = .answer
            }
        }
    }

    public enum PipelineState: Sendable {
        case idle, listening, thinking, speaking, stopped

        internal init(raw: Int32) {
            switch raw {
            case 2:  self = .listening
            case 3:  self = .thinking
            case 4:  self = .speaking
            case 5:  self = .stopped
            default: self = .idle
            }
        }
    }

    public enum VADKind: Sendable {
        case voiceStart, voiceEnd, bargeIn, silence, unknown

        internal init(raw: Int32) {
            switch raw {
            case 1:  self = .voiceStart
            case 2:  self = .voiceEnd
            case 3:  self = .bargeIn
            case 4:  self = .silence
            default: self = .unknown
            }
        }
    }

    internal static func create(from config: SolutionConfig) async throws
        -> VoiceSession {
        return VoiceSession(config: config)
    }

    private init(config: SolutionConfig) {
        self.config = config
    }

    private let config: SolutionConfig
    private var pipeline: OpaquePointer?
    private var continuation: AsyncThrowingStream<Event, Error>.Continuation?

    // Keep string config fields alive for the lifetime of the C call.
    private var heldStrings: [String] = []

    /// Streams the event sequence. Cancel by dropping the iterator.
    public func run() -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            do {
                try self.start()
            } catch {
                continuation.finish(throwing: error)
                return
            }
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    public func stop() {
        if let p = pipeline { ra_pipeline_cancel(p) }
    }

    deinit {
        if let p = pipeline { ra_pipeline_destroy(p) }
    }

    // MARK: - C bridge

    private func start() throws {
        guard case .voiceAgent(let cfg) = config else {
            throw RunAnywhereError.backendUnavailable(
                "only voiceAgent configs are wired through ra_pipeline yet")
        }

        heldStrings = [cfg.llm, cfg.stt, cfg.tts, cfg.vad, cfg.systemPrompt]

        var out: OpaquePointer?
        let status: Int32 = heldStrings[0].withCString { lp in
        heldStrings[1].withCString { sp in
        heldStrings[2].withCString { tp in
        heldStrings[3].withCString { vp in
        heldStrings[4].withCString { pp in
            var c = ra_voice_agent_config_t()
            c.llm_model_id          = lp
            c.stt_model_id          = sp
            c.tts_model_id          = tp
            c.vad_model_id          = vp
            c.sample_rate_hz        = Int32(cfg.sampleRateHz)
            c.chunk_ms              = Int32(cfg.chunkMilliseconds)
            c.audio_source          = Int32(RA_AUDIO_SOURCE_MICROPHONE)
            c.audio_file_path       = nil
            c.enable_barge_in       = cfg.enableBargeIn ? 1 : 0
            c.barge_in_threshold_ms = 200
            c.system_prompt         = pp
            c.max_context_tokens    = Int32(cfg.maxContextTokens)
            c.temperature           = cfg.temperature
            c.emit_partials         = cfg.emitPartials ? 1 : 0
            c.emit_thoughts         = cfg.emitThoughts ? 1 : 0
            return ra_pipeline_create_voice_agent(&c, &out)
        }}}}}

        guard status == Int32(RA_OK), let handle = out else {
            throw RunAnywhereError.internalError(
                "ra_pipeline_create_voice_agent failed: \(status)")
        }
        self.pipeline = handle

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        _ = ra_pipeline_set_event_callback(handle, { eventPtr, userData in
            guard let userData, let eventPtr else { return }
            let session = Unmanaged<VoiceSession>.fromOpaque(userData).takeUnretainedValue()
            session.handleEvent(eventPtr.pointee)
        }, ctx)

        _ = ra_pipeline_set_completion_callback(handle, { status, message, userData in
            guard let userData else { return }
            let session = Unmanaged<VoiceSession>.fromOpaque(userData).takeUnretainedValue()
            let msg = message.map { String(cString: $0) } ?? ""
            if status == Int32(RA_OK) {
                session.continuation?.finish()
            } else if status == Int32(RA_ERR_CANCELLED) {
                session.continuation?.finish(throwing: RunAnywhereError.cancelled)
            } else {
                session.continuation?.finish(throwing:
                    RunAnywhereError.internalError("pipeline terminated: \(status) \(msg)"))
            }
        }, ctx)

        let runStatus = ra_pipeline_run(handle)
        guard runStatus == Int32(RA_OK) else {
            throw RunAnywhereError.internalError("ra_pipeline_run failed: \(runStatus)")
        }
    }

    // Running accumulator — when the C pipeline streams partial assistant
    // tokens we concatenate them here and emit a single `.responded(_,_)`
    // on the STT/metrics boundary to match main's sample expectations.
    private var partialUserTranscript: String = ""
    private var partialAssistantReply:  String = ""

    private func handleEvent(_ ev: ra_voice_event_t) {
        let text = ev.text.map { String(cString: $0) } ?? ""
        switch Int32(ev.kind) {
        case Int32(RA_VOICE_EVENT_USER_SAID):
            partialUserTranscript = text
            continuation?.yield(.transcribed(text))
        case Int32(RA_VOICE_EVENT_ASSISTANT_TOKEN):
            if ev.is_final != 0 {
                partialAssistantReply += text
                continuation?.yield(.responded(partialUserTranscript,
                                                partialAssistantReply))
            } else if !text.isEmpty {
                partialAssistantReply += text
            }
        case Int32(RA_VOICE_EVENT_AUDIO):
            // Audio PCM is delivered by the C pipeline for analytics;
            // sample code doesn't consume it directly — suppress.
            break
        case Int32(RA_VOICE_EVENT_VAD):
            // Map the first voice-start tick into `.speechStarted`.
            if ev.vad_type == 1 {
                continuation?.yield(.speechStarted)
            }
        case Int32(RA_VOICE_EVENT_INTERRUPTED):
            continuation?.yield(.error("interrupted: \(text)"))
        case Int32(RA_VOICE_EVENT_STATE_CHANGE):
            let current = PipelineState(raw: ev.curr_state)
            switch current {
            case .listening: continuation?.yield(.listening(level: 0))
            case .thinking:  continuation?.yield(.processing)
            case .speaking:  continuation?.yield(.speaking)
            case .stopped:   continuation?.yield(.stopped)
            case .idle:      break
            }
        case Int32(RA_VOICE_EVENT_METRICS):
            continuation?.yield(.turnCompleted(
                transcript: partialUserTranscript,
                response:   partialAssistantReply,
                ttftMs:     ev.llm_first_token_ms,
                totalMs:    ev.end_to_end_ms))
            partialUserTranscript = ""
            partialAssistantReply  = ""
        case Int32(RA_VOICE_EVENT_ERROR):
            continuation?.yield(.error(text.isEmpty ? "pipeline error" : text))
        default:
            break
        }
    }

    /// Feeds externally-sourced PCM audio into the pipeline. Required when
    /// the voice agent is configured with `audio_source = CALLBACK`.
    public func feedAudio(samples: [Float], sampleRateHz: Int) {
        guard let handle = pipeline else { return }
        samples.withUnsafeBufferPointer { buf in
            _ = ra_pipeline_feed_audio(handle, buf.baseAddress,
                                        Int32(samples.count),
                                        Int32(sampleRateHz))
        }
    }

    /// Injects a barge-in control signal to interrupt current assistant output.
    public func bargeIn() {
        guard let handle = pipeline else { return }
        _ = ra_pipeline_inject_barge_in(handle)
    }
}

