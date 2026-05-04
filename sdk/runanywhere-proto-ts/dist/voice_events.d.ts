import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
export declare enum VoiceEventCategory {
    VOICE_EVENT_CATEGORY_UNSPECIFIED = 0,
    VOICE_EVENT_CATEGORY_VOICE_AGENT = 1,
    VOICE_EVENT_CATEGORY_STT = 2,
    VOICE_EVENT_CATEGORY_ASR = 3,
    VOICE_EVENT_CATEGORY_TTS = 4,
    VOICE_EVENT_CATEGORY_VAD = 5,
    VOICE_EVENT_CATEGORY_STD = 6,
    VOICE_EVENT_CATEGORY_LLM = 7,
    VOICE_EVENT_CATEGORY_AUDIO = 8,
    VOICE_EVENT_CATEGORY_METRICS = 9,
    VOICE_EVENT_CATEGORY_ERROR = 10,
    VOICE_EVENT_CATEGORY_WAKEWORD = 11,
    UNRECOGNIZED = -1
}
export declare function voiceEventCategoryFromJSON(object: any): VoiceEventCategory;
export declare function voiceEventCategoryToJSON(object: VoiceEventCategory): string;
export declare enum VoiceEventSeverity {
    VOICE_EVENT_SEVERITY_DEBUG = 0,
    VOICE_EVENT_SEVERITY_INFO = 1,
    VOICE_EVENT_SEVERITY_WARNING = 2,
    VOICE_EVENT_SEVERITY_ERROR = 3,
    VOICE_EVENT_SEVERITY_CRITICAL = 4,
    UNRECOGNIZED = -1
}
export declare function voiceEventSeverityFromJSON(object: any): VoiceEventSeverity;
export declare function voiceEventSeverityToJSON(object: VoiceEventSeverity): string;
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
export declare enum VADEventType {
    VAD_EVENT_UNSPECIFIED = 0,
    VAD_EVENT_VOICE_START = 1,
    VAD_EVENT_VOICE_END_OF_UTTERANCE = 2,
    VAD_EVENT_BARGE_IN = 3,
    VAD_EVENT_SILENCE = 4,
    VAD_EVENT_STATISTICS = 5,
    VAD_EVENT_STATE_CHANGED = 6,
    UNRECOGNIZED = -1
}
export declare function vADEventTypeFromJSON(object: any): VADEventType;
export declare function vADEventTypeToJSON(object: VADEventType): string;
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
/**
 * Loading state of a single voice-agent component (STT, LLM, TTS, VAD).
 * UNSPECIFIED preserves proto3 zero-value semantics — frontends MUST treat it
 * the same as NOT_LOADED for forward-compatibility.
 */
export declare enum ComponentLoadState {
    COMPONENT_LOAD_STATE_UNSPECIFIED = 0,
    COMPONENT_LOAD_STATE_NOT_LOADED = 1,
    COMPONENT_LOAD_STATE_LOADING = 2,
    COMPONENT_LOAD_STATE_LOADED = 3,
    COMPONENT_LOAD_STATE_ERROR = 4,
    UNRECOGNIZED = -1
}
export declare function componentLoadStateFromJSON(object: any): ComponentLoadState;
export declare function componentLoadStateToJSON(object: ComponentLoadState): string;
export declare enum VoiceSessionErrorCode {
    VOICE_SESSION_ERROR_CODE_UNSPECIFIED = 0,
    VOICE_SESSION_ERROR_CODE_MICROPHONE_PERMISSION_DENIED = 1,
    VOICE_SESSION_ERROR_CODE_NOT_READY = 2,
    VOICE_SESSION_ERROR_CODE_ALREADY_RUNNING = 3,
    VOICE_SESSION_ERROR_CODE_COMPONENT_FAILURE = 4,
    UNRECOGNIZED = -1
}
export declare function voiceSessionErrorCodeFromJSON(object: any): VoiceSessionErrorCode;
export declare function voiceSessionErrorCodeToJSON(object: VoiceSessionErrorCode): string;
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
    category: VoiceEventCategory;
    severity: VoiceEventSeverity;
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
     * v3.2: Voice agent lifecycle events. Mirror Swift VoiceSessionError /
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
}
/** User speech finalized by STT (is_final=false → partial hypothesis). */
export interface UserSaidEvent {
    text: string;
    isFinal: boolean;
    /** 0.0..1.0, engine-dependent */
    confidence: number;
    audioStartUs: number;
    audioEndUs: number;
}
/**
 * Single token decoded by the LLM. is_final=true on the last token of a
 * response (end-of-stream marker).
 */
