//
//  Events.swift
//  RunAnywhere SDK
//
//  One event grammar for every stream: `started`, then deltas, then
//  `completed`. Failures are thrown into the consumer, never smuggled through
//  a payload field.
//

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
            return .error(message: error.message, recoverable: error.recoverable)
        case .turnLifecycle(let turn):
            if turn.kind == .agentResponseStarted {
                return .agentStateChanged(.speaking)
            }
            if turn.kind == .failed, turn.hasError {
                return .error(message: turn.error.message, recoverable: turn.error.recoverable)
            }
            return nil
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
    case progress(operationId: String, sequence: Int64, bytesDone: Int64, bytesTotal: Int64, percent: Float, file: String?)
    case verifying(operationId: String, sequence: Int64)
    case extracting(operationId: String, sequence: Int64, percent: Float?)
    case completed(operationId: String, sequence: Int64, model: ModelInfo)
    case failed(operationId: String, sequence: Int64, error: SDKException)
    case cancelled(operationId: String, sequence: Int64)
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
