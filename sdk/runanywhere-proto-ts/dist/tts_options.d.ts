import _m0 from "protobufjs/minimal";
import { AudioFormat, InferenceFramework } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Voice gender — union across SDKs.
 * Sources pre-IDL:
 *   RN     TTSTypes.ts:117    ('male' | 'female' | 'neutral')
 * (Other SDKs did not expose voice listing pre-IDL; canonicalized here.)
 * ---------------------------------------------------------------------------
 */
export declare enum TTSVoiceGender {
    TTS_VOICE_GENDER_UNSPECIFIED = 0,
    TTS_VOICE_GENDER_MALE = 1,
    TTS_VOICE_GENDER_FEMALE = 2,
    TTS_VOICE_GENDER_NEUTRAL = 3,
    UNRECOGNIZED = -1
}
export declare function tTSVoiceGenderFromJSON(object: any): TTSVoiceGender;
export declare function tTSVoiceGenderToJSON(object: TTSVoiceGender): string;
/**
 * ---------------------------------------------------------------------------
 * Component-level TTS configuration.
 *
 * Mirrors the C ABI rac_tts_config_t exactly (minus preferred_framework, which
 * is a runtime hint, not part of the wire contract). Field names match Swift
 * TTSConfiguration / Kotlin TTSConfiguration.
 *
 * Defaults (for documentation; proto3 zero-values apply on the wire):
 *   voice              = "default"  (Kotlin) / "com.apple.ttsbundle..." (Swift)
 *   language_code      = "en-US"
 *   speaking_rate      = 1.0   (range 0.5 – 2.0)
 *   pitch              = 1.0   (range 0.5 – 2.0)
 *   volume             = 1.0   (range 0.0 – 1.0)
 *   audio_format       = AUDIO_FORMAT_PCM
 *   sample_rate        = 22050 (RAC_TTS_DEFAULT_SAMPLE_RATE)
 *   enable_neural_voice= true
 *   enable_ssml        = false
 * ---------------------------------------------------------------------------
 */
