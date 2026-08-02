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
export declare enum VADStreamEventKind {
    VAD_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    VAD_STREAM_EVENT_KIND_STARTED = 1,
    VAD_STREAM_EVENT_KIND_FRAME = 2,
    VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY = 3,
    VAD_STREAM_EVENT_KIND_STATISTICS = 4,
    VAD_STREAM_EVENT_KIND_STOPPED = 5,
    VAD_STREAM_EVENT_KIND_ERROR = 6,
    /**
     * VAD_STREAM_EVENT_KIND_BARGE_IN - Speech that interrupts active assistant playback. Downstream pipeline
     * also routes this through InterruptedEvent/InterruptReason.
     */
    VAD_STREAM_EVENT_KIND_BARGE_IN = 7,
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
     * Milliseconds on the wire; Swift/Kotlin/Dart/C hold seconds, so generated
     * bindings divide by 1000 when they bind to those types.
     */
    frameLengthMs: number;
    /** Commons rejects values outside [0, 1] and warns below 0.002 or above 0.1. */
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
    /** 0 = backend default, for both of these. */
    windowSizeSamples: number;
    maxSpeechDurationMs: number;
}
/** Per-call options. Field vocabulary follows LiveKit/Silero naming. */
export interface VADOptions {
    /** 0 = keep the configured threshold. */
    activationThreshold: number;
    minSpeechDurationMs: number;
    minSilenceDurationMs: number;
    /** 0 = backend default, for both of these. */
    maxSpeechDurationMs: number;
    /**
     * Audio retained before SPEECH_STARTED so segments don't clip the first
     * syllable.
     */
    prefixPaddingMs: number;
    includeStatistics: boolean;
}
export interface VADAudioSource {
    audioData?: Uint8Array | undefined;
    adapterHandle?: string | undefined;
    encoding: AudioEncoding;
    sampleRate: number;
    channels: number;
    frameOffsetMs: number;
}
export interface VADProcessRequest {
    requestId: string;
    audio?: VADAudioSource | undefined;
    options?: VADOptions | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface VADProcessRequest_MetadataEntry {
    key: string;
    value: string;
}
export interface VADResult {
    isSpeech: boolean;
    /** [0.0, 1.0], backend-dependent. */
    confidence: number;
    /** RMS energy of the analyzed frame. */
    energy: number;
    /** Length of the analyzed frame. */
    durationMs: number;
    /** Milliseconds since epoch. */
    timestampMs: number;
    /** 0 = unset. */
    startTimeMs: number;
    endTimeMs: number;
    statistics?: VADStatistics | undefined;
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
 * Narrow component-level transition. voice_events.proto's VADEvent carries the
 * broader pipeline taxonomy (BARGE_IN, END_OF_UTTERANCE) via VADStreamEventKind.
 */
export interface SpeechActivityEvent {
    eventType: SpeechActivityKind;
    /** Milliseconds since epoch. */
    timestampMs: number;
    /**
     * Length of the just-finished utterance on SPEECH_ENDED; zero on
     * SPEECH_STARTED.
     */
    durationMs: number;
    confidence: number;
    result?: VADResult | undefined;
    segmentId?: string | undefined;
}
export interface VADStreamEvent {
    seq: number;
    timestampUs: number;
    requestId: string;
    kind: VADStreamEventKind;
    result?: VADResult | undefined;
    activity?: SpeechActivityEvent | undefined;
    statistics?: VADStatistics | undefined;
    error?: SDKError | undefined;
}
export interface VADServiceState {
    isReady: boolean;
    isSpeechActive: boolean;
    energyThreshold: number;
    sampleRate: number;
    frameLengthMs: number;
    currentModel?: string | undefined;
    error?: SDKError | undefined;
}
export declare const VADConfiguration: MessageFns<VADConfiguration>;
export declare const VADOptions: MessageFns<VADOptions>;
export declare const VADAudioSource: MessageFns<VADAudioSource>;
export declare const VADProcessRequest: MessageFns<VADProcessRequest>;
export declare const VADProcessRequest_MetadataEntry: MessageFns<VADProcessRequest_MetadataEntry>;
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
