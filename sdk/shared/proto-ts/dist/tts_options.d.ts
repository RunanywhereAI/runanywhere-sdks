import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
import { AudioFormat } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
export declare enum TTSStreamEventKind {
    TTS_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    TTS_STREAM_EVENT_KIND_STARTED = 1,
    TTS_STREAM_EVENT_KIND_AUDIO_CHUNK = 2,
    TTS_STREAM_EVENT_KIND_COMPLETED = 4,
    TTS_STREAM_EVENT_KIND_ERROR = 5,
    UNRECOGNIZED = -1
}
export declare function tTSStreamEventKindFromJSON(object: any): TTSStreamEventKind;
export declare function tTSStreamEventKindToJSON(object: TTSStreamEventKind): string;
export interface TTSOptions {
    /** Empty = use the component's configured voice. */
    voice: string;
    /**
     * Voice/model id to synthesize with. Unset = use whatever is already
     * loaded for MODEL_CATEGORY_SPEECH_SYNTHESIS; set = load it first,
     * downloading if needed.
     */
    model?: string | undefined;
    /** BCP-47. Empty = use the component default. */
    languageCode: string;
    /** Speed multiplier, matching OpenAI /audio/speech `speed`. */
    speed: number;
    /**
     * Fundamental-frequency multiplier, 1.0 = the voice's own pitch. Honoured
     * only by the platform backend (Apple System TTS / Android TextToSpeech);
     * neural voices (sherpa/Piper/Kokoro, qhexrt) ignore it, because for them
     * pitch is voice identity rather than a dial.
     */
    pitch: number;
    /** 0.0 - 1.0. */
    volume: number;
    /**
     * TTS honours exactly AUDIO_FORMAT_PCM (float32) and AUDIO_FORMAT_WAV.
     * Other values, including AUDIO_FORMAT_PCM_S16LE, fall through to PCM
     * silently today; do not rely on them until that is fixed.
     */
    audioFormat: AudioFormat;
    /**
     * 0 (the default) = render at the voice's native rate. Naming any other
     * rate forces a resample and costs quality. TTSOutput.sample_rate always
     * reports the rate actually used.
     */
    sampleRate: number;
}
export interface TTSSynthesisRequest {
    requestId: string;
    text: string;
    options?: TTSOptions | undefined;
}
export interface TTSSynthesisMetadata {
    voiceId: string;
    /** BCP-47. */
    languageCode: string;
    processingTimeMs: number;
    /** UTF-8 byte length of the spoken input, not a codepoint count. */
    inputBytes: number;
}
export interface TTSOutput {
    /** Encoded per audio_format. */
    audioData: Uint8Array;
    audioFormat: AudioFormat;
    /**
     * Required to interpret PCM payloads. For compressed formats this is the
     * synthesis rate, not the container rate.
     */
    sampleRate: number;
    durationMs: number;
    metadata?: TTSSynthesisMetadata | undefined;
    /** Milliseconds since epoch. */
    timestampMs: number;
    /** For one-shot synthesis, chunk_index=0 and is_final=true. */
    chunkIndex: number;
    isFinal: boolean;
    error?: SDKError | undefined;
}
/**
 * Metadata-only view for callers that let the SDK play the audio and never
 * need the raw bytes.
 */
export interface TTSSpeakResult {
    audioFormat: AudioFormat;
    sampleRate: number;
    durationMs: number;
    /** 0 for system TTS that plays directly without exposing buffers. */
    audioSizeBytes: number;
    metadata?: TTSSynthesisMetadata | undefined;
    /** Milliseconds since epoch, when speech completed. */
    timestampMs: number;
    error?: SDKError | undefined;
}
export interface TTSVoiceInfo {
    /** Passed back as TTSOptions.voice. */
    id: string;
    /**
     * e.g. "Samantha". MUST NOT be a copy of `id` -- fall back to the model
     * id only when the engine reports no display name.
     */
    displayName: string;
    /** BCP-47. */
    languageCode: string;
    /**
     * The voice's native rate in Hz -- tells the caller whether naming a
     * different TTSOptions.sample_rate buys anything.
     */
    sampleRate: number;
}
export interface TTSVoiceList {
    voices: TTSVoiceInfo[];
}
export interface TTSStreamEvent {
    timestampUs: number;
    requestId: string;
    kind: TTSStreamEventKind;
    output?: TTSOutput | undefined;
    error?: SDKError | undefined;
}
export interface TTSServiceState {
    isReady: boolean;
    currentVoice?: string | undefined;
    supportedLanguageCodes: string[];
    error?: SDKError | undefined;
}
export declare const TTSOptions: MessageFns<TTSOptions>;
export declare const TTSSynthesisRequest: MessageFns<TTSSynthesisRequest>;
export declare const TTSSynthesisMetadata: MessageFns<TTSSynthesisMetadata>;
export declare const TTSOutput: MessageFns<TTSOutput>;
export declare const TTSSpeakResult: MessageFns<TTSSpeakResult>;
export declare const TTSVoiceInfo: MessageFns<TTSVoiceInfo>;
export declare const TTSVoiceList: MessageFns<TTSVoiceList>;
export declare const TTSStreamEvent: MessageFns<TTSStreamEvent>;
export declare const TTSServiceState: MessageFns<TTSServiceState>;
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