export interface TTSConfiguration {
    /**
     * Model identifier (voice model file id, e.g. piper voice). Optional —
     * platform TTS engines (Apple System TTS, Android TextToSpeech) don't
     * require a model file.
     */
    modelId: string;
    /**
     * Voice identifier to use for synthesis. For platform engines this is the
     * engine-specific voice id (e.g. "com.apple.ttsbundle.siri_female_en-US_compact").
     */
    voice: string;
    /** Language for synthesis (BCP-47, e.g. "en-US"). */
    languageCode: string;
    /** Speaking rate (0.5 – 2.0; 1.0 is normal). */
    speakingRate: number;
    /** Speech pitch (0.5 – 2.0; 1.0 is normal). */
    pitch: number;
    /** Speech volume (0.0 – 1.0). */
    volume: number;
    /** Output audio format. */
    audioFormat: AudioFormat;
    /**
     * Sample rate for output audio in Hz. 0 = engine default
     * (RAC_TTS_DEFAULT_SAMPLE_RATE = 22050).
     */
    sampleRate: number;
    /** Whether to use neural / premium voice if available. */
    enableNeuralVoice: boolean;
    /** Whether to enable SSML markup support. */
    enableSsml: boolean;
    /**
     * Preferred framework for the component. Absent = auto. Mirrors the C
     * ABI rac_tts_config_t preferred_framework field.
     */
    preferredFramework?: InferenceFramework | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Per-call TTS synthesis options.
 *
 * Mirrors the C ABI rac_tts_options_t exactly. Field names match Swift
 * TTSOptions / Kotlin TTSOptions / Dart TTSOptions.
 *
 * Note: `voice` is optional at the source (Swift `String?`, C `const char* =
 * NULL`). On the wire, an empty string MUST be interpreted as "use the
 * component's configured voice".
 * ---------------------------------------------------------------------------
 */
export interface TTSOptions {
    /** Voice override (empty = use component default). */
    voice: string;
    /** Language override (BCP-47). Empty = use component default. */
    languageCode: string;
    /**
     * Speech rate (0.0 – 2.0; 1.0 is normal). Note Swift/Kotlin use the name
     * `rate`, Dart uses `rate`, RN uses `rate`. C ABI field is `rate`. We
     * canonicalize on `speaking_rate` to match TTSConfiguration; bindings
     * alias to `rate` where appropriate.
     */
    speakingRate: number;
    /** Speech pitch (0.5 – 2.0; 1.0 is normal). */
    pitch: number;
    /** Speech volume (0.0 – 1.0). */
    volume: number;
    /**
     * Whether the input contains SSML markup. C ABI: `use_ssml`, Swift:
     * `useSSML`, Kotlin: `useSSML`, Dart: `useSSML`. Canonicalized to
     * `enable_ssml` for consistency with TTSConfiguration.
     */
    enableSsml: boolean;
    /** Output audio format. */
    audioFormat: AudioFormat;
    /**
     * Output sample rate override in Hz. 0 = component/default sample rate.
     * Present in rac_tts_options_t and several SDK option structs.
     */
    sampleRate: number;
}
/**
 * ---------------------------------------------------------------------------
 * Phoneme-level timestamp.
 *
 * Mirrors the C ABI rac_tts_phoneme_timestamp_t exactly. Time units are
 * **milliseconds** on the wire (matches C ABI). Swift / Kotlin / Dart bindings
 * expose seconds (double) and convert at the binding boundary.
 * ---------------------------------------------------------------------------
 */
export interface TTSPhonemeTimestamp {
    /** The phoneme symbol (IPA or engine-specific). */
    phoneme: string;
    /** Start time within the synthesized audio, in milliseconds. */
    startMs: number;
    /** End time within the synthesized audio, in milliseconds. */
    endMs: number;
}
/**
 * ---------------------------------------------------------------------------
 * Synthesis metadata.
 *
 * Mirrors the C ABI rac_tts_synthesis_metadata_t. Time units in milliseconds
 * and durations as int64 to match the C ABI.
 * ---------------------------------------------------------------------------
 */
export interface TTSSynthesisMetadata {
    /** Voice id used for synthesis. */
    voiceId: string;
    /**
     * Language used for synthesis (BCP-47). Source field name varies:
     * C ABI: `language`, Swift: `language`, Kotlin: `language`. We use
     * `language_code` to match TTSConfiguration / TTSOptions.
     */
    languageCode: string;
    /** Wall-clock processing time in milliseconds. */
    processingTimeMs: number;
    /** Number of input characters synthesized. */
    characterCount: number;
    /**
     * Audio duration in milliseconds. Present in C ABI rac_tts_output_t but
     * mirrored here so metadata is self-describing for clients that consume
     * metadata-only paths (e.g. TTSSpeakResult).
     */
    audioDurationMs: number;
    /**
     * Characters processed per second. Some native paths expose this directly;
     * consumers may also compute it from character_count / processing_time_ms.
     */
    charactersPerSecond: number;
}
/**
 * ---------------------------------------------------------------------------
 * Full TTS output: synthesized audio plus metadata.
 *
 * Mirrors the C ABI rac_tts_output_t. `audio_data` is opaque bytes; bindings
 * adapt to native buffers (Swift Data, Kotlin ByteArray, Dart Uint8List,
 * JS ArrayBuffer/Float32Array, C void*). Sample rate is required because PCM
 * payloads are otherwise unparseable.
 * ---------------------------------------------------------------------------
 */
export interface TTSOutput {
    /** Synthesized audio bytes, encoded per `audio_format`. */
    audioData: Uint8Array;
    /** Audio format of the bytes in `audio_data`. */
    audioFormat: AudioFormat;
    /**
     * Sample rate in Hz. For PCM payloads this is required to interpret the
     * bytes; for compressed formats (mp3, opus, …) it reflects the synthesis
     * sample rate, not the container rate.
     */
    sampleRate: number;
    /** Audio duration in milliseconds (matches C ABI `duration_ms`). */
    durationMs: number;
    /** Phoneme-level timestamps, if the engine produced them. May be empty. */
    phonemeTimestamps: TTSPhonemeTimestamp[];
    /** Per-pass synthesis metadata. */
    metadata?: TTSSynthesisMetadata | undefined;
    /**
     * Wall-clock timestamp when the output was produced
     * (milliseconds since UNIX epoch). Mirrors C ABI `timestamp_ms`.
     */
    timestampMs: number;
}
/**
 * ---------------------------------------------------------------------------
 * Result of a `speak()` call — metadata-only view of an already-played
 * synthesis pass. Used when the SDK plays audio internally and the caller
 * does not need raw bytes.
 *
 * Mirrors the C ABI rac_tts_speak_result_t. Identical to TTSOutput minus
 * `audio_data` and `phoneme_timestamps`; `audio_size_bytes` is retained for
 * callers that want to know how much was synthesized.
 * ---------------------------------------------------------------------------
 */
export interface TTSSpeakResult {
    /** Audio format used during synthesis. */
    audioFormat: AudioFormat;
    /** Sample rate in Hz used during synthesis. */
    sampleRate: number;
    /** Audio duration in milliseconds. */
    durationMs: number;
    /**
     * Audio size in bytes (0 for system TTS that plays directly without
     * exposing buffers).
     */
    audioSizeBytes: number;
    /** Per-pass synthesis metadata. */
    metadata?: TTSSynthesisMetadata | undefined;
    /** Wall-clock timestamp when speech completed (ms since UNIX epoch). */
    timestampMs: number;
}
/**
 * ---------------------------------------------------------------------------
 * Descriptor for a TTS voice the engine can use.
 *
 * Pre-IDL only RN exposed this (TTSTypes.ts:106). Canonicalized here so all
 * SDKs gain a typed voice-listing API. `gender` uses an enum to avoid the
 * string-typed drift that RN had ('male' | 'female' | 'neutral').
 * ---------------------------------------------------------------------------
 */
export interface TTSVoiceInfo {
    /**
     * Engine-specific voice identifier (passed back as TTSOptions.voice or
     * TTSConfiguration.voice).
     */
    id: string;
    /** Human-readable display name (e.g. "Samantha", "Daniel"). */
    displayName: string;
    /** Language spoken by this voice (BCP-47, e.g. "en-US"). */
    languageCode: string;
    /** Voice gender, when known. */
    gender: TTSVoiceGender;
    /** Optional descriptive text (locale, age, style notes). */
    description: string;
}
export declare const TTSConfiguration: {
    encode(message: TTSConfiguration, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TTSConfiguration;
    fromJSON(object: any): TTSConfiguration;
    toJSON(message: TTSConfiguration): unknown;
    create<I extends Exact<DeepPartial<TTSConfiguration>, I>>(base?: I): TTSConfiguration;
    fromPartial<I extends Exact<DeepPartial<TTSConfiguration>, I>>(object: I): TTSConfiguration;
};
export declare const TTSOptions: {
    encode(message: TTSOptions, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TTSOptions;
    fromJSON(object: any): TTSOptions;
    toJSON(message: TTSOptions): unknown;
    create<I extends Exact<DeepPartial<TTSOptions>, I>>(base?: I): TTSOptions;
    fromPartial<I extends Exact<DeepPartial<TTSOptions>, I>>(object: I): TTSOptions;
};
export declare const TTSPhonemeTimestamp: {
    encode(message: TTSPhonemeTimestamp, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TTSPhonemeTimestamp;
    fromJSON(object: any): TTSPhonemeTimestamp;
    toJSON(message: TTSPhonemeTimestamp): unknown;
    create<I extends Exact<DeepPartial<TTSPhonemeTimestamp>, I>>(base?: I): TTSPhonemeTimestamp;
    fromPartial<I extends Exact<DeepPartial<TTSPhonemeTimestamp>, I>>(object: I): TTSPhonemeTimestamp;
};
export declare const TTSSynthesisMetadata: {
    encode(message: TTSSynthesisMetadata, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TTSSynthesisMetadata;
    fromJSON(object: any): TTSSynthesisMetadata;
    toJSON(message: TTSSynthesisMetadata): unknown;
    create<I extends Exact<DeepPartial<TTSSynthesisMetadata>, I>>(base?: I): TTSSynthesisMetadata;
    fromPartial<I extends Exact<DeepPartial<TTSSynthesisMetadata>, I>>(object: I): TTSSynthesisMetadata;
};
export declare const TTSOutput: {
    encode(message: TTSOutput, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TTSOutput;
    fromJSON(object: any): TTSOutput;
    toJSON(message: TTSOutput): unknown;
    create<I extends Exact<DeepPartial<TTSOutput>, I>>(base?: I): TTSOutput;
    fromPartial<I extends Exact<DeepPartial<TTSOutput>, I>>(object: I): TTSOutput;
};
export declare const TTSSpeakResult: {
    encode(message: TTSSpeakResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TTSSpeakResult;
    fromJSON(object: any): TTSSpeakResult;
    toJSON(message: TTSSpeakResult): unknown;
    create<I extends Exact<DeepPartial<TTSSpeakResult>, I>>(base?: I): TTSSpeakResult;
    fromPartial<I extends Exact<DeepPartial<TTSSpeakResult>, I>>(object: I): TTSSpeakResult;
};
export declare const TTSVoiceInfo: {
    encode(message: TTSVoiceInfo, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TTSVoiceInfo;
    fromJSON(object: any): TTSVoiceInfo;
    toJSON(message: TTSVoiceInfo): unknown;
    create<I extends Exact<DeepPartial<TTSVoiceInfo>, I>>(base?: I): TTSVoiceInfo;
    fromPartial<I extends Exact<DeepPartial<TTSVoiceInfo>, I>>(object: I): TTSVoiceInfo;
};
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
export {};
//# sourceMappingURL=tts_options.d.ts.map