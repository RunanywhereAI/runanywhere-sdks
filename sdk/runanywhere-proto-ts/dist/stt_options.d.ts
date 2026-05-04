import _m0 from "protobufjs/minimal";
import { AudioFormat, InferenceFramework } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * STT language hint. Sources pre-IDL:
 *   Swift  STTConfiguration default = "en-US", STTOptions default = "en"
 *   Kotlin STTConfiguration default = "en-US", STTOptions default = "en"
 *   Dart   STTOptions language nullable; auto-detect when null
 *   RN     STTOptions.language?: string (free-form)
 *   Web    STTTranscribeOptions.language?: string (free-form)
 *   C ABI  RAC_STT_DEFAULT_LANGUAGE = "en"
 * Free-form BCP-47 strings are collapsed to base language codes here.
 * AUTO is the explicit "detect from audio" sentinel; UNSPECIFIED falls
 * back to the backend default (typically "en").
 * ---------------------------------------------------------------------------
 */
export declare enum STTLanguage {
    STT_LANGUAGE_UNSPECIFIED = 0,
    /** STT_LANGUAGE_AUTO - Auto-detect from audio */
    STT_LANGUAGE_AUTO = 1,
    STT_LANGUAGE_EN = 2,
    STT_LANGUAGE_ES = 3,
    STT_LANGUAGE_FR = 4,
    STT_LANGUAGE_DE = 5,
    STT_LANGUAGE_ZH = 6,
    STT_LANGUAGE_JA = 7,
    STT_LANGUAGE_KO = 8,
    STT_LANGUAGE_IT = 9,
    STT_LANGUAGE_PT = 10,
    STT_LANGUAGE_AR = 11,
    STT_LANGUAGE_RU = 12,
    STT_LANGUAGE_HI = 13,
    UNRECOGNIZED = -1
}
export declare function sTTLanguageFromJSON(object: any): STTLanguage;
export declare function sTTLanguageToJSON(object: STTLanguage): string;
/**
 * ---------------------------------------------------------------------------
 * STT component configuration (init-time settings).
 * Sources pre-IDL:
 *   Swift  STTTypes.swift:15           STTConfiguration
 *   Kotlin STTTypes.kt:27              STTConfiguration
 *   Dart   stt_configuration.dart:9    STTConfiguration
 *   C ABI  rac_stt_types.h:76          rac_stt_config_t
 *
 * Note: max_alternatives, enable_punctuation, enable_diarization, and
 * enable_timestamps appear in the pre-IDL configs but are runtime knobs
 * in the canonical model. They live on STTOptions; STTConfiguration
 * keeps only true init-time fields (model id, language, sample rate,
 * VAD toggle, audio format). Producers should mirror runtime knobs into
 * STTOptions when constructing requests.
 * ---------------------------------------------------------------------------
 */
