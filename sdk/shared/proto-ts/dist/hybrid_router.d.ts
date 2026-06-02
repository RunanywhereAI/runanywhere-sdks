import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Capability under hybrid routing. Only STT is wired today.
 * ---------------------------------------------------------------------------
 */
export declare enum HybridCapability {
    HYBRID_CAPABILITY_UNSPECIFIED = 0,
    HYBRID_CAPABILITY_LLM = 1,
    HYBRID_CAPABILITY_VLM = 2,
    HYBRID_CAPABILITY_STT = 3,
    HYBRID_CAPABILITY_TTS = 4,
    HYBRID_CAPABILITY_VAD = 5,
    UNRECOGNIZED = -1
}
export declare function hybridCapabilityFromJSON(object: any): HybridCapability;
export declare function hybridCapabilityToJSON(object: HybridCapability): string;
/**
 * ---------------------------------------------------------------------------
 * Backend identity. Matches the engines/ directory entry that registers
 * the service vtable. HYBRID_BACKEND_CLOUD is the generic cloud STT engine
 * ("cloud_stt"); the concrete HTTP provider (e.g. "sarvam") is selected from
 * the descriptor's `provider` field, not from a distinct enum kind.
 * ---------------------------------------------------------------------------
 */
export declare enum HybridBackendKind {
    HYBRID_BACKEND_UNSPECIFIED = 0,
    HYBRID_BACKEND_LLAMACPP = 1,
    HYBRID_BACKEND_OPENROUTER = 2,
    HYBRID_BACKEND_SHERPA = 3,
    /**
     * HYBRID_BACKEND_CLOUD - Renamed from HYBRID_BACKEND_SARVAM (same wire number) — the engine is now
     * the generic "cloud_stt" backend; the provider is carried out-of-band.
     */
    HYBRID_BACKEND_CLOUD = 4,
    UNRECOGNIZED = -1
}
export declare function hybridBackendKindFromJSON(object: any): HybridBackendKind;
export declare function hybridBackendKindToJSON(object: HybridBackendKind): string;
/**
 * ---------------------------------------------------------------------------
 * Whether a model runs on-device or in the cloud. The router decides which
 * of its two registered candidates to invoke based on policy.
 * ---------------------------------------------------------------------------
 */
export declare enum HybridModelType {
    HYBRID_MODEL_TYPE_UNSPECIFIED = 0,
    HYBRID_MODEL_TYPE_OFFLINE = 1,
    HYBRID_MODEL_TYPE_ONLINE = 2,
    UNRECOGNIZED = -1
}
export declare function hybridModelTypeFromJSON(object: any): HybridModelType;
export declare function hybridModelTypeToJSON(object: HybridModelType): string;
/**
 * ---------------------------------------------------------------------------
 * Rank — comparator used to sort eligible candidates. Exactly one rank
 * per policy.
 * ---------------------------------------------------------------------------
 */
export declare enum HybridRank {
    HYBRID_RANK_UNSPECIFIED = 0,
    HYBRID_RANK_PREFER_LOCAL_FIRST = 1,
    HYBRID_RANK_PREFER_ONLINE_FIRST = 2,
    UNRECOGNIZED = -1
}
export declare function hybridRankFromJSON(object: any): HybridRank;
export declare function hybridRankToJSON(object: HybridRank): string;
/**
 * ---------------------------------------------------------------------------
 * Hard filter — drops a candidate from consideration when the predicate
 * fails. Filters compose with AND semantics. The wire kinds match
 * thoughts/file.txt's Routing Conditions list verbatim.
 * ---------------------------------------------------------------------------
 */
export interface HybridFilter {
    /**
     * True iff the host has working network. Disqualifies online
     * candidates when false; offline candidates are unaffected.
     */
    network?: boolean | undefined;
    /**
     * Discrete quality tier required from the candidate. Candidates
     * declaring a lower tier in their descriptor are filtered out.
     */
    qualityTier?: number | undefined;
    /**
     * Disqualifies cloud candidates when the device is below the
     * given battery percent (0–100).
     */
    battery?: BatteryFilter | undefined;
    /**
     * Caller-supplied predicate, evaluated host-side via the
     * registered custom-filter callback table.
     */
    custom?: CustomFilter | undefined;
}
export interface BatteryFilter {
    minBatteryPercent: number;
}
export interface CustomFilter {
    name: string;
    description: string;
}
/**
 * ---------------------------------------------------------------------------
 * Cascade — triggers fallback from the primary candidate to the next
 * candidate mid-request. Matches the file.txt Confidence policy.
 * ---------------------------------------------------------------------------
 */
export interface HybridCascade {
    /**
     * Cascade when the primary's confidence/logprob signal falls below
     * `threshold`, or when the primary returns an error (treated as
     * "no confidence").
     */
    confidence?: ConfidenceCascade | undefined;
}
export interface ConfidenceCascade {
    threshold: number;
}
/**
 * ---------------------------------------------------------------------------
 * Full routing policy attached to a model pair. `simple` mode collapses
 * to a single filter; `advanced` mode allows composition.
 * ---------------------------------------------------------------------------
 */
export interface HybridRoutingPolicy {
    hardFilters: HybridFilter[];
    cascade?: HybridCascade | undefined;
    rank: HybridRank;
}
/**
 * ---------------------------------------------------------------------------
 * Descriptor for a single registered model on one side of the pair.
 * ---------------------------------------------------------------------------
 */
export interface HybridModelDescriptor {
    modelId: string;
    modelType: HybridModelType;
    backend: HybridBackendKind;
    /**
     * Concrete cloud provider when backend == HYBRID_BACKEND_CLOUD (e.g.
     * "sarvam"). The cloud_stt engine reads it from config_json["provider"];
     * empty defaults to "sarvam". Ignored for non-cloud backends.
     */
    provider: string;
}
/**
 * ---------------------------------------------------------------------------
 * Metadata returned alongside the capability result describing what the
 * router did. Always populated even on success.
 * ---------------------------------------------------------------------------
 */
export interface HybridRoutedMetadata {
    chosenModelId: string;
    wasFallback: boolean;
    attemptCount: number;
    /**
     * Why the router fell back to the secondary. Zero (RAC_SUCCESS) when
     * the primary served the request or no fallback occurred.
     */
    primaryErrorCode: number;
    primaryErrorMessage: string;
    /**
     * Final confidence of the result that was actually returned. NaN when
     * the engine does not surface a quality signal (e.g. sherpa-onnx Whisper).
     */
    confidence: number;
    /**
     * Primary's confidence captured BEFORE cascading to the secondary.
     * Populated only when `was_fallback = true` AND the fallback fired on
     * confidence (not on an error). NaN otherwise.
     */
    primaryConfidence: number;
}
/**
 * ---------------------------------------------------------------------------
 * Per-request routing context — caller-supplied hints only.
 *
 * Device-state fields (is_online, battery_percent, thermal_throttled) live
 * behind the rac_hybrid_device_state C ABI vtable in commons (task #22).
 * `input_is_sensitive` (tag 2) was the privacy PII hint; removed entirely
 * alongside the HybridFilter.privacy gate.
 *
 * Reserved tags 1–4 prevent re-use of any old field number.
 * ---------------------------------------------------------------------------
 */
export interface HybridRoutingContext {
}
/**
 * ---------------------------------------------------------------------------
 * STT transcription options carried through the router. Sample rate and
 * audio_format mirror the C `rac_stt_options_t` knobs; `language` is the
 * caller-supplied BCP-47 hint (empty = backend auto-detect).
 * ---------------------------------------------------------------------------
 */
export interface HybridSttTranscribeOptions {
    language: string;
    sampleRate: number;
    /** Matches rac_audio_format_enum_t: 0=PCM, 1=WAV, 2=MP3, 3=OPUS, 4=AAC, 5=FLAC. */
    audioFormat: number;
}
/**
 * ---------------------------------------------------------------------------
 * Request handed to the JNI transcribe thunk. Audio bytes are passed
 * verbatim to the chosen backend; each engine is responsible for parsing
 * the encoded format (the cloud provider, e.g. Sarvam, reads the multipart
 * file part; sherpa decodes the WAV/PCM bytes).
 * ---------------------------------------------------------------------------
 */
export interface HybridSttTranscribeRequest {
    audioBytes: Uint8Array;
    context?: HybridRoutingContext | undefined;
    options?: HybridSttTranscribeOptions | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Response returned by the JNI transcribe thunk. Carries the transcript,
 * the detected (or hinted) language, the routing decision metadata, the
 * native rc, and a human-readable error message when rc != 0.
 * ---------------------------------------------------------------------------
 */
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
