import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
import { AudioEncoding, AudioFormat, InferenceFramework } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
export declare enum STTStreamEventKind {
    STT_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    STT_STREAM_EVENT_KIND_STARTED = 1,
    STT_STREAM_EVENT_KIND_PARTIAL = 2,
    STT_STREAM_EVENT_KIND_FINAL = 3,
    STT_STREAM_EVENT_KIND_ENDPOINT = 4,
    STT_STREAM_EVENT_KIND_ERROR = 5,
    UNRECOGNIZED = -1
}
export declare function sTTStreamEventKindFromJSON(object: any): STTStreamEventKind;
export declare function sTTStreamEventKindToJSON(object: STTStreamEventKind): string;
/**
 * Init-time settings. Per-call knobs live on STTOptions; adapters mirror the
 * transcription defaults below into STTOptions when building a request.
 */
export interface STTConfiguration {
    modelId: string;
    language?: string | undefined;
    sampleRate: number;
    enableVad: boolean;
    audioFormat: AudioFormat;
    enablePunctuation: boolean;
    enableDiarization: boolean;
    vocabularyList: string[];
    /** 0 = backend default */
    maxAlternatives: number;
    enableWordTimestamps: boolean;
    preferredFramework?: InferenceFramework | undefined;
}
/** Per-call overrides. */
export interface STTOptions {
    language?: string | undefined;
    enablePunctuation: boolean;
    enableDiarization: boolean;
    /** 0 = auto */
    maxSpeakers: number;
    vocabularyList: string[];
    enableWordTimestamps: boolean;
    /** 0 = backend default, for all four of these. */
    beamSize: number;
    maxAlternatives: number;
    chunkDurationMs: number;
    endpointSilenceMs: number;
    suppressBlank: boolean;
    translateToEnglish: boolean;
}
export interface STTAudioSource {
    audioData?: Uint8Array | undefined;
    fileUri?: string | undefined;
    adapterHandle?: string | undefined;
    encoding: AudioEncoding;
    audioFormat: AudioFormat;
    sampleRate: number;
    channels: number;
    bitsPerSample: number;
    durationMs: number;
}
export interface STTTranscriptionRequest {
    requestId: string;
    audio?: STTAudioSource | undefined;
    options?: STTOptions | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface STTTranscriptionRequest_MetadataEntry {
    key: string;
    value: string;
}
export interface WordTimestamp {
    word: string;
    startMs: number;
    endMs: number;
    confidence: number;
    speakerId?: string | undefined;
}
/** One n-best hypothesis. Per-word breakdown only when the backend emits it. */
export interface TranscriptionAlternative {
    text: string;
    confidence: number;
    words: WordTimestamp[];
}
export interface TranscriptionMetadata {
    modelId: string;
    processingTimeMs: number;
    audioLengthMs: number;
}
export interface STTOutput {
    text: string;
    confidence: number;
    /** Detected language, BCP-47. Empty = unknown. */
    language?: string | undefined;
    words: WordTimestamp[];
    alternatives: TranscriptionAlternative[];
    metadata?: TranscriptionMetadata | undefined;
    /** Milliseconds since epoch. */
    timestampMs: number;
    /** Often duplicates metadata.audio_length_ms. */
    durationMs: number;
    speakerIds: string[];
    /** For long-running or streaming transcription. */
    segmentIndex: number;
    error?: SDKError | undefined;
}
export interface STTPartialResult {
    text: string;
    isFinal: boolean;
    /** Whisper-style hypothesis stability, 0.0-1.0. 0.0 when unsupported. */
    stability: number;
    confidence: number;
    language?: string | undefined;
    timestampMs: number;
    alternatives: TranscriptionAlternative[];
    requestId: string;
    segmentIndex: number;
    audioStartMs: number;
    audioEndMs: number;
    finalOutput?: STTOutput | undefined;
}
export interface STTStreamEvent {
    seq: number;
    timestampUs: number;
    requestId: string;
    kind: STTStreamEventKind;
    partial?: STTPartialResult | undefined;
    finalOutput?: STTOutput | undefined;
    error?: SDKError | undefined;
}
export interface STTServiceState {
    isReady: boolean;
    currentModel?: string | undefined;
    supportsStreaming: boolean;
    supportedLanguageCodes: string[];
    error?: SDKError | undefined;
}
export declare const STTConfiguration: MessageFns<STTConfiguration>;
export declare const STTOptions: MessageFns<STTOptions>;
export declare const STTAudioSource: MessageFns<STTAudioSource>;
export declare const STTTranscriptionRequest: MessageFns<STTTranscriptionRequest>;
export declare const STTTranscriptionRequest_MetadataEntry: MessageFns<STTTranscriptionRequest_MetadataEntry>;
export declare const WordTimestamp: MessageFns<WordTimestamp>;
export declare const TranscriptionAlternative: MessageFns<TranscriptionAlternative>;
export declare const TranscriptionMetadata: MessageFns<TranscriptionMetadata>;
export declare const STTOutput: MessageFns<STTOutput>;
export declare const STTPartialResult: MessageFns<STTPartialResult>;
export declare const STTStreamEvent: MessageFns<STTStreamEvent>;
export declare const STTServiceState: MessageFns<STTServiceState>;
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
