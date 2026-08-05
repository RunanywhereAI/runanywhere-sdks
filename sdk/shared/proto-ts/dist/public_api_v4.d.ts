import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
import { AudioEncoding, AudioFormat, InferenceFramework, ModelCategory } from "./model_types";
import { TokenUsage } from "./token_usage";
import { ToolCall } from "./tool_calling";
export declare const protobufPackage = "runanywhere.v1";
export declare enum AcceleratorPolicy {
    ACCELERATOR_POLICY_UNSPECIFIED = 0,
    ACCELERATOR_POLICY_AUTO = 1,
    ACCELERATOR_POLICY_CPU = 2,
    ACCELERATOR_POLICY_GPU = 3,
    ACCELERATOR_POLICY_NPU = 4,
    UNRECOGNIZED = -1
}
export declare function acceleratorPolicyFromJSON(object: any): AcceleratorPolicy;
export declare function acceleratorPolicyToJSON(object: AcceleratorPolicy): string;
export declare enum StructuredEnforcementMode {
    STRUCTURED_ENFORCEMENT_MODE_UNSPECIFIED = 0,
    /** STRUCTURED_ENFORCEMENT_MODE_CONSTRAINED - engine-constrained decoding */
    STRUCTURED_ENFORCEMENT_MODE_CONSTRAINED = 1,
    /** STRUCTURED_ENFORCEMENT_MODE_VALIDATION_ONLY - generate then validate */
    STRUCTURED_ENFORCEMENT_MODE_VALIDATION_ONLY = 2,
    /** STRUCTURED_ENFORCEMENT_MODE_REPAIR - validate + repair retries */
    STRUCTURED_ENFORCEMENT_MODE_REPAIR = 3,
    UNRECOGNIZED = -1
}
export declare function structuredEnforcementModeFromJSON(object: any): StructuredEnforcementMode;
export declare function structuredEnforcementModeToJSON(object: StructuredEnforcementMode): string;
export declare enum PublicGenerationEventKind {
    PUBLIC_GENERATION_EVENT_KIND_UNSPECIFIED = 0,
    PUBLIC_GENERATION_EVENT_KIND_STARTED = 1,
    PUBLIC_GENERATION_EVENT_KIND_OUTPUT_ITEM_ADDED = 2,
    PUBLIC_GENERATION_EVENT_KIND_TEXT_DELTA = 3,
    PUBLIC_GENERATION_EVENT_KIND_REASONING_DELTA = 4,
    PUBLIC_GENERATION_EVENT_KIND_TOOL_CALL_ADDED = 5,
    PUBLIC_GENERATION_EVENT_KIND_TOOL_ARGUMENTS_DELTA = 6,
    PUBLIC_GENERATION_EVENT_KIND_TOOL_ARGUMENTS_DONE = 7,
    PUBLIC_GENERATION_EVENT_KIND_USAGE = 8,
    PUBLIC_GENERATION_EVENT_KIND_COMPLETED = 9,
    PUBLIC_GENERATION_EVENT_KIND_FAILED = 10,
    PUBLIC_GENERATION_EVENT_KIND_CANCELLED = 11,
    UNRECOGNIZED = -1
}
export declare function publicGenerationEventKindFromJSON(object: any): PublicGenerationEventKind;
export declare function publicGenerationEventKindToJSON(object: PublicGenerationEventKind): string;
export declare enum PublicDownloadEventKind {
    PUBLIC_DOWNLOAD_EVENT_KIND_UNSPECIFIED = 0,
    PUBLIC_DOWNLOAD_EVENT_KIND_STARTED = 1,
    PUBLIC_DOWNLOAD_EVENT_KIND_PROGRESS = 2,
    PUBLIC_DOWNLOAD_EVENT_KIND_VERIFYING = 3,
    PUBLIC_DOWNLOAD_EVENT_KIND_EXTRACTING = 4,
    PUBLIC_DOWNLOAD_EVENT_KIND_COMPLETED = 5,
    PUBLIC_DOWNLOAD_EVENT_KIND_FAILED = 6,
    PUBLIC_DOWNLOAD_EVENT_KIND_CANCELLED = 7,
    UNRECOGNIZED = -1
}
export declare function publicDownloadEventKindFromJSON(object: any): PublicDownloadEventKind;
export declare function publicDownloadEventKindToJSON(object: PublicDownloadEventKind): string;
export declare enum PublicTranscriptionEventKind {
    PUBLIC_TRANSCRIPTION_EVENT_KIND_UNSPECIFIED = 0,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_STARTED = 1,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_SPEECH_STARTED = 2,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_PARTIAL = 3,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_TRANSCRIPT_FINAL = 4,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_SPEECH_ENDED = 5,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_USAGE = 6,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_COMPLETED = 7,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_FAILED = 8,
    PUBLIC_TRANSCRIPTION_EVENT_KIND_CANCELLED = 9,
    UNRECOGNIZED = -1
}
export declare function publicTranscriptionEventKindFromJSON(object: any): PublicTranscriptionEventKind;
export declare function publicTranscriptionEventKindToJSON(object: PublicTranscriptionEventKind): string;
export interface BackendPreference {
    backend: InferenceFramework;
    required: boolean;
}
export interface DevicePlacement {
    deviceId: string;
    deviceName: string;
    /** cpu | gpu | npu | metal | webgpu | unknown */
    deviceKind: string;
}
/** Resident ownership handle returned by models.load. */
export interface LoadedModelInfo {
    modelId: string;
    category: ModelCategory;
    requestedBackend?: InferenceFramework | undefined;
    actualBackend: InferenceFramework;
    actualDevice?: DevicePlacement | undefined;
    runtimeVersion?: string | undefined;
    abiVersion?: string | undefined;
    fallbackReason?: string | undefined;
    resolvedPath: string;
    loadedAtUnixMs: number;
    alreadyLoaded: boolean;
    warnings: string[];
    error?: SDKError | undefined;
}
export interface AudioFormatSpec {
    encoding: AudioEncoding;
    sampleRate: number;
    channels: number;
    /** when encoding = CONTAINER */
    container?: AudioFormat | undefined;
}
export interface AudioFrame {
    samples: Uint8Array;
    sampleCount: number;
    timestampMs?: number | undefined;
}
export interface AudioStreamOpenRequest {
    requestId: string;
    format?: AudioFormatSpec | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface AudioStreamOpenRequest_MetadataEntry {
    key: string;
    value: string;
}
export interface SpeechHandleState {
    id: string;
    interrupted: boolean;
    done: boolean;
    error?: SDKError | undefined;
}
export interface UnavailableCapability {
    name: string;
    reason: string;
}
export interface ToolCapabilities {
    registry: boolean;
    parallel: boolean;
    cancellation: boolean;
}
export interface RagCapabilities {
    multiSession: boolean;
    persistent: boolean;
    documentListing: boolean;
    documentRemoval: boolean;
}
export interface StreamingCapabilities {
    llmTokenStream: boolean;
    sttLiveFrames: boolean;
    ttsAudioChunks: boolean;
    vadLiveFrames: boolean;
    voiceSession: boolean;
}
export interface SDKCapabilities {
    modalities: string[];
    backends: InferenceFramework[];
    audioFormats: AudioFormat[];
    streaming?: StreamingCapabilities | undefined;
    tools?: ToolCapabilities | undefined;
    rag?: RagCapabilities | undefined;
    unavailable: UnavailableCapability[];
    metadata: {
        [key: string]: string;
    };
}
export interface SDKCapabilities_MetadataEntry {
    key: string;
    value: string;
}
export interface PublicGenerationEvent {
    kind: PublicGenerationEventKind;
    requestId: string;
    sequence: number;
    itemId?: string | undefined;
    index?: number | undefined;
    text?: string | undefined;
    toolCall?: ToolCall | undefined;
    argumentsJson?: string | undefined;
    argumentsDelta?: string | undefined;
    usage?: TokenUsage | undefined;
    partialText?: string | undefined;
    /** GenerationResult JSON or structured payload */
    resultJson?: string | undefined;
    error?: SDKError | undefined;
}
export interface PublicDownloadEvent {
    kind: PublicDownloadEventKind;
    operationId: string;
    sequence: number;
    bytesDone: number;
    bytesTotal: number;
    file?: string | undefined;
    percent?: number | undefined;
    modelId?: string | undefined;
    error?: SDKError | undefined;
}
export interface TranscriptAlternative {
    text: string;
    confidence?: number | undefined;
}
export interface PublicTranscriptionEvent {
    kind: PublicTranscriptionEventKind;
    requestId: string;
    sequence: number;
    segmentId?: string | undefined;
    revision?: number | undefined;
    alternatives: TranscriptAlternative[];
    finalText?: string | undefined;
    timestampMs?: number | undefined;
    usage?: TokenUsage | undefined;
    error?: SDKError | undefined;
}
export declare const BackendPreference: MessageFns<BackendPreference>;
export declare const DevicePlacement: MessageFns<DevicePlacement>;
export declare const LoadedModelInfo: MessageFns<LoadedModelInfo>;
export declare const AudioFormatSpec: MessageFns<AudioFormatSpec>;
export declare const AudioFrame: MessageFns<AudioFrame>;
export declare const AudioStreamOpenRequest: MessageFns<AudioStreamOpenRequest>;
export declare const AudioStreamOpenRequest_MetadataEntry: MessageFns<AudioStreamOpenRequest_MetadataEntry>;
export declare const SpeechHandleState: MessageFns<SpeechHandleState>;
export declare const UnavailableCapability: MessageFns<UnavailableCapability>;
export declare const ToolCapabilities: MessageFns<ToolCapabilities>;
export declare const RagCapabilities: MessageFns<RagCapabilities>;
export declare const StreamingCapabilities: MessageFns<StreamingCapabilities>;
export declare const SDKCapabilities: MessageFns<SDKCapabilities>;
export declare const SDKCapabilities_MetadataEntry: MessageFns<SDKCapabilities_MetadataEntry>;
export declare const PublicGenerationEvent: MessageFns<PublicGenerationEvent>;
export declare const PublicDownloadEvent: MessageFns<PublicDownloadEvent>;
export declare const TranscriptAlternative: MessageFns<TranscriptAlternative>;
export declare const PublicTranscriptionEvent: MessageFns<PublicTranscriptionEvent>;
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
