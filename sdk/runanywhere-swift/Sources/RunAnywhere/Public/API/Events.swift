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
    case token(text: String, kind: TokenKind)
    case toolCall(ToolCall)
    case completed(GenerationResult)
}

// MARK: - TranscriptionEvent

/// Progress of one streaming transcription.
public enum TranscriptionEvent: Sendable {
    case started
    case partial(text: String)
    case final(Transcription)
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
        case .error(let error):
            return .error(message: error.message, recoverable: error.isRecoverable)
        case .sessionError(let error):
            return .error(message: error.message, recoverable: error.recoverable)
        case .agentResponseStarted:
            return .agentStateChanged(.speaking)
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
    case progress(bytesDone: Int64, bytesTotal: Int64, percent: Float)
    case extracting
    case completed(ModelInfo)
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
        if proto.category == .failure {
            let failure = proto.failure
            let message = failure.hasError ? failure.error.message : "SDK operation failed"
            return .error(message: message, recoverable: failure.recoverable)
        }
        if proto.category == .error {
            let message = proto.hasError ? proto.error.message : "SDK error"
            return .error(message: message, recoverable: false)
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
