import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
export declare enum HybridBackendKind {
    HYBRID_BACKEND_UNSPECIFIED = 0,
    HYBRID_BACKEND_LLAMACPP = 1,
    HYBRID_BACKEND_OPENROUTER = 2,
    HYBRID_BACKEND_SHERPA = 3,
    HYBRID_BACKEND_CLOUD = 4,
    UNRECOGNIZED = -1
}
export declare function hybridBackendKindFromJSON(object: any): HybridBackendKind;
export declare function hybridBackendKindToJSON(object: HybridBackendKind): string;
/** A candidate must pass every hard filter to stay in the running. */
export interface HybridFilter {
    network?: boolean | undefined;
    /** Documented as a no-op in the Dart policy. */
    qualityTier?: number | undefined;
    battery?: BatteryFilter | undefined;
    custom?: CustomFilter | undefined;
}
export interface BatteryFilter {
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
export interface HybridRoutingPolicy {
    hardFilters: HybridFilter[];
    cascade?: HybridCascade | undefined;
    preferLocal: boolean;
}
export interface HybridModelDescriptor {
    modelId: string;
    isLocal: boolean;
    backend: HybridBackendKind;
    provider: string;
}
/** What the router actually did, including the failed primary attempt. */
export interface HybridRoutedMetadata {
    chosenModelId: string;
    wasFallback: boolean;
    attemptCount: number;
    primaryErrorCode: number;
    primaryErrorMessage: string;
    confidence: number;
    primaryConfidence: number;
}
/**
 * Device state lives behind the rac_hybrid_device_state vtable in commons, so
 * callers never serialize platform state into this message.
 */
export interface HybridRoutingContext {
}
export interface CloudSttBackendConfig {
    provider: string;
    model: string;
    apiKey: string;
    languageCode: string;
    baseUrl: string;
    timeoutMs: number;
}
export interface HybridSttTranscribeOptions {
    language: string;
    sampleRate: number;
    /** Untyped: every other file uses the AudioFormat enum here. */
    audioFormat: number;
}
export interface HybridSttTranscribeRequest {
    audioBytes: Uint8Array;
    context?: HybridRoutingContext | undefined;
    options?: HybridSttTranscribeOptions | undefined;
}
export interface HybridSttTranscribeResponse {
    rc: number;
    text: string;
    detectedLanguage: string;
    routing?: HybridRoutedMetadata | undefined;
    errorMsg: string;
}
export declare const HybridFilter: MessageFns<HybridFilter>;
export declare const BatteryFilter: MessageFns<BatteryFilter>;
export declare const CustomFilter: MessageFns<CustomFilter>;
export declare const HybridCascade: MessageFns<HybridCascade>;
export declare const ConfidenceCascade: MessageFns<ConfidenceCascade>;
export declare const HybridRoutingPolicy: MessageFns<HybridRoutingPolicy>;
export declare const HybridModelDescriptor: MessageFns<HybridModelDescriptor>;
export declare const HybridRoutedMetadata: MessageFns<HybridRoutedMetadata>;
export declare const HybridRoutingContext: MessageFns<HybridRoutingContext>;
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