export interface AssistantTokenEvent {
    text: string;
    isFinal: boolean;
    kind: TokenKind;
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
}
/**
 * Voice Activity Detection output. Frontends usually do not need this —
 * exposed for debugging and custom UIs (waveform highlighting, etc.).
 */
export interface VADEvent {
    type: VADEventType;
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
     * v3.1: monotonic producer-side timestamp in nanoseconds. Set by the
     * producer (C++ dispatcher) at event-emit time; read by consumers
     * (5-SDK perf_bench + p50 benchmark CI) to compute event-to-frontend
     * latency without relying on wall-clock sync. Encoded as int64 so
     * std::chrono::steady_clock::now().time_since_epoch() values fit
     * directly (2^63 ns ≈ 292 years of runtime headroom).
     */
    createdAtNs: number;
}
/**
 * Aggregate load state across all four voice-agent components. Mirrors Swift
 * `VoiceAgentComponentStates`, Kotlin `VoiceAgentComponentStates`, RN
 * `VoiceAgentComponentStates`, Web `VoiceAgentComponentStates`, and Flutter
 * `VoiceAgentComponentStates`.
 */
export interface VoiceAgentComponentStates {
    sttState: ComponentLoadState;
    llmState: ComponentLoadState;
    ttsState: ComponentLoadState;
    vadState: ComponentLoadState;
    /**
     * Computed: true when stt_state, llm_state, tts_state, vad_state are all
     * COMPONENT_LOAD_STATE_LOADED. Producer sets this; consumers must NOT
     * recompute.
     */
    ready: boolean;
    /** Computed: true when any of the four states is COMPONENT_LOAD_STATE_LOADING. */
    anyLoading: boolean;
}
export interface VoiceSessionError {
    code: VoiceSessionErrorCode;
    message: string;
    failedComponent?: string | undefined;
}
export interface SessionStartedEvent {
}
export interface SessionStoppedEvent {
}
export interface AgentResponseStartedEvent {
}
export interface AgentResponseCompletedEvent {
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
}
export interface WakeWordDetectedEvent {
    wakeWord: string;
    confidence: number;
    timestampMs: number;
    modelId: string;
    modelIndex: number;
    durationMs: number;
}
export declare const VoiceEvent: {
    encode(message: VoiceEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): VoiceEvent;
    fromJSON(object: any): VoiceEvent;
    toJSON(message: VoiceEvent): unknown;
    create<I extends Exact<DeepPartial<VoiceEvent>, I>>(base?: I): VoiceEvent;
    fromPartial<I extends Exact<DeepPartial<VoiceEvent>, I>>(object: I): VoiceEvent;
};
export declare const UserSaidEvent: {
    encode(message: UserSaidEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): UserSaidEvent;
    fromJSON(object: any): UserSaidEvent;
    toJSON(message: UserSaidEvent): unknown;
    create<I extends Exact<DeepPartial<UserSaidEvent>, I>>(base?: I): UserSaidEvent;
    fromPartial<I extends Exact<DeepPartial<UserSaidEvent>, I>>(object: I): UserSaidEvent;
};
export declare const AssistantTokenEvent: {
    encode(message: AssistantTokenEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): AssistantTokenEvent;
    fromJSON(object: any): AssistantTokenEvent;
    toJSON(message: AssistantTokenEvent): unknown;
    create<I extends Exact<DeepPartial<AssistantTokenEvent>, I>>(base?: I): AssistantTokenEvent;
    fromPartial<I extends Exact<DeepPartial<AssistantTokenEvent>, I>>(object: I): AssistantTokenEvent;
};
export declare const AudioFrameEvent: {
    encode(message: AudioFrameEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): AudioFrameEvent;
    fromJSON(object: any): AudioFrameEvent;
    toJSON(message: AudioFrameEvent): unknown;
    create<I extends Exact<DeepPartial<AudioFrameEvent>, I>>(base?: I): AudioFrameEvent;
    fromPartial<I extends Exact<DeepPartial<AudioFrameEvent>, I>>(object: I): AudioFrameEvent;
};
export declare const VADEvent: {
    encode(message: VADEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): VADEvent;
    fromJSON(object: any): VADEvent;
    toJSON(message: VADEvent): unknown;
    create<I extends Exact<DeepPartial<VADEvent>, I>>(base?: I): VADEvent;
    fromPartial<I extends Exact<DeepPartial<VADEvent>, I>>(object: I): VADEvent;
};
export declare const InterruptedEvent: {
    encode(message: InterruptedEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): InterruptedEvent;
    fromJSON(object: any): InterruptedEvent;
    toJSON(message: InterruptedEvent): unknown;
    create<I extends Exact<DeepPartial<InterruptedEvent>, I>>(base?: I): InterruptedEvent;
    fromPartial<I extends Exact<DeepPartial<InterruptedEvent>, I>>(object: I): InterruptedEvent;
};
export declare const StateChangeEvent: {
    encode(message: StateChangeEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): StateChangeEvent;
    fromJSON(object: any): StateChangeEvent;
    toJSON(message: StateChangeEvent): unknown;
    create<I extends Exact<DeepPartial<StateChangeEvent>, I>>(base?: I): StateChangeEvent;
    fromPartial<I extends Exact<DeepPartial<StateChangeEvent>, I>>(object: I): StateChangeEvent;
};
export declare const ErrorEvent: {
    encode(message: ErrorEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ErrorEvent;
    fromJSON(object: any): ErrorEvent;
    toJSON(message: ErrorEvent): unknown;
    create<I extends Exact<DeepPartial<ErrorEvent>, I>>(base?: I): ErrorEvent;
    fromPartial<I extends Exact<DeepPartial<ErrorEvent>, I>>(object: I): ErrorEvent;
};
export declare const MetricsEvent: {
    encode(message: MetricsEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): MetricsEvent;
    fromJSON(object: any): MetricsEvent;
    toJSON(message: MetricsEvent): unknown;
    create<I extends Exact<DeepPartial<MetricsEvent>, I>>(base?: I): MetricsEvent;
    fromPartial<I extends Exact<DeepPartial<MetricsEvent>, I>>(object: I): MetricsEvent;
};
export declare const VoiceAgentComponentStates: {
    encode(message: VoiceAgentComponentStates, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): VoiceAgentComponentStates;
    fromJSON(object: any): VoiceAgentComponentStates;
    toJSON(message: VoiceAgentComponentStates): unknown;
    create<I extends Exact<DeepPartial<VoiceAgentComponentStates>, I>>(base?: I): VoiceAgentComponentStates;
    fromPartial<I extends Exact<DeepPartial<VoiceAgentComponentStates>, I>>(object: I): VoiceAgentComponentStates;
};
export declare const VoiceSessionError: {
    encode(message: VoiceSessionError, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): VoiceSessionError;
    fromJSON(object: any): VoiceSessionError;
    toJSON(message: VoiceSessionError): unknown;
    create<I extends Exact<DeepPartial<VoiceSessionError>, I>>(base?: I): VoiceSessionError;
    fromPartial<I extends Exact<DeepPartial<VoiceSessionError>, I>>(object: I): VoiceSessionError;
};
export declare const SessionStartedEvent: {
    encode(_: SessionStartedEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): SessionStartedEvent;
    fromJSON(_: any): SessionStartedEvent;
    toJSON(_: SessionStartedEvent): unknown;
    create<I extends Exact<DeepPartial<SessionStartedEvent>, I>>(base?: I): SessionStartedEvent;
    fromPartial<I extends Exact<DeepPartial<SessionStartedEvent>, I>>(_: I): SessionStartedEvent;
};
export declare const SessionStoppedEvent: {
    encode(_: SessionStoppedEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): SessionStoppedEvent;
    fromJSON(_: any): SessionStoppedEvent;
    toJSON(_: SessionStoppedEvent): unknown;
    create<I extends Exact<DeepPartial<SessionStoppedEvent>, I>>(base?: I): SessionStoppedEvent;
    fromPartial<I extends Exact<DeepPartial<SessionStoppedEvent>, I>>(_: I): SessionStoppedEvent;
};
export declare const AgentResponseStartedEvent: {
    encode(_: AgentResponseStartedEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): AgentResponseStartedEvent;
    fromJSON(_: any): AgentResponseStartedEvent;
    toJSON(_: AgentResponseStartedEvent): unknown;
    create<I extends Exact<DeepPartial<AgentResponseStartedEvent>, I>>(base?: I): AgentResponseStartedEvent;
    fromPartial<I extends Exact<DeepPartial<AgentResponseStartedEvent>, I>>(_: I): AgentResponseStartedEvent;
};
export declare const AgentResponseCompletedEvent: {
    encode(_: AgentResponseCompletedEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): AgentResponseCompletedEvent;
    fromJSON(_: any): AgentResponseCompletedEvent;
    toJSON(_: AgentResponseCompletedEvent): unknown;
    create<I extends Exact<DeepPartial<AgentResponseCompletedEvent>, I>>(base?: I): AgentResponseCompletedEvent;
    fromPartial<I extends Exact<DeepPartial<AgentResponseCompletedEvent>, I>>(_: I): AgentResponseCompletedEvent;
};
export declare const SpeechTurnDetectionEvent: {
    encode(message: SpeechTurnDetectionEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): SpeechTurnDetectionEvent;
    fromJSON(object: any): SpeechTurnDetectionEvent;
    toJSON(message: SpeechTurnDetectionEvent): unknown;
    create<I extends Exact<DeepPartial<SpeechTurnDetectionEvent>, I>>(base?: I): SpeechTurnDetectionEvent;
    fromPartial<I extends Exact<DeepPartial<SpeechTurnDetectionEvent>, I>>(object: I): SpeechTurnDetectionEvent;
};
export declare const TurnLifecycleEvent: {
    encode(message: TurnLifecycleEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TurnLifecycleEvent;
    fromJSON(object: any): TurnLifecycleEvent;
    toJSON(message: TurnLifecycleEvent): unknown;
    create<I extends Exact<DeepPartial<TurnLifecycleEvent>, I>>(base?: I): TurnLifecycleEvent;
    fromPartial<I extends Exact<DeepPartial<TurnLifecycleEvent>, I>>(object: I): TurnLifecycleEvent;
};
export declare const WakeWordDetectedEvent: {
    encode(message: WakeWordDetectedEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): WakeWordDetectedEvent;
    fromJSON(object: any): WakeWordDetectedEvent;
    toJSON(message: WakeWordDetectedEvent): unknown;
    create<I extends Exact<DeepPartial<WakeWordDetectedEvent>, I>>(base?: I): WakeWordDetectedEvent;
    fromPartial<I extends Exact<DeepPartial<WakeWordDetectedEvent>, I>>(object: I): WakeWordDetectedEvent;
};
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
export {};
//# sourceMappingURL=voice_events.d.ts.map