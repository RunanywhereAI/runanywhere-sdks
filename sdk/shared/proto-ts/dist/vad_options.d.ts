import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
import { AudioEncoding, InferenceFramework } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
export declare enum SpeechActivityKind {
    SPEECH_ACTIVITY_KIND_UNSPECIFIED = 0,
    SPEECH_ACTIVITY_KIND_SPEECH_STARTED = 1,
    SPEECH_ACTIVITY_KIND_SPEECH_ENDED = 2,
    SPEECH_ACTIVITY_KIND_ONGOING = 3,
    UNRECOGNIZED = -1
}
export declare function speechActivityKindFromJSON(object: any): SpeechActivityKind;
export declare function speechActivityKindToJSON(object: SpeechActivityKind): string;
/**
 * Every value here is emitted by commons. Barge-in is a session-level
 * decision, not a detector verdict: it lives on InterruptedEvent /
 * InterruptReason in voice_events.proto.
 */
export declare enum VADStreamEventKind {
    VAD_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    VAD_STREAM_EVENT_KIND_FRAME = 1,
    VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY = 2,
    VAD_STREAM_EVENT_KIND_ERROR = 3,
    UNRECOGNIZED = -1
}
export declare function vADStreamEventKindFromJSON(object: any): VADStreamEventKind;
export declare function vADStreamEventKindToJSON(object: VADStreamEventKind): string;
/** Load-time configuration for a VAD instance. */
export interface VADConfiguration {
    /** Empty when using the built-in energy VAD. */
    modelId: string;
    sampleRate: number;
    /**
     * Milliseconds, on the wire AND in every generated binding. Only the
     * internal rac_vad_config_t holds seconds; commons converts there.
     */
    frameLengthMs: number;
    /**
     * Normalized activation sensitivity in [0,1]; higher = harder to trigger.
     * 0.5 is the industry default (OpenAI turn_detection.threshold, Silero,
     * LiveKit activation_threshold). Each backend maps it onto its own units:
     * a probability model uses it 1:1, the built-in energy detector converts
     * it to an RMS bar. That conversion is backend-owned and is NOT fixed
     * here; the built-in energy path and the voice-agent path calibrate
     * separately today.
     */
    activationThreshold: number;
    /**
     * Calibrate against ambient noise and scale the threshold by
     * calibration_multiplier.
     */
    enableAutoCalibration: boolean;
    /** threshold = ambient noise * multiplier */
    calibrationMultiplier: number;
    preferredFramework?: InferenceFramework | undefined;
    /** For backend-specific VADs such as Silero ONNX. */
    modelPath?: string | undefined;
}
/** Per-call options. Field vocabulary follows LiveKit/Silero naming. */
export interface VADOptions {
    /**
     * Unset = keep the loaded detector's calibrated value. Same normalized
     * [0,1] scale as VADConfiguration.activation_threshold.
     */
    activationThreshold?: number | undefined;
    /** Debounce: speech shorter than this is discarded (coughs, clicks, taps). */
    minSpeechDurationMs: number;
    /**
     * Hangover: continuous silence this long ends the turn. This is the
     * primary latency dial. Defaulted for TURN-TAKING (OpenAI
     * silence_duration_ms = 500), not for ASR segmentation (Silero = 100).
     */
    minSilenceDurationMs: number;
    /** Force-split a monologue longer than this. Unset = unbounded. */
    maxSpeechDurationMs?: number | undefined;
    /**
     * Pre-roll kept before SPEECH_STARTED so the first phoneme survives.
     * Included in the emitted segment's audio_start_ms (OpenAI semantics).
     */
    prefixPaddingMs: number;
    /**
     * Capture rate of the audio fed to the detector, for the whole session.
     * Nothing resamples: a mismatch yields wrong segment durations. Bound is
     * identical to VADConfiguration.sample_rate and the commons validator —
     * if the project narrows to Silero/LiveKit's {8000,16000}, change all
     * three together.
     */
    sampleRate: number;
}
export interface VADAudioSource {
    audioData: Uint8Array;
    encoding: AudioEncoding;
    sampleRate: number;
    /**
     * Kept: commons rejects channels > 1 with RAC_ERROR_NOT_SUPPORTED, and
     * this is the only signal that a caller pushed interleaved stereo.
     */
    channels: number;
    /**
     * Position of this chunk on the session timeline; feeds
     * SpeechActivityEvent.audio_start_ms / audio_end_ms.
     */
    frameOffsetMs: number;
}
export interface VADProcessRequest {
    audio?: VADAudioSource | undefined;
    options?: VADOptions | undefined;
}
export interface VADResult {
    isSpeech: boolean;
    /**
     * [0.0, 1.0], backend- AND path-dependent. On the one-shot detect path the
     * built-in energy VAD reports min(1.0, energy/threshold), which saturates
     * at 1.0; on the streaming per-frame path it is binary 0.0/1.0. A model
     * backend reports its own speech probability. Not comparable across
     * backends — do not re-threshold on it.
     */
    probability: number;
    /** RMS energy of the analyzed frame. */
    energy: number;
    /** Length of the analyzed frame. */
    durationMs: number;
    /** Milliseconds since epoch. */
    timestampMs: number;
    error?: SDKError | undefined;
}
/** Exposed for debugging and waveform UIs. */
export interface VADStatistics {
    currentEnergy: number;
    currentThreshold: number;
    /** Ambient noise level captured by calibration. */
    ambientLevel: number;
    /** Moving-window average and peak. */
    recentAvg: number;
    recentMax: number;
    /** Zero = unset for energy-only implementations. */
    totalSpeechSegments: number;
    totalSpeechDurationMs: number;
    averageEnergy: number;
    peakEnergy: number;
}
/**
 * Narrow component-level transition: this detector said speech started or
 * ended. Barge-in is a session-level decision, not a detector verdict — it is
 * reported by InterruptedEvent / InterruptReason in voice_events.proto.
 */
export interface SpeechActivityEvent {
    eventType: SpeechActivityKind;
    /** Milliseconds since epoch. */
    timestampMs: number;
    /**
     * Ms from the start of session audio when speech began. Set on both
     * STARTED and ENDED. Includes prefix_padding_ms (OpenAI audio_start_ms).
     */
    audioStartMs: number;
    /**
     * Ms from the start of session audio when speech ended; 0 on STARTED.
     * Includes min_silence_duration_ms (OpenAI audio_end_ms).
     */
    audioEndMs: number;
    /** Correlates STARTED with its ENDED (OpenAI item_id). */
    segmentId?: string | undefined;
}
export interface VADStreamEvent {
    seq: number;
    /**
     * Microseconds since epoch. Genuine sub-millisecond precision: the
     * streaming dispatcher stamps this from a microsecond clock.
     */
    timestampUs: number;
    requestId: string;
    kind: VADStreamEventKind;
    result?: VADResult | undefined;
    activity?: SpeechActivityEvent | undefined;
    error?: SDKError | undefined;
}
export interface VADServiceState {
    isReady: boolean;
    isSpeechActive: boolean;
    /**
     * The threshold actually in force. After auto-calibration this differs
     * from what was requested, which is why it is worth reading back.
     */
    activationThreshold: number;
    sampleRate: number;
    frameLengthMs: number;
    currentModel?: string | undefined;
    error?: SDKError | undefined;
}
export declare const VADConfiguration: MessageFns<VADConfiguration>;
export declare const VADOptions: MessageFns<VADOptions>;
export declare const VADAudioSource: MessageFns<VADAudioSource>;
export declare const VADProcessRequest: MessageFns<VADProcessRequest>;
export declare const VADResult: MessageFns<VADResult>;
export declare const VADStatistics: MessageFns<VADStatistics>;
export declare const SpeechActivityEvent: MessageFns<SpeechActivityEvent>;
export declare const VADStreamEvent: MessageFns<VADStreamEvent>;
export declare const VADServiceState: MessageFns<VADServiceState>;
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
