//
//  Events.swift
//  RunAnywhere SDK
//
//  One event grammar for every stream: `started`, then deltas, then
//  `completed`. Failures are thrown into the consumer, never smuggled through
//  a payload field.
//

import CRACommons
import Foundation

// MARK: - TokenKind

/// Whether a streamed token is part of the answer or the model's thinking.
public enum TokenKind: Sendable {
    case text
    case thought

    init(proto: RATokenKind) {
        self = proto == .thought ? .thought : .text
    }
}

// MARK: - GenerationEvent

/// Progress of one streaming text or vision generation.
public enum GenerationEvent: Sendable {
    case started(requestId: String)
    case outputItemAdded(requestId: String, sequence: Int64, itemId: String, index: Int, item: String)
    case textDelta(requestId: String, sequence: Int64, itemId: String, index: Int, text: String)
    case reasoningDelta(requestId: String, sequence: Int64, itemId: String, index: Int, text: String)
    case toolCallAdded(requestId: String, sequence: Int64, itemId: String, index: Int, call: ToolCall)
    case toolArgumentsDelta(requestId: String, sequence: Int64, itemId: String, delta: String)
    case toolArgumentsDone(requestId: String, sequence: Int64, itemId: String, arguments: String)
    case usage(requestId: String, sequence: Int64, inputTokens: Int, outputTokens: Int)
    case completed(requestId: String, result: GenerationResult)
    case failed(requestId: String, partial: String?, error: SDKException)
    case cancelled(requestId: String, partial: String?)
}

// MARK: - TranscriptionEvent

/// Progress of one streaming transcription.
public enum TranscriptionEvent: Sendable {
    case started(requestId: String)
    case speechStarted(requestId: String, sequence: Int64, timestampMs: Int64?)
    case partial(requestId: String, sequence: Int64, segmentId: String, revision: Int, alternatives: [String])
    case transcriptFinal(requestId: String, sequence: Int64, transcription: Transcription)
    case speechEnded(requestId: String, sequence: Int64, timestampMs: Int64?)
    case completed(requestId: String)
    case failed(requestId: String, error: SDKException)
    case cancelled(requestId: String)
}

// MARK: - VadEvent

/// Progress of one live VAD stream.
public enum VadEvent: Sendable {
    case speechStarted(timestampMs: Int64?)
    case speechEnded(timestampMs: Int64?)
    case activity(isSpeech: Bool, probability: Float, timestampMs: Int64?)
    case failed(SDKException)
    case completed
}

// MARK: - VoiceEvent

/// What the agent is doing right now.
public enum AgentState: Sendable {
    case listening
    case thinking
    case speaking
}

/// Turn-by-turn activity inside a live voice session.
public enum VoiceEvent: Sendable {
    case userTranscribed(text: String, isFinal: Bool)
    case agentStateChanged(AgentState)
    case agentResponse(text: String)
    case speechStarted
    case speechEnded

    /// The session is running and reading the microphone, but the microphone is
    /// not delivering a usable signal — muted, the wrong input device selected,
    /// or a host with no audio device at all. `detail` is the core's own
    /// measurement, e.g. "the microphone is delivering digital silence (every
    /// sample zero for 8s)".
    ///
    /// Separate from `.error` because nothing has failed: the pipeline is
    /// healthy and will hear the moment real signal arrives. Rendering it as an
    /// error would be wrong, and rendering it as nothing at all is what left the
    /// panel asserting "Go ahead — I'm listening" at a user it could not hear.
    /// The distinction is on the wire already (`ERROR_CODE_INSUFFICIENT_AUDIO_DATA`
    /// on a recoverable `VoiceSessionError`); this case stops the SDK throwing it
    /// away.
    case inputSilent(detail: String)

    case error(message: String, recoverable: Bool)

