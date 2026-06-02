import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { ComponentLifecycleState, EventCategory } from "./component_types";
import { ErrorCode, ErrorSeverity } from "./errors";
import { VADStreamEventKind } from "./vad_options";
export declare const protobufPackage = "runanywhere.v1";
export declare enum VoicePipelineComponent {
    VOICE_PIPELINE_COMPONENT_UNSPECIFIED = 0,
    VOICE_PIPELINE_COMPONENT_AGENT = 1,
    VOICE_PIPELINE_COMPONENT_STT = 2,
    VOICE_PIPELINE_COMPONENT_ASR = 3,
    VOICE_PIPELINE_COMPONENT_TTS = 4,
    VOICE_PIPELINE_COMPONENT_VAD = 5,
    VOICE_PIPELINE_COMPONENT_STD = 6,
    VOICE_PIPELINE_COMPONENT_LLM = 7,
    VOICE_PIPELINE_COMPONENT_AUDIO = 8,
    VOICE_PIPELINE_COMPONENT_WAKEWORD = 9,
    UNRECOGNIZED = -1
}
export declare function voicePipelineComponentFromJSON(object: any): VoicePipelineComponent;
export declare function voicePipelineComponentToJSON(object: VoicePipelineComponent): string;
export declare enum TokenKind {
    TOKEN_KIND_UNSPECIFIED = 0,
    /** TOKEN_KIND_ANSWER - Regular content token */
    TOKEN_KIND_ANSWER = 1,
    /** TOKEN_KIND_THOUGHT - Chain-of-thought token (qwen3, deepseek-r1) */
    TOKEN_KIND_THOUGHT = 2,
    /** TOKEN_KIND_TOOL_CALL - Parsed tool-call directive */
    TOKEN_KIND_TOOL_CALL = 3,
    UNRECOGNIZED = -1
}
export declare function tokenKindFromJSON(object: any): TokenKind;
export declare function tokenKindToJSON(object: TokenKind): string;
export declare enum AudioEncoding {
    AUDIO_ENCODING_UNSPECIFIED = 0,
    AUDIO_ENCODING_PCM_F32_LE = 1,
    AUDIO_ENCODING_PCM_S16_LE = 2,
    UNRECOGNIZED = -1
}
export declare function audioEncodingFromJSON(object: any): AudioEncoding;
export declare function audioEncodingToJSON(object: AudioEncoding): string;
export declare enum InterruptReason {
    INTERRUPT_REASON_UNSPECIFIED = 0,
    INTERRUPT_REASON_USER_BARGE_IN = 1,
    INTERRUPT_REASON_APP_STOP = 2,
    INTERRUPT_REASON_AUDIO_ROUTE_CHANGE = 3,
    INTERRUPT_REASON_TIMEOUT = 4,
    UNRECOGNIZED = -1
}
export declare function interruptReasonFromJSON(object: any): InterruptReason;
export declare function interruptReasonToJSON(object: InterruptReason): string;
export declare enum PipelineState {
    PIPELINE_STATE_UNSPECIFIED = 0,
    PIPELINE_STATE_IDLE = 1,
    PIPELINE_STATE_LISTENING = 2,
    PIPELINE_STATE_THINKING = 3,
    PIPELINE_STATE_SPEAKING = 4,
    PIPELINE_STATE_STOPPED = 5,
    PIPELINE_STATE_WAITING_WAKEWORD = 6,
    PIPELINE_STATE_PROCESSING_SPEECH = 7,
    PIPELINE_STATE_GENERATING_RESPONSE = 8,
    PIPELINE_STATE_PLAYING_TTS = 9,
    PIPELINE_STATE_COOLDOWN = 10,
    PIPELINE_STATE_ERROR = 11,
    UNRECOGNIZED = -1
}
export declare function pipelineStateFromJSON(object: any): PipelineState;
export declare function pipelineStateToJSON(object: PipelineState): string;
export declare enum SpeechTurnDetectionEventKind {
    SPEECH_TURN_DETECTION_EVENT_KIND_UNSPECIFIED = 0,
    SPEECH_TURN_DETECTION_EVENT_KIND_TURN_STARTED = 1,
    SPEECH_TURN_DETECTION_EVENT_KIND_TURN_ENDED = 2,
    SPEECH_TURN_DETECTION_EVENT_KIND_SPEAKER_CHANGED = 3,
    SPEECH_TURN_DETECTION_EVENT_KIND_STATISTICS = 4,
    UNRECOGNIZED = -1
}
export declare function speechTurnDetectionEventKindFromJSON(object: any): SpeechTurnDetectionEventKind;
export declare function speechTurnDetectionEventKindToJSON(object: SpeechTurnDetectionEventKind): string;
export declare enum TurnLifecycleEventKind {
    TURN_LIFECYCLE_EVENT_KIND_UNSPECIFIED = 0,
    TURN_LIFECYCLE_EVENT_KIND_STARTED = 1,
    TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED = 2,
    TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED = 3,
    TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL = 4,
    TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED = 5,
    TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED = 6,
    TURN_LIFECYCLE_EVENT_KIND_COMPLETED = 7,
    TURN_LIFECYCLE_EVENT_KIND_CANCELLED = 8,
    TURN_LIFECYCLE_EVENT_KIND_FAILED = 9,
    UNRECOGNIZED = -1
}
export declare function turnLifecycleEventKindFromJSON(object: any): TurnLifecycleEventKind;
export declare function turnLifecycleEventKindToJSON(object: TurnLifecycleEventKind): string;
/**
 * ---------------------------------------------------------------------------
 * Sum type emitted on the output edge of the VoiceAgent pipeline.
 * ---------------------------------------------------------------------------
 */
