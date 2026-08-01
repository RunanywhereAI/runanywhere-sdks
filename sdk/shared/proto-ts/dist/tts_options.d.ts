import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
import { AudioFormat, InferenceFramework } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
export declare enum TTSVoiceGender {
    TTS_VOICE_GENDER_UNSPECIFIED = 0,
    TTS_VOICE_GENDER_MALE = 1,
    TTS_VOICE_GENDER_FEMALE = 2,
    TTS_VOICE_GENDER_NEUTRAL = 3,
    UNRECOGNIZED = -1
}
export declare function tTSVoiceGenderFromJSON(object: any): TTSVoiceGender;
export declare function tTSVoiceGenderToJSON(object: TTSVoiceGender): string;
export declare enum TTSStreamEventKind {
    TTS_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    TTS_STREAM_EVENT_KIND_STARTED = 1,
    TTS_STREAM_EVENT_KIND_AUDIO_CHUNK = 2,
    TTS_STREAM_EVENT_KIND_PHONEME = 3,
    TTS_STREAM_EVENT_KIND_COMPLETED = 4,
    TTS_STREAM_EVENT_KIND_ERROR = 5,
    TTS_STREAM_EVENT_KIND_PROGRESS = 6,
    UNRECOGNIZED = -1
}
export declare function tTSStreamEventKindFromJSON(object: any): TTSStreamEventKind;
export declare function tTSStreamEventKindToJSON(object: TTSStreamEventKind): string;
export interface TTSConfiguration {
    /**
     * Voice model file id, e.g. a piper voice. Empty for platform TTS engines
     * (Apple System TTS, Android TextToSpeech), which need no model file.
     */
    modelId: string;
    /** Use the neural or premium voice when available. */
    enableNeuralVoice: boolean;
    preferredFramework?: InferenceFramework | undefined;
    /** Applied when a per-call TTSOptions is absent or leaves a field unset. */
    defaultOptions?: TTSOptions | undefined;
}
export interface TTSOptions {
    /** Empty = use the component's configured voice. */
    voice: string;
    /** BCP-47. Empty = use the component default. */
    languageCode: string;
    /** Speed multiplier, matching OpenAI /audio/speech `speed`. */
    speed: number;
    /** 0.5 - 2.0. */
    pitch: number;
    /** 0.0 - 1.0. */
    volume: number;
    /** Whether the input carries SSML markup. */
    enableSsml: boolean;
    audioFormat: AudioFormat;
    /** 0 = component default. */
    sampleRate: number;
    /** For multi-speaker voices. -1 or 0 = backend default, per model convention. */
    speakerId: number;
    /** Style or emotion hint for voices supporting style transfer. */
    style?: string | undefined;
}
export interface TTSSynthesisRequest {
    requestId: string;
    text: string;
    ssml?: string | undefined;
    options?: TTSOptions | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface TTSSynthesisRequest_MetadataEntry {
    key: string;
    value: string;
}
export interface TTSPhonemeTimestamp {
    /** IPA or engine-specific symbol. */
    phoneme: string;
    /** Offsets within the synthesized audio. */
    startMs: number;
    endMs: number;
}
export interface TTSSynthesisMetadata {
    voiceId: string;
    /** BCP-47. */
    languageCode: string;
    processingTimeMs: number;
    characterCount: number;
    audioDurationMs: number;
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
    /** Empty unless the engine produced them. */
    phonemeTimestamps: TTSPhonemeTimestamp[];
    metadata?: TTSSynthesisMetadata | undefined;
    /** Milliseconds since epoch. */
    timestampMs: number;
    /** For one-shot synthesis, chunk_index=0 and is_final=true. */
    chunkIndex: number;
    isFinal: boolean;
    audioSizeBytes: number;
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
    /** e.g. "Samantha". */
    displayName: string;
    /** BCP-47. */
    languageCode: string;
    gender: TTSVoiceGender;
    /** Locale, age, or style notes. */
    description: string;
    isNeural: boolean;
    isSystem: boolean;
    sampleRate: number;
    supportedStyles: string[];
}
export interface TTSVoiceList {
    voices: TTSVoiceInfo[];
}
export interface TTSStreamEvent {
    timestampUs: number;
    requestId: string;
    kind: TTSStreamEventKind;
    output?: TTSOutput | undefined;
    phoneme?: TTSPhonemeTimestamp | undefined;
    speakResult?: TTSSpeakResult | undefined;
    /** progress is 0.0-1.0 when known; total_chunks 0 = unknown. */
    progress: number;
    chunkIndex: number;
    totalChunks: number;
    elapsedMs: number;
    statusMessage: string;
    error?: SDKError | undefined;
}
export interface TTSServiceState {
    isReady: boolean;
    currentVoice?: string | undefined;
    voices: TTSVoiceInfo[];
    supportedLanguageCodes: string[];
    error?: SDKError | undefined;
}
export declare const TTSConfiguration: MessageFns<TTSConfiguration>;
export declare const TTSOptions: MessageFns<TTSOptions>;
export declare const TTSSynthesisRequest: MessageFns<TTSSynthesisRequest>;
export declare const TTSSynthesisRequest_MetadataEntry: MessageFns<TTSSynthesisRequest_MetadataEntry>;
export declare const TTSPhonemeTimestamp: MessageFns<TTSPhonemeTimestamp>;
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
