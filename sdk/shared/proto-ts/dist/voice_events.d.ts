import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { ComponentLifecycleState, EventCategory } from "./component_types";
import { ErrorCode, ErrorSeverity, SDKError } from "./errors";
import { AudioEncoding } from "./model_types";
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
     * Wall-clock timestamp captured at the C++ edge, in milliseconds since
     * Unix epoch. Frontends may re-timestamp for UI display.
     */
    timestampMs: number;
    category: EventCategory;
    severity: ErrorSeverity;
    component: VoicePipelineComponent;
    userSaid?: UserSaidEvent | undefined;
    assistantToken?: AssistantTokenEvent | undefined;
    audio?: AudioFrameEvent | undefined;
    vad?: VADEvent | undefined;
    interrupted?: InterruptedEvent | undefined;
    state?: StateChangeEvent | undefined;
    metrics?: MetricsEvent | undefined;
    componentStateChanged?: VoiceAgentComponentStates | undefined;
    /** The one error payload in this domain. */
    sessionError?: VoiceSessionError | undefined;
    /**
     * Agent-response start/complete and user-speech start/end are
     * TurnLifecycleEventKind values, not separate arms. Session start and
     * stop are PipelineState transitions on StateChangeEvent.
     */
    turnLifecycle?: TurnLifecycleEvent | undefined;
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
    /**
     * Milliseconds from the start of ALL audio fed this session, matching
     * OpenAI input_audio_buffer.speech_started.audio_start_ms.
     */
    audioStartMs: number;
    audioEndMs: number;
    /**
     * Detected language, BCP-47. One spelling across this domain and
     * stt_options.proto.
     */
    language: string;
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
    /** Position of the analyzed frame on the session timeline, in ms. */
    frameOffsetMs: number;
    /** Same scale and caveats as VADResult.probability. */
    probability: number;
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
    vadFirstSpeechMs: number;
    sttFirstPartialMs: number;
    llmTotalMs: number;
    ttsTotalMs: number;
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
    error?: SDKError | undefined;
}
export interface VoiceSessionError {
    code: ErrorCode;
    message: string;
    failedComponent?: string | undefined;
    /**
     * The raw ra_status_t (core/abi/ra_primitives.h), preserved for
     * diagnostics alongside the canonical `code`.
     */
    cAbiCode: number;
    recoverable: boolean;
    /** The operation that failed, e.g. "transcribe", "generate", "synthesize". */
    operation?: string | undefined;
}
export interface TurnLifecycleEvent {
    kind: TurnLifecycleEventKind;
    turnId: string;
    sessionId: string;
    transcript: string;
    response: string;
    /** Set on KIND_FAILED. Same payload as VoiceEvent.session_error. */
    error?: VoiceSessionError | undefined;
    startedAtMs: number;
    completedAtMs: number;
}
export declare const VoiceEvent: MessageFns<VoiceEvent>;
export declare const VoiceEvent_MetadataEntry: MessageFns<VoiceEvent_MetadataEntry>;
export declare const UserSaidEvent: MessageFns<UserSaidEvent>;
export declare const AssistantTokenEvent: MessageFns<AssistantTokenEvent>;
export declare const AudioFrameEvent: MessageFns<AudioFrameEvent>;
export declare const VADEvent: MessageFns<VADEvent>;
export declare const InterruptedEvent: MessageFns<InterruptedEvent>;
export declare const StateChangeEvent: MessageFns<StateChangeEvent>;
export declare const MetricsEvent: MessageFns<MetricsEvent>;
export declare const VoiceAgentComponentStates: MessageFns<VoiceAgentComponentStates>;
export declare const VoiceSessionError: MessageFns<VoiceSessionError>;
export declare const TurnLifecycleEvent: MessageFns<TurnLifecycleEvent>;
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