export interface VoiceEvent {
    /**
     * Monotonic pipeline-local sequence number. Useful for frontends that
     * need to detect gaps after reconnection or out-of-order delivery.
     */
    seq: number;
    /**
     * Wall-clock timestamp captured at the C++ edge, in microseconds since
     * Unix epoch. Frontends may re-timestamp for UI display.
     */
    timestampUs: number;
    category: EventCategory;
    severity: ErrorSeverity;
    component: VoicePipelineComponent;
    userSaid?: UserSaidEvent | undefined;
    assistantToken?: AssistantTokenEvent | undefined;
    audio?: AudioFrameEvent | undefined;
    vad?: VADEvent | undefined;
    interrupted?: InterruptedEvent | undefined;
    state?: StateChangeEvent | undefined;
    error?: ErrorEvent | undefined;
    metrics?: MetricsEvent | undefined;
    /**
     * Voice agent lifecycle events. Mirror Swift VoiceSessionError /
     * VoiceAgentComponentStates and the AsyncSequence-style lifecycle
     * signals consumed by the cross-platform VoiceAgent extensions
     * (Swift VoiceAgentTypes.swift, Kotlin VoiceAgentTypes.kt, RN
     * VoiceAgentTypes.ts, Web VoiceAgentCTypes.ts, Flutter
     * voice_agent_types.dart).
     */
    componentStateChanged?: VoiceAgentComponentStates | undefined;
    sessionError?: VoiceSessionError | undefined;
    sessionStarted?: SessionStartedEvent | undefined;
    sessionStopped?: SessionStoppedEvent | undefined;
    agentResponseStarted?: AgentResponseStartedEvent | undefined;
    agentResponseCompleted?: AgentResponseCompletedEvent | undefined;
    speechTurnDetection?: SpeechTurnDetectionEvent | undefined;
    turnLifecycle?: TurnLifecycleEvent | undefined;
    wakewordDetected?: WakeWordDetectedEvent | undefined;
    audioLevel?: AudioLevelEvent | undefined;
    componentProgress?: ComponentProgressEvent | undefined;
    /** Correlation fields shared by streaming and one-shot voice turns. */
    sessionId: string;
    turnId: string;
    requestId: string;
    metadata: {
        [key: string]: string;
    };
}
export interface VoiceEvent_MetadataEntry {
    key: string;
    value: string;
}
/** User speech finalized by STT (is_final=false → partial hypothesis). */
export interface UserSaidEvent {
    text: string;
    isFinal: boolean;
    /** 0.0..1.0, engine-dependent */
    confidence: number;
    audioStartUs: number;
    audioEndUs: number;
    languageCode: string;
    segmentIndex: number;
}
/**
 * Single token decoded by the LLM. is_final=true on the last token of a
 * response (end-of-stream marker).
 */
export interface AssistantTokenEvent {
    text: string;
    isFinal: boolean;
    kind: TokenKind;
    tokenId: number;
    logprob: number;
    finishReason: string;
}
/**
 * A chunk of synthesized PCM audio, ready for the sink. The frontend is
 * expected to copy the bytes out; the C ABI does NOT retain ownership.
 */
export interface AudioFrameEvent {
    /** f32 little-endian interleaved */
    pcm: Uint8Array;
    /** usually 24000 for Kokoro, 22050 for Piper */
    sampleRateHz: number;
    /** 1 for mono */
    channels: number;
    encoding: AudioEncoding;
    /** True for the final audio chunk in a TTS/voice-agent audio stream. */
    isFinal: boolean;
    chunkIndex: number;
    durationMs: number;
}
/**
 * Voice Activity Detection output. Frontends usually do not need this —
 * exposed for debugging and custom UIs (waveform highlighting, etc.).
 * `type` uses the canonical VADStreamEventKind enum from
 * vad_options.proto (the hand-rolled VADEventType was deleted).
 */
export interface VADEvent {
    type: VADStreamEventKind;
    frameOffsetUs: number;
    confidence: number;
    isSpeech: boolean;
    speechDurationMs: number;
    silenceDurationMs: number;
    noiseFloorDb: number;
}
/**
 * Assistant playback was interrupted by a barge-in. The reason distinguishes
 * user barge-in from app-initiated cancel.
 */
export interface InterruptedEvent {
    reason: InterruptReason;
    detail: string;
}
/** Pipeline lifecycle state. Ordered — callers can compare numerically. */
export interface StateChangeEvent {
    previous: PipelineState;
    current: PipelineState;
}
/**
 * Terminal or recoverable error in the pipeline. Frontends map these to
 * their native error types.
 */
export interface ErrorEvent {
    /** See ra_status_t in core/abi/ra_primitives.h */
    code: number;
    message: string;
    /** "llm", "stt", "tts", "vad", "pipeline", ... */
    component: string;
    isRecoverable: boolean;
    operation: string;
    detailsJson: string;
}
/** Per-primitive latency breakdown. Emitted at barge-in and at pipeline stop. */
export interface MetricsEvent {
    sttFinalMs: number;
    llmFirstTokenMs: number;
    ttsFirstAudioMs: number;
    endToEndMs: number;
    tokensGenerated: number;
    audioSamplesPlayed: number;
    /**
     * True when `end_to_end_ms` exceeded the `PipelineOptions.latency_budget_ms`
     * configured for this run. Frontends can surface this to the UI for SLO
     * dashboards without re-computing the threshold themselves.
     */
    isOverBudget: boolean;
    /**
     * Monotonic producer-side timestamp in nanoseconds. Set by the
     * producer (C++ dispatcher) at event-emit time; read by consumers
     * (5-SDK perf_bench + p50 benchmark CI) to compute event-to-frontend
     * latency without relying on wall-clock sync. Encoded as int64 so
     * std::chrono::steady_clock::now().time_since_epoch() values fit
     * directly (2^63 ns ≈ 292 years of runtime headroom).
     */
    createdAtNs: number;
    vadFirstSpeechMs: number;
    sttFirstPartialMs: number;
    llmTotalMs: number;
    ttsTotalMs: number;
}
export interface AudioLevelEvent {
    rms: number;
    peak: number;
    noiseFloorDb: number;
    isSpeech: boolean;
}
export interface ComponentProgressEvent {
    component: VoicePipelineComponent;
    operation: string;
    progress: number;
    message: string;
}
/**
 * Aggregate load state across all four voice-agent components. Mirrors Swift
 * `VoiceAgentComponentStates`, Kotlin `VoiceAgentComponentStates`, RN
 * `VoiceAgentComponentStates`, Web `VoiceAgentComponentStates`, and Flutter
 * `VoiceAgentComponentStates`.
 *
 * The former `ComponentLoadState` enum was consolidated into the
 * canonical richer `ComponentLifecycleState` (component_types.proto). Where
 * the old enum's `COMPONENT_LOAD_STATE_LOADED` value was used to mean "this
 * component is ready to use", callers now use
 * `COMPONENT_LIFECYCLE_STATE_READY`.
 */
export interface VoiceAgentComponentStates {
    sttState: ComponentLifecycleState;
    llmState: ComponentLifecycleState;
    ttsState: ComponentLifecycleState;
    vadState: ComponentLifecycleState;
    /**
     * Computed: true when stt_state, llm_state, tts_state, vad_state are all
     * COMPONENT_LIFECYCLE_STATE_READY. Producer sets this; consumers must NOT
     * recompute.
     */
    ready: boolean;
    /**
     * Computed: true when any of the four states is
     * COMPONENT_LIFECYCLE_STATE_LOADING.
     */
    anyLoading: boolean;
    wakewordState: ComponentLifecycleState;
    errorMessage?: string | undefined;
}
export interface VoiceSessionError {
    code: ErrorCode;
    message: string;
    failedComponent?: string | undefined;
    cAbiCode: number;
    recoverable: boolean;
}
export interface SessionStartedEvent {
    sessionId: string;
}
export interface SessionStoppedEvent {
    sessionId: string;
    reason: string;
}
export interface AgentResponseStartedEvent {
    turnId: string;
}
export interface AgentResponseCompletedEvent {
    turnId: string;
    responseDurationMs: number;
}
export interface SpeechTurnDetectionEvent {
    kind: SpeechTurnDetectionEventKind;
    speakerId: string;
    turnStartUs: number;
    turnEndUs: number;
    confidence: number;
    speechDurationMs: number;
    silenceDurationMs: number;
}
export interface TurnLifecycleEvent {
    kind: TurnLifecycleEventKind;
    turnId: string;
    sessionId: string;
    transcript: string;
    response: string;
    error: string;
    startedAtMs: number;
    completedAtMs: number;
}
export interface WakeWordDetectedEvent {
    wakeWord: string;
    confidence: number;
    timestampMs: number;
    modelId: string;
    modelIndex: number;
    durationMs: number;
}
export declare const VoiceEvent: MessageFns<VoiceEvent>;
export declare const VoiceEvent_MetadataEntry: MessageFns<VoiceEvent_MetadataEntry>;
export declare const UserSaidEvent: MessageFns<UserSaidEvent>;
export declare const AssistantTokenEvent: MessageFns<AssistantTokenEvent>;
export declare const AudioFrameEvent: MessageFns<AudioFrameEvent>;
export declare const VADEvent: MessageFns<VADEvent>;
export declare const InterruptedEvent: MessageFns<InterruptedEvent>;
export declare const StateChangeEvent: MessageFns<StateChangeEvent>;
export declare const ErrorEvent: MessageFns<ErrorEvent>;
export declare const MetricsEvent: MessageFns<MetricsEvent>;
export declare const AudioLevelEvent: MessageFns<AudioLevelEvent>;
export declare const ComponentProgressEvent: MessageFns<ComponentProgressEvent>;
export declare const VoiceAgentComponentStates: MessageFns<VoiceAgentComponentStates>;
export declare const VoiceSessionError: MessageFns<VoiceSessionError>;
export declare const SessionStartedEvent: MessageFns<SessionStartedEvent>;
export declare const SessionStoppedEvent: MessageFns<SessionStoppedEvent>;
export declare const AgentResponseStartedEvent: MessageFns<AgentResponseStartedEvent>;
export declare const AgentResponseCompletedEvent: MessageFns<AgentResponseCompletedEvent>;
export declare const SpeechTurnDetectionEvent: MessageFns<SpeechTurnDetectionEvent>;
export declare const TurnLifecycleEvent: MessageFns<TurnLifecycleEvent>;
export declare const WakeWordDetectedEvent: MessageFns<WakeWordDetectedEvent>;
type Builtin = Date | Function | Uint8Array | string | number | boolean | undefined;
export type DeepPartial<T> = T extends Builtin ? T : T extends globalThis.Array<infer U> ? globalThis.Array<DeepPartial<U>> : T extends ReadonlyArray<infer U> ? ReadonlyArray<DeepPartial<U>> : T extends {} ? {
    [K in keyof T]?: DeepPartial<T[K]>;
} : Partial<T>;
type KeysOfUnion<T> = T extends T ? keyof T : never;
export type Exact<P, I extends P> = P extends Builtin ? P : P & {
    [K in keyof P]: Exact<P[K], I[K]>;
} & {
    [K in Exclude<keyof I, KeysOfUnion<P>>]: never;
};
export interface MessageFns<T> {
    encode(message: T, writer?: BinaryWriter): BinaryWriter;
    decode(input: BinaryReader | Uint8Array, length?: number): T;
    fromJSON(object: any): T;
    toJSON(message: T): unknown;
    create<I extends Exact<DeepPartial<T>, I>>(base?: I): T;
    fromPartial<I extends Exact<DeepPartial<T>, I>>(object: I): T;
}
export {};
