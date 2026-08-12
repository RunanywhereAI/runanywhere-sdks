import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { AudioFormat } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Firebase AI Logic / developer.android.com InferenceMode, verbatim.
 * PREFER_* falls back silently across the boundary; ONLY_* fails instead.
 */
export declare enum HybridInferenceMode {
    /** HYBRID_INFERENCE_MODE_UNSPECIFIED - Treated as PREFER_ON_DEVICE, so the proto3 zero is the private default. */
    HYBRID_INFERENCE_MODE_UNSPECIFIED = 0,
    HYBRID_INFERENCE_MODE_PREFER_ON_DEVICE = 1,
    HYBRID_INFERENCE_MODE_ONLY_ON_DEVICE = 2,
    HYBRID_INFERENCE_MODE_PREFER_IN_CLOUD = 3,
    HYBRID_INFERENCE_MODE_ONLY_IN_CLOUD = 4,
    UNRECOGNIZED = -1
}
export declare function hybridInferenceModeFromJSON(object: any): HybridInferenceMode;
export declare function hybridInferenceModeToJSON(object: HybridInferenceMode): string;
/** A candidate must pass every hard filter to stay in the running. */
export interface HybridFilter {
    network?: boolean | undefined;
    battery?: BatteryFilter | undefined;
    custom?: CustomFilter | undefined;
}
export interface BatteryFilter {
    /** Charge floor, 0-100, below which the on-device candidate is dropped. */
    minBatteryPercent: number;
}
export interface CustomFilter {
    name: string;
    description: string;
}
export interface HybridCascade {
    confidence?: ConfidenceCascade | undefined;
}
/** Below this on-device confidence, the router escalates to cloud. */
export interface ConfidenceCascade {
    threshold: number;
}
/**
 * The candidate chain for one routed request: tried first to last, first
 * success wins, position IS the priority. `mode` still governs whether the
 * chain may cross the on-device/cloud line.
 */
export interface HybridRoutingPolicy {
    hardFilters: HybridFilter[];
    cascade?: HybridCascade | undefined;
    mode: HybridInferenceMode;
    /**
     * Per-ATTEMPT deadline, not the overall request deadline. When a candidate
     * has produced nothing within this many milliseconds it is abandoned and
     * the next candidate is tried. 0 = no per-attempt deadline.
     */
    attemptTimeoutMs: number;
    /** Ordered candidates, priority first. Replaces the offline/online pair. */
    models: HybridModelDescriptor[];
}
export interface HybridModelDescriptor {
    modelId: string;
    /**
     * True = this candidate runs ON DEVICE (and is exempt from the network and
     * battery filters). False = it runs IN CLOUD. Firebase/Android vocabulary.
     */
    isOnDevice: boolean;
    /**
     * The plugin-registry engine name the runtime already pins on: "sherpa",
     * "llamacpp", "onnx", "qhexrt", "mlx", "cloud", or any name passed to
     * registerCloudProvider(). Empty = let the registry pick by priority.
     */
    engine: string;
}
/** What the router actually did, including the failed primary attempt. */
export interface HybridRoutedMetadata {
    chosenModelId: string;
    wasFallback: boolean;
    attemptCount: number;
    primaryErrorCode: number;
    primaryErrorMessage: string;
    /** Absent (not NaN, not 0.0) when the engine reports no quality score. */
    confidence?: number | undefined;
    /** Absent unless a confidence cascade discarded a primary answer. */
    primaryConfidence?: number | undefined;
    /**
     * True when the answer was produced ON DEVICE. This is the field an app
     * reads to truthfully claim "processed on your device"; never infer it by
     * comparing chosen_model_id.
     */
    servedOnDevice: boolean;
}
export interface CloudSttBackendConfig {
    provider: string;
    model: string;
    /**
     * SECRET. Held in memory only; never logged, never persisted, never
     * included in a toString()/toJSON() dump.
     */
    apiKey: string;
    languageCode: string;
    baseUrl: string;
    timeoutMs: number;
}
export interface HybridSttTranscribeOptions {
    language: string;
    sampleRate: number;
    /**
     * Container the bytes are already in. UNSPECIFIED (the proto3 zero) means
     * headerless PCM16, which commons wraps in a WAV container.
     */
    audioFormat: AudioFormat;
}
export interface HybridSttTranscribeRequest {
    audioBytes: Uint8Array;
    options?: HybridSttTranscribeOptions | undefined;
}
export interface HybridSttTranscribeResponse {
    rc: number;
    text: string;
    detectedLanguage: string;
    routing?: HybridRoutedMetadata | undefined;
}
export declare const HybridFilter: MessageFns<HybridFilter>;
export declare const BatteryFilter: MessageFns<BatteryFilter>;
export declare const CustomFilter: MessageFns<CustomFilter>;
export declare const HybridCascade: MessageFns<HybridCascade>;
export declare const ConfidenceCascade: MessageFns<ConfidenceCascade>;
export declare const HybridRoutingPolicy: MessageFns<HybridRoutingPolicy>;
export declare const HybridModelDescriptor: MessageFns<HybridModelDescriptor>;
export declare const HybridRoutedMetadata: MessageFns<HybridRoutedMetadata>;
export declare const CloudSttBackendConfig: MessageFns<CloudSttBackendConfig>;
export declare const HybridSttTranscribeOptions: MessageFns<HybridSttTranscribeOptions>;
export declare const HybridSttTranscribeRequest: MessageFns<HybridSttTranscribeRequest>;
export declare const HybridSttTranscribeResponse: MessageFns<HybridSttTranscribeResponse>;
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