    /// Fold one native voice event onto the spec grammar, or drop it when it
    /// carries no caller-visible meaning.
    ///
    /// `OneOf_Payload.error` was deleted outright (idl/voice_events.proto:
    /// "The one error payload in this domain" is now `sessionError` alone),
    /// and `agentResponseStarted` collapsed from its own oneof arm into a
    /// `TurnLifecycleEventKind` value carried on the `turnLifecycle` arm.
    static func from(proto: RAVoiceEvent) -> VoiceEvent? {
        switch proto.payload {
        case .userSaid(let said):
            return .userTranscribed(text: said.text, isFinal: said.isFinal)
        case .assistantToken(let token):
            return token.text.isEmpty ? nil : .agentResponse(text: token.text)
        case .state(let change):
            return VoiceEvent.state(from: change.current).map { .agentStateChanged($0) }
        case .vad(let vad):
            if vad.type == .speechActivity {
                return vad.isSpeech ? .speechStarted : .speechEnded
            }
            return nil
        case .sessionError(let error):
            if error.code == .insufficientAudioData {
                return .inputSilent(detail: error.message)
            }
            return .error(message: error.message, recoverable: error.recoverable)
        case .turnLifecycle(let turn):
            switch turn.kind {
            case .agentResponseStarted:
                return .agentStateChanged(.speaking)
            // The core's in-feed segmenter reports the moment the energy gate
            // opens (voice_agent_feed_abi.cpp → USER_SPEECH_STARTED), which is
            // the only signal that arrives *while* the user is still talking.
            // Swift used to drop both of these and derive `.speechStarted`
            // solely from the `vad` arm, which the turn pipeline emits once,
            // after the utterance has already closed — and only when a VAD
            // model answered. With no VAD resident it never arrived at all, so
            // "I can't hear you" stayed on screen through a transcript and a
            // spoken reply. Kotlin has always mapped these two (VoiceSession.kt);
            // this is Swift catching up.
            case .userSpeechStarted:
                return .speechStarted
            case .userSpeechEnded:
                return .speechEnded
            case .failed where turn.hasError:
                return .error(message: turn.error.message, recoverable: turn.error.recoverable)
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func state(from pipeline: RAPipelineState) -> AgentState? {
        switch pipeline {
        case .listening, .waitingWakeword, .processingSpeech: return .listening
        case .thinking, .generatingResponse: return .thinking
        case .speaking, .playingTts: return .speaking
        default: return nil
        }
    }
}

// MARK: - RagEvent

/// Progress of one streaming RAG query.
public enum RagEvent: Sendable {
    case retrieved([Match])
    case token(text: String, kind: TokenKind)
    case completed(RagResult)
}

// MARK: - ImageEvent

/// Progress of one streaming image generation.
public enum ImageEvent: Sendable {
    case started
    case progress(step: Int, totalSteps: Int, partialImage: ImageData?)
    case completed(ImageResult)
}

// MARK: - DownloadEvent

/// Progress of one model download.
public enum DownloadEvent: Sendable {
    case started(operationId: String, sequence: Int64)
    case progress(DownloadProgressSnapshot)
    case verifying(operationId: String, sequence: Int64)
    case extracting(operationId: String, sequence: Int64, percent: Float?)
    case completed(operationId: String, sequence: Int64, model: ModelInfo)
    case failed(operationId: String, sequence: Int64, error: SDKException)
    case cancelled(operationId: String, sequence: Int64)
}

/// What a download looks like to a caller at one instant.
///
/// ## Why this is a struct and not six more associated values
///
/// `.progress` used to be a six-tuple, which meant every consumer wrote
/// `case .progress(_, _, _, _, let percent, _)` — five wildcards to reach one
/// value, and a pattern that silently changes meaning if a field is ever
/// inserted. Adding speed and ETA that way would have made it eleven positions.
///
/// ## Why these fields exist at all
///
/// A model is hundreds of megabytes to several gigabytes, so a bare percentage
/// cannot distinguish a slow transfer from a stalled one. C++ already measures
/// throughput and projects a finish time (`download_orchestrator.cpp` sets
/// `bytes_per_second` and `eta_seconds`), and the `DownloadProgress` proto has
/// carried both — along with the retry count and the position in a multi-file
/// plan — the whole time. Those fields were computed, sent across the ABI, and
/// then dropped at this boundary, so no consumer could show a rate or a
/// remaining time no matter what it did.
///
/// They are surfaced rather than re-derived per platform on purpose: five SDKs
/// each computing a rate from two successive UI-thread samples would disagree
/// with each other and with the transfer that knows its own history.
///
/// Optional fields are `nil` when genuinely unknown rather than `0`, so a
/// caller can omit a row instead of rendering "0 B/s" while the connection is
/// still opening. This mirrors `DownloadEvent.Progress` in the Kotlin SDK
/// field-for-field.
public struct DownloadProgressSnapshot: Sendable, Equatable {
    public let operationId: String
    public let sequence: Int64
    public let bytesDone: Int64
    /// 0 when the server never sent a length.
    public let bytesTotal: Int64
    /// Name of the file currently transferring, when the plan names one.
    public let file: String?
    /// Measured throughput. `nil` when not yet known — never a zero standing in
    /// for unknown.
    public let bytesPerSecond: Float?
    /// Projected seconds remaining. `nil` when the total size or the rate is
    /// unknown.
    public let etaSeconds: Int64?
    /// 0 on the first attempt. Above 0 means the transfer recovered from a
    /// failure, which a UI should show rather than hide.
    public let retryAttempt: Int
    /// 0-based position in the planned file list.
    public let currentFileIndex: Int
    /// Files in the plan. 1 for a single-file model.
    public let totalFiles: Int

    /// Progress across the whole plan as reported by the transfer, 0...1.
    let overallProgress: Float?

    public init(
        operationId: String,
        sequence: Int64,
        bytesDone: Int64,
        bytesTotal: Int64,
        file: String? = nil,
        bytesPerSecond: Float? = nil,
        etaSeconds: Int64? = nil,
        retryAttempt: Int = 0,
        currentFileIndex: Int = 0,
        totalFiles: Int = 1,
        overallProgress: Float? = nil
    ) {
        self.operationId = operationId
        self.sequence = sequence
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.file = file
        self.bytesPerSecond = bytesPerSecond
        self.etaSeconds = etaSeconds
        self.retryAttempt = retryAttempt
        self.currentFileIndex = currentFileIndex
        self.totalFiles = totalFiles
        self.overallProgress = overallProgress
    }

    /// Fraction of the whole download that is done, 0...1, or `nil` when the
    /// size is unknown.
    ///
    /// Uses `rac_download_progress_percent` (overall preferred when in range;
    /// else bytes). Reports `nil` rather than a fake `0` when both inputs are
    /// unusable so a caller can show an indeterminate bar.
    public var fraction: Float? {
        percent.map { $0 / 100 }
    }

    /// `fraction` as 0–100, or `nil` when the size is unknown.
    public var percent: Float? {
        let overall = overallProgress ?? -1
        let pct = rac_download_progress_percent(
            overall,
            Int64(bytesDone),
            Int64(bytesTotal)
        )
        if overallProgress == nil && bytesTotal <= 0 { return nil }
        return Float(pct)
    }

    /// True when the size is unknown, so the caller should show an
    /// indeterminate bar.
    public var isIndeterminate: Bool { fraction == nil }
}

// MARK: - SdkEvent

/// Lifecycle, download, and error breadcrumbs from the SDK itself.
public enum SdkEvent: Sendable {
    case ready
    case modelLoaded(id: String, category: ModelCategory)
    case modelUnloaded(id: String)
    case error(message: String, recoverable: Bool)

    /// Fold one raw proto envelope onto the spec grammar, or drop it.
    static func from(proto: RASDKEvent) -> SdkEvent? {
        if proto.category == .initialization, proto.initialization.stage == .completed {
            return .ready
        }
        // FailureEvent was deleted outright (idl/sdk_events.proto: "every
        // field already exists on the envelope -- component ->
        // SDKEvent.component, operation -> SDKEvent.operation_id, error ->
        // SDKEvent.error, recoverable -> SDKError.retryable. A failure is
        // any event whose envelope `error` is set"). `.failure` and `.error`
        // categories both now read off the same top-level `error` field.
        if proto.category == .failure || proto.category == .error {
            let message = proto.hasError ? proto.error.message : "SDK error"
            return .error(message: message, recoverable: proto.hasError ? proto.error.retryable : false)
        }
        guard let change = EventBus.modelLifecycleChange(from: proto) else { return nil }
        switch change.kind {
        case .loaded:
            return .modelLoaded(id: change.modelID, category: SdkEvent.category(for: change.component))
        case .unloaded:
            return .modelUnloaded(id: change.modelID)
        }
    }

    private static func category(for component: RASDKComponent) -> ModelCategory {
        switch component {
        case .llm: return .language
        case .stt: return .speechRecognition
        case .tts: return .speechSynthesis
        case .vad: return .voiceActivityDetection
        case .vlm: return .multimodal
        case .diffusion: return .imageGeneration
        case .embeddings: return .embedding
        case .speakerDiarization: return .speakerDiarization
        case .semanticSegmentation: return .semanticSegmentation
        case .ocr: return .ocr
        default: return .unspecified
        }
    }
}

// MARK: - RunAnywhere.events

public extension RunAnywhere {

    /// Lifecycle, download, and error breadcrumbs as they happen.
    ///
    /// ```swift
    /// for await event in RunAnywhere.events { print(event) }
    /// ```
    static var events: AsyncStream<SdkEvent> {
        AsyncStream { continuation in
            let subscription = CppBridge.Events.subscribeSDKEvents { proto in
                if let event = SdkEvent.from(proto: proto) {
                    continuation.yield(event)
                }
            }
            continuation.onTermination = { @Sendable _ in
                CppBridge.Events.unsubscribeSDKEvents(subscription)
            }
        }
    }

    /// Combine-based access to the raw proto event envelopes.
    ///
    /// Use this when `events` has folded away a field you need — download
    /// byte counts, per-component progress, telemetry payloads.
    static var eventBus: EventBus { EventBus.shared }
}
