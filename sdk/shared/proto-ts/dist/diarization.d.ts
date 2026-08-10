import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
import { AudioEncoding } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
export declare enum DiarizationStreamEventKind {
    DIARIZATION_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    DIARIZATION_STREAM_EVENT_KIND_STARTED = 1,
    DIARIZATION_STREAM_EVENT_KIND_UPDATE = 2,
    DIARIZATION_STREAM_EVENT_KIND_FINAL = 3,
    DIARIZATION_STREAM_EVENT_KIND_ERROR = 4,
    UNRECOGNIZED = -1
}
export declare function diarizationStreamEventKindFromJSON(object: any): DiarizationStreamEventKind;
export declare function diarizationStreamEventKindToJSON(object: DiarizationStreamEventKind): string;
export interface DiarizationOptions {
    /**
     * Only 16 kHz is accepted: the engine does not resample, and any other
     * rate fails with RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED.
     */
    sampleRate?: number | undefined;
    channels?: number | undefined;
    /**
     * Byte layout of audio_data. ONLY AUDIO_ENCODING_PCM_F32_LE and
     * AUDIO_ENCODING_PCM_S16_LE are accepted; commons normalizes either to
     * float samples before dispatching to an engine. AUDIO_ENCODING_CONTAINER
     * and AUDIO_ENCODING_UNSPECIFIED are rejected with
     * RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED — strip container headers first.
     */
    encoding?: AudioEncoding | undefined;
    threshold?: number | undefined;
    minimumDurationMs: number;
    mergeGapMs: number;
    /**
     * Speaker-count hint: an upper bound, not an exact count. Unset =
     * auto-detect. An engine that detects more than max_speakers speakers
     * ranks them by total active duration, drops the weakest, and re-densifies
     * the speaker indices. Values above the loaded model's speaker capacity
     * are clamped.
     */
    maxSpeakers?: number | undefined;
}
export interface DiarizationRequest {
    audioData: Uint8Array;
    options?: DiarizationOptions | undefined;
}
export interface DiarizationSegment {
    startMs: number;
    endMs: number;
    speakerIndex: number;
    speakerId: string;
}
export interface DiarizationResult {
    segments: DiarizationSegment[];
    speakerCount: number;
    audioDurationMs: number;
    processingTimeMs: number;
    modelId: string;
}
/**
 * UPDATE and FINAL carry a complete snapshot of the session hypothesis, not a
 * delta. Speaker indices/IDs are stable only within one offline call or stream
 * session. Segments belonging to different speakers may overlap.
 */
export interface DiarizationStreamEvent {
    sessionId: number;
    seq: number;
    timestampUs: number;
    kind: DiarizationStreamEventKind;
    result?: DiarizationResult | undefined;
    error?: SDKError | undefined;
}
export declare const DiarizationOptions: MessageFns<DiarizationOptions>;
export declare const DiarizationRequest: MessageFns<DiarizationRequest>;
export declare const DiarizationSegment: MessageFns<DiarizationSegment>;
export declare const DiarizationResult: MessageFns<DiarizationResult>;
export declare const DiarizationStreamEvent: MessageFns<DiarizationStreamEvent>;
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
