import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { AudioFormat, InferenceFramework } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
export declare enum STTAudioEncoding {
    STT_AUDIO_ENCODING_UNSPECIFIED = 0,
    STT_AUDIO_ENCODING_PCM_S16_LE = 1,
    STT_AUDIO_ENCODING_PCM_F32_LE = 2,
    /** STT_AUDIO_ENCODING_CONTAINER - WAV/MP3/FLAC/etc.; see AudioFormat. */
    STT_AUDIO_ENCODING_CONTAINER = 3,
    UNRECOGNIZED = -1
}
export declare function sTTAudioEncodingFromJSON(object: any): STTAudioEncoding;
export declare function sTTAudioEncodingToJSON(object: STTAudioEncoding): string;
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
    /** Default input language, BCP-47 / ISO-639-1. Unset/empty = auto-detect. */
    language?: string | undefined;
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
    /**
     * Input language as a BCP-47 / ISO-639-1 tag ("en", "en-US", "hi").
     * Unset or empty = auto-detect. Matches the industry `language` param.
     */
    language?: string | undefined;
    enablePunctuation: boolean;
    enableDiarization: boolean;
    /** 0 = auto */
    maxSpeakers: number;
    /** Custom vocabulary bias */
    vocabularyList: string[];
    enableWordTimestamps: boolean;
    /** 0 = backend default */
    beamSize: number;
    /** Maximum number of alternatives to return. 0 = backend/default. */
    maxAlternatives: number;
    /** Streaming/endpointer controls. 0 = backend/default. */
    chunkDurationMs: number;
    endpointSilenceMs: number;
    suppressBlank: boolean;
    translateToEnglish: boolean;
}
export interface STTAudioSource {
    audioData?: Uint8Array | undefined;
    fileUri?: string | undefined;
    adapterHandle?: string | undefined;
    encoding: STTAudioEncoding;
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
    speakerId?: string | undefined;
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
    confidence: number;
    /** Detected language, BCP-47 (preserves regional variants). Empty = unknown. */
    language?: string | undefined;
    words: WordTimestamp[];
    alternatives: TranscriptionAlternative[];
    metadata?: TranscriptionMetadata | undefined;
    /** Wall-clock output timestamp in milliseconds since Unix epoch. */
    timestampMs: number;
    /**
     * Audio duration in milliseconds for SDKs that expose duration directly.
     * Often duplicates metadata.audio_length_ms.
     */
    durationMs: number;
    /** Diarization summary when available. */
    speakerIds: string[];
    /** Terminal error details for result-envelope APIs. */
    errorMessage?: string | undefined;
    errorCode: number;
    /** Segment index for long-running/streaming transcription. */
    segmentIndex: number;
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
    language?: string | undefined;
    timestampMs: number;
    alternatives: TranscriptionAlternative[];
    /** Streaming correlation and endpointing metadata. */
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
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface STTServiceState {
    isReady: boolean;
    currentModel?: string | undefined;
    supportsStreaming: boolean;
    supportedLanguageCodes: string[];
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface STTLanguageDetectionResult {
    /** Detected language, BCP-47. */
    language: string;
    confidence: number;
    alternatives: string[];
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
export declare const STTLanguageDetectionResult: MessageFns<STTLanguageDetectionResult>;
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