export interface STTConfiguration {
    modelId: string;
    language: STTLanguage;
    /** Hz; default 16000 */
    sampleRate: number;
    enableVad: boolean;
    audioFormat: AudioFormat;
    /**
     * C ABI / legacy SDK config-level transcription defaults. These may be
     * mirrored into STTOptions by adapters for per-call overrides.
     */
    enablePunctuation: boolean;
    enableDiarization: boolean;
    vocabularyList: string[];
    /** 0 = backend/default */
    maxAlternatives: number;
    enableWordTimestamps: boolean;
    /** Preferred framework for the component. Absent = auto. */
    preferredFramework?: InferenceFramework | undefined;
    /**
     * Free-form BCP-47 language tag ("en-US", "pt-BR", etc.) for callers
     * that cannot be represented by STTLanguage's base-code enum.
     */
    languageCode?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * STT runtime transcription options (per-call overrides).
 * Sources pre-IDL:
 *   Swift  STTTypes.swift:64           STTOptions  (10 fields)
 *   Kotlin STTTypes.kt:65              STTOptions  (10 fields)
 *   Dart   generation_types.dart:78    STTOptions  (10 fields)
 *   RN     STTTypes.ts:12              STTOptions  (5 fields, narrower)
 *   Web    STTTypes.ts:25              STTTranscribeOptions (2 fields)
 *   C ABI  rac_stt_types.h:130         rac_stt_options_t (8 fields)
 *
 * Per spec, this canonical message exposes: language, enable_punctuation,
 * enable_diarization, max_speakers, vocabulary_list, enable_word_timestamps,
 * beam_size. Other pre-IDL fields (audio_format, sample_rate, detect_language,
 * preferred_framework) are part of STTConfiguration or implied by
 * STT_LANGUAGE_AUTO.
 * ---------------------------------------------------------------------------
 */
export interface STTOptions {
    language: STTLanguage;
    enablePunctuation: boolean;
    enableDiarization: boolean;
    /** 0 = auto / unset */
    maxSpeakers: number;
    /** Custom vocabulary bias */
    vocabularyList: string[];
    enableWordTimestamps: boolean;
    /** 0 = backend default */
    beamSize: number;
    /**
     * Free-form BCP-47 language tag. When set, consumers should prefer this
     * over the base-language enum above.
     */
    languageCode?: string | undefined;
    /**
     * Explicit language auto-detection flag for C ABI parity. Equivalent to
     * language == STT_LANGUAGE_AUTO for generated-only consumers.
     */
    detectLanguage: boolean;
    /** Per-call input audio hints mirrored from rac_stt_options_t. */
    audioFormat: AudioFormat;
    sampleRate: number;
    /** Maximum number of alternatives to return. 0 = backend/default. */
    maxAlternatives: number;
}
/**
 * ---------------------------------------------------------------------------
 * Word-level timestamp.
 * Sources pre-IDL:
 *   Swift  STTTypes.swift:260          WordTimestamp (TimeInterval seconds)
 *   Kotlin STTTypes.kt:141             WordTimestamp (Double seconds)
 *   Dart   generation_types.dart:124   WordTimestamp (double seconds, conf?)
 *   RN     STTTypes.ts:55              WordTimestamp (number seconds)
 *   Web    STTTypes.ts:18              STTWord       (number ms)
 *   C ABI  rac_stt_types.h:175         rac_stt_word_t (int64 ms)
 *
 * Canonicalize on int64 *_ms (matches C ABI and Web).
 * ---------------------------------------------------------------------------
 */
export interface WordTimestamp {
    word: string;
    startMs: number;
    endMs: number;
    confidence: number;
}
/**
 * ---------------------------------------------------------------------------
 * Alternative transcription hypothesis (n-best).
 * Sources pre-IDL:
 *   Swift  STTTypes.swift:275          TranscriptionAlternative (text, confidence)
 *   Kotlin STTTypes.kt:155             TranscriptionAlternative (text, confidence)
 *   Dart   generation_types.dart:146   TranscriptionAlternative (transcript, confidence)
 *   RN     STTTypes.ts:65              STTAlternative (text, confidence)
 *   C ABI  rac_stt_types.h:320         rac_transcription_alternative_t (text, confidence)
 *
 * Drift: Dart uses `transcript` while everyone else uses `text`. Canonical
 * field name is `text`. Per-word breakdown is OPTIONAL (only some backends
 * emit it for alternatives).
 * ---------------------------------------------------------------------------
 */
export interface TranscriptionAlternative {
    text: string;
    confidence: number;
    words: WordTimestamp[];
}
/**
 * ---------------------------------------------------------------------------
 * Per-pass transcription metadata.
 * Sources pre-IDL:
 *   Swift  STTTypes.swift:241          TranscriptionMetadata (s + computed RTF)
 *   Kotlin STTTypes.kt:124             TranscriptionMetadata (s + computed RTF)
 *   Dart   generation_types.dart:160   TranscriptionMetadata (s + computed RTF)
 *   RN     STTTypes.ts:73              TranscriptionMetadata (s + optional RTF)
 *   C ABI  rac_stt_types.h:297         rac_transcription_metadata_t (ms + RTF)
 *
 * Canonicalize on ms (matches C ABI). real_time_factor is producer-set;
 * consumers may recompute as processing_time_ms / audio_length_ms.
 * ---------------------------------------------------------------------------
 */
export interface TranscriptionMetadata {
    modelId: string;
    processingTimeMs: number;
    audioLengthMs: number;
    realTimeFactor: number;
}
/**
 * ---------------------------------------------------------------------------
 * Final STT output.
 * Sources pre-IDL:
 *   Swift  STTTypes.swift:147          STTOutput (text, conf, words, lang, alts, meta, ts)
 *   Kotlin STTTypes.kt:100             STTOutput (text, conf, words, lang, alts, meta, ts)
 *   Dart   generation_types.dart:218   STTResult / STTOutput (text, conf, durMs, lang, words, alts, meta, ts)
 *   RN     STTTypes.ts:32              STTOutput (text, conf, words, lang, alts, meta)
 *   Web    STTTypes.ts:9               STTTranscriptionResult (text, conf, lang, procMs, words)
 *   C ABI  rac_stt_types.h:338         rac_stt_output_t (text, conf, words, lang, alts, meta, ts_ms)
 *
 * Drift reconciled:
 *   - language: detected language. Promoted to STTLanguage enum.
 *   - durationMs (Dart) / processingTimeMs (Web) → captured in metadata.
 * ---------------------------------------------------------------------------
 */
export interface STTOutput {
    text: string;
    language: STTLanguage;
    confidence: number;
    words: WordTimestamp[];
    alternatives: TranscriptionAlternative[];
    metadata?: TranscriptionMetadata | undefined;
    /** Free-form detected language tag, preserving regional variants. */
    languageCode?: string | undefined;
    /** Wall-clock output timestamp in milliseconds since Unix epoch. */
    timestampMs: number;
    /**
     * Audio duration in milliseconds for SDKs that expose duration directly.
     * Often duplicates metadata.audio_length_ms.
     */
    durationMs: number;
}
/**
 * ---------------------------------------------------------------------------
 * Streaming partial result emitted during live transcription.
 * Sources pre-IDL:
 *   Dart   generation_types.dart:184   STTPartialResult (transcript, conf, isFinal, lang, ts, alts)
 *   RN     STTTypes.ts:90              STTPartialResult (transcript, conf, ts, lang, alts, isFinal)
 *   C ABI  rac_stt_types.h:240         rac_stt_stream_callback_t (partial_text, is_final)
 *   Web    STTTypes.ts:31              STTStreamCallback (text, isFinal)
 *
 * Canonical minimal shape per spec: text, is_final, stability. Full word
 * timestamps + alternatives flow through STTOutput on the terminal event.
 * `stability` is the Whisper-style hypothesis stability score (0.0-1.0);
 * 0.0 when backend does not provide one.
 * ---------------------------------------------------------------------------
 */
export interface STTPartialResult {
    text: string;
    isFinal: boolean;
    stability: number;
    /** Additional partial-hypothesis fields carried by Dart/RN live streams. */
    confidence: number;
    language: STTLanguage;
    timestampMs: number;
    alternatives: TranscriptionAlternative[];
    languageCode?: string | undefined;
}
export declare const STTConfiguration: {
    encode(message: STTConfiguration, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): STTConfiguration;
    fromJSON(object: any): STTConfiguration;
    toJSON(message: STTConfiguration): unknown;
    create<I extends Exact<DeepPartial<STTConfiguration>, I>>(base?: I): STTConfiguration;
    fromPartial<I extends Exact<DeepPartial<STTConfiguration>, I>>(object: I): STTConfiguration;
};
export declare const STTOptions: {
    encode(message: STTOptions, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): STTOptions;
    fromJSON(object: any): STTOptions;
    toJSON(message: STTOptions): unknown;
    create<I extends Exact<DeepPartial<STTOptions>, I>>(base?: I): STTOptions;
    fromPartial<I extends Exact<DeepPartial<STTOptions>, I>>(object: I): STTOptions;
};
export declare const WordTimestamp: {
    encode(message: WordTimestamp, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): WordTimestamp;
    fromJSON(object: any): WordTimestamp;
    toJSON(message: WordTimestamp): unknown;
    create<I extends Exact<DeepPartial<WordTimestamp>, I>>(base?: I): WordTimestamp;
    fromPartial<I extends Exact<DeepPartial<WordTimestamp>, I>>(object: I): WordTimestamp;
};
export declare const TranscriptionAlternative: {
    encode(message: TranscriptionAlternative, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TranscriptionAlternative;
    fromJSON(object: any): TranscriptionAlternative;
    toJSON(message: TranscriptionAlternative): unknown;
    create<I extends Exact<DeepPartial<TranscriptionAlternative>, I>>(base?: I): TranscriptionAlternative;
    fromPartial<I extends Exact<DeepPartial<TranscriptionAlternative>, I>>(object: I): TranscriptionAlternative;
};
export declare const TranscriptionMetadata: {
    encode(message: TranscriptionMetadata, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TranscriptionMetadata;
    fromJSON(object: any): TranscriptionMetadata;
    toJSON(message: TranscriptionMetadata): unknown;
    create<I extends Exact<DeepPartial<TranscriptionMetadata>, I>>(base?: I): TranscriptionMetadata;
    fromPartial<I extends Exact<DeepPartial<TranscriptionMetadata>, I>>(object: I): TranscriptionMetadata;
};
export declare const STTOutput: {
    encode(message: STTOutput, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): STTOutput;
    fromJSON(object: any): STTOutput;
    toJSON(message: STTOutput): unknown;
    create<I extends Exact<DeepPartial<STTOutput>, I>>(base?: I): STTOutput;
    fromPartial<I extends Exact<DeepPartial<STTOutput>, I>>(object: I): STTOutput;
};
export declare const STTPartialResult: {
    encode(message: STTPartialResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): STTPartialResult;
    fromJSON(object: any): STTPartialResult;
    toJSON(message: STTPartialResult): unknown;
    create<I extends Exact<DeepPartial<STTPartialResult>, I>>(base?: I): STTPartialResult;
    fromPartial<I extends Exact<DeepPartial<STTPartialResult>, I>>(object: I): STTPartialResult;
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
//# sourceMappingURL=stt_options.d.ts.map