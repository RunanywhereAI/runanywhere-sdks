import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { InferenceFramework } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Speech-activity lifecycle kind.
 * Sources pre-IDL:
 *   Swift  VADTypes.swift:235               (started, ended)
 *   Kotlin VADTypes.kt:171                  (STARTED, ENDED)
 *   Dart   runanywhere_vad.dart:28          (started, ended)
 *   RN     VADTypes.ts:43                   ('started' | 'ended')
 *   Web    VADTypes.ts:8                    (Started, Ended, Ongoing)   ← only SDK with ONGOING
 *   C ABI  rac_vad_types.h:107              (RAC_SPEECH_STARTED, RAC_SPEECH_ENDED, RAC_SPEECH_ONGOING)
 * Canonical union: STARTED, ENDED, ONGOING.
 * ---------------------------------------------------------------------------
 */
export declare enum SpeechActivityKind {
    /** SPEECH_ACTIVITY_KIND_UNSPECIFIED - Reserved (proto3 default) */
    SPEECH_ACTIVITY_KIND_UNSPECIFIED = 0,
    SPEECH_ACTIVITY_KIND_SPEECH_STARTED = 1,
    SPEECH_ACTIVITY_KIND_SPEECH_ENDED = 2,
    SPEECH_ACTIVITY_KIND_ONGOING = 3,
    UNRECOGNIZED = -1
}
export declare function speechActivityKindFromJSON(object: any): SpeechActivityKind;
export declare function speechActivityKindToJSON(object: SpeechActivityKind): string;
export declare enum VADAudioEncoding {
    VAD_AUDIO_ENCODING_UNSPECIFIED = 0,
    VAD_AUDIO_ENCODING_PCM_F32_LE = 1,
    VAD_AUDIO_ENCODING_PCM_S16_LE = 2,
    UNRECOGNIZED = -1
}
export declare function vADAudioEncodingFromJSON(object: any): VADAudioEncoding;
export declare function vADAudioEncodingToJSON(object: VADAudioEncoding): string;
export declare enum VADStreamEventKind {
    VAD_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    VAD_STREAM_EVENT_KIND_STARTED = 1,
    VAD_STREAM_EVENT_KIND_FRAME = 2,
    VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY = 3,
    VAD_STREAM_EVENT_KIND_STATISTICS = 4,
    VAD_STREAM_EVENT_KIND_STOPPED = 5,
    VAD_STREAM_EVENT_KIND_ERROR = 6,
    /**
     * VAD_STREAM_EVENT_KIND_BARGE_IN - Pipeline-level barge-in signal previously carried by the
     * deleted VADEventType enum. Emitted when the VAD detects speech that
     * interrupts active assistant playback; downstream pipeline typically
     * routes this through InterruptedEvent/InterruptReason as well.
     */
    VAD_STREAM_EVENT_KIND_BARGE_IN = 7,
    UNRECOGNIZED = -1
}
export declare function vADStreamEventKindFromJSON(object: any): VADStreamEventKind;
export declare function vADStreamEventKindToJSON(object: VADStreamEventKind): string;
/**
 * ---------------------------------------------------------------------------
 * Compile-time / load-time configuration for a VAD instance.
 * Sources pre-IDL:
 *   Swift  VADTypes.swift:15                (energyThreshold, sampleRate, frameLength,
 *                                            enableAutoCalibration, calibrationMultiplier)
 *   Kotlin VADTypes.kt:26                   (same five fields, defaults match Swift)
 *   Dart   vad_configuration.dart:5         (same five fields)
 *   RN     VADTypes.ts:12                   (sampleRate, frameLength, energyThreshold;
 *                                            no calibration fields)
 *   Web    VADTypes.ts —                    (no VADConfiguration; per-backend in WebSDK)
 *   C ABI  rac_vad_types.h:63 (rac_vad_config_t)
 *                                           (model_id, preferred_framework, energy_threshold,
 *                                            sample_rate, frame_length, enable_auto_calibration,
 *                                            calibration_multiplier)
 *
 * `frame_length_ms` is the canonical wire field — Swift/Kotlin/Dart/C use
 * seconds (float), but ms is more interoperable across protobuf consumers.
 * Generators must convert when binding to per-platform types.
 * ---------------------------------------------------------------------------
 */
export interface VADConfiguration {
    /**
     * Optional model id; empty when using the built-in energy VAD.
     * C ABI: model_id (rac_vad_config_t::model_id, may be NULL).
     */
    modelId: string;
    /** PCM sample rate in Hz. Default 16000 (RAC_VAD_DEFAULT_SAMPLE_RATE). */
    sampleRate: number;
    /**
     * Frame length in milliseconds. Default 100 (Swift/Kotlin/Dart store
     * 0.1 seconds; we canonicalize to ms on the wire).
     */
    frameLengthMs: number;
    /**
     * Energy threshold in [0.0, 1.0] for voice detection.
     * Recommended range 0.01–0.05; default 0.015 across SDKs.
     */
    threshold: number;
    /**
     * When true, the VAD performs ambient-noise calibration and uses the
     * result as a multiplier on the threshold (see calibration_multiplier
     * in the C ABI). Defaults to false.
     */
    enableAutoCalibration: boolean;
    /**
     * Calibration multiplier (threshold = ambient noise * multiplier).
     * Present in Swift/Kotlin/Dart configs and rac_vad_config_t.
     */
    calibrationMultiplier: number;
    /** Preferred framework for VAD. Absent = auto. */
    preferredFramework?: InferenceFramework | undefined;
    /** Optional model path for backend-specific VADs (e.g. Silero ONNX). */
    modelPath?: string | undefined;
    /**
     * Window size in samples for frame-based neural VAD backends. 0 =
     * backend/default.
     */
    windowSizeSamples: number;
    /**
     * Maximum continuous speech segment duration in milliseconds. 0 =
     * backend/default.
     */
    maxSpeechDurationMs: number;
}
/**
 * ---------------------------------------------------------------------------
 * Runtime / per-call options applied to a VAD pass.
 * Sources pre-IDL:
 *   Swift  none — Swift uses raw arguments to detectSpeech().
 *   Kotlin none — same as Swift.
 *   Dart   runanywhere_vad.dart:99          (`detectSpeech` takes raw Float32List)
 *   RN     VADTypes.ts —                    (no per-call options struct)
 *   Web    VADTypes.ts —                    (no per-call options struct)
 *   C ABI  rac_vad_types.h:123 (rac_vad_input_t)
 *                                           (audio_samples, num_samples,
 *                                            energy_threshold_override)
 *
 * We canonicalize on the energy_threshold_override + the speech-duration
 * gates that already appear as constants in rac_vad_types.h:50-51:
 *   RAC_VAD_MIN_SPEECH_DURATION_MS  = 100
 *   RAC_VAD_MIN_SILENCE_DURATION_MS = 300
 * Surfacing them as fields lets callers tune debouncing without a rebuild.
 * ---------------------------------------------------------------------------
 */
export interface VADOptions {
    /**
     * Per-call energy threshold override. Use 0 (default) to keep the
     * configured threshold. Mirrors rac_vad_input_t::energy_threshold_override
     * (which uses -1 as the sentinel; on the wire we use 0 for proto3
     * default semantics — generators emit -1 when this is unset).
     */
    threshold: number;
    /**
     * Minimum continuous speech duration (ms) before SPEECH_STARTED fires.
     * Default 100 (RAC_VAD_MIN_SPEECH_DURATION_MS).
     */
    minSpeechDurationMs: number;
    /**
     * Minimum continuous silence duration (ms) before SPEECH_ENDED fires.
     * Default 300 (RAC_VAD_MIN_SILENCE_DURATION_MS).
     */
    minSilenceDurationMs: number;
    /**
     * Maximum continuous speech duration (ms) before forcing a segment split.
     * 0 = backend/default.
     */
    maxSpeechDurationMs: number;
    /** Whether to include VADStatistics in stream events when available. */
    includeStatistics: boolean;
}
export interface VADAudioSource {
    audioData?: Uint8Array | undefined;
    adapterHandle?: string | undefined;
    encoding: VADAudioEncoding;
    sampleRate: number;
    channels: number;
    frameOffsetMs: number;
}
export interface VADProcessRequest {
    requestId: string;
    audio?: VADAudioSource | undefined;
    options?: VADOptions | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface VADProcessRequest_MetadataEntry {
    key: string;
    value: string;
}
/**
 * ---------------------------------------------------------------------------
 * Result of a single VAD pass over a chunk of PCM audio.
 * Sources pre-IDL:
 *   Swift  VADTypes.swift —                 (no struct; bool returned from detectSpeech())
 *   Kotlin VADTypes.kt:152                  (isSpeech, confidence, energyLevel,
 *                                            statistics, timestamp)
 *   Dart   dart_bridge_vad.dart:290         (isSpeech, energy, speechProbability)
 *   RN     VADTypes.ts:26                   (isSpeech, probability, startTime, endTime)
 *   Web    VADTypes.ts —                    (no VADResult; only SpeechSegment)
 *   C ABI  rac_vad_types.h:151 (rac_vad_output_t)
 *                                           (is_speech_detected, energy_level, timestamp_ms)
 *
 * Drift notes:
 *   - Kotlin's `confidence` and Dart's `speechProbability` and RN's
 *     `probability` collapse onto the canonical `confidence` field.
 *   - Kotlin/RN/C all carry timing — we encode duration_ms (length of the
 *     analyzed frame). Wall-clock timestamps belong on the carrying envelope
 *     (e.g. VoiceEvent.timestamp_us in voice_events.proto).
 * ---------------------------------------------------------------------------
 */
export interface VADResult {
    /**
     * Whether speech was detected in this frame.
     * Mirrors rac_vad_output_t::is_speech_detected.
     */
    isSpeech: boolean;
    /** Confidence / probability in [0.0, 1.0]. Backend-dependent. */
    confidence: number;
    /**
     * RMS energy level of the analyzed frame.
     * Mirrors rac_vad_output_t::energy_level.
     */
    energy: number;
    /** Length of the analyzed frame in milliseconds. */
    durationMs: number;
    /** Wall-clock timestamp for this frame/result, in milliseconds since epoch. */
    timestampMs: number;
    /** Optional detected segment start/end times, in milliseconds. 0 = unset. */
    startTimeMs: number;
    endTimeMs: number;
    /** Optional statistics snapshot and result-envelope error details. */
    statistics?: VADStatistics | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
/**
 * ---------------------------------------------------------------------------
 * Internal VAD statistics, exposed for debugging / waveform UIs.
 * Sources pre-IDL:
 *   Swift  VADTypes.swift:174               (current, threshold, ambient,
 *                                            recentAvg, recentMax)
 *   Kotlin VADTypes.kt:123                  (same five fields)
 *   Dart   none — Dart bridge does not surface statistics yet.
 *   RN     VADTypes.ts —                    (none)
 *   Web    VADTypes.ts —                    (none)
 *   C ABI  rac_vad_types.h:194 (rac_vad_statistics_t)
 *                                           (current_threshold, ambient_noise_level,
 *                                            total_speech_segments, total_speech_duration_ms,
 *                                            average_energy, peak_energy)
 *
 * We canonicalize on the Swift/Kotlin shape because it is the most widely
 * used. The richer C ABI fields (segment counts, totals) belong on a future
 * VADAnalytics message and are intentionally NOT included here.
 * ---------------------------------------------------------------------------
 */
export interface VADStatistics {
    /** Current instantaneous energy level. (Swift/Kotlin: `current`) */
    currentEnergy: number;
    /**
     * Energy threshold currently in use. (Swift/Kotlin: `threshold`;
     * C ABI: rac_vad_statistics_t::current_threshold)
     */
    currentThreshold: number;
    /**
     * Ambient noise level captured by calibration. (Swift/Kotlin: `ambient`;
     * C ABI: rac_vad_statistics_t::ambient_noise_level)
     */
    ambientLevel: number;
    /** Recent moving-window average energy. (Swift/Kotlin: `recentAvg`) */
    recentAvg: number;
    /** Recent moving-window peak energy. (Swift/Kotlin: `recentMax`) */
    recentMax: number;
    /**
     * Richer service-level counters from rac_vad_statistics_t. Zero = unset
     * for energy-only implementations.
     */
    totalSpeechSegments: number;
    totalSpeechDurationMs: number;
    averageEnergy: number;
    peakEnergy: number;
}
/**
 * ---------------------------------------------------------------------------
 * Activity transition emitted by the VAD as it watches a stream.
 * Sources pre-IDL:
 *   Swift  VADTypes.swift:235               (SpeechActivityEvent enum: started/ended)
 *   Kotlin VADTypes.kt:171                  (SpeechActivityEvent enum: STARTED/ENDED)
 *   Dart   runanywhere_vad.dart:28          (SpeechActivityEvent enum: started/ended)
 *   RN     VADTypes.ts:43                   ('started' | 'ended' string union)
 *   Web    VADTypes.ts:8                    (SpeechActivity enum: Started/Ended/Ongoing)
 *   C ABI  rac_vad_types.h:107 (rac_speech_activity_t)
 *                                           (RAC_SPEECH_STARTED/ENDED/ONGOING)
 *
 * Distinct from voice_events.proto's `VADEvent`, which carries the broader
 * pipeline-level taxonomy (BARGE_IN, END_OF_UTTERANCE, etc) via
 * `VADStreamEventKind`. `SpeechActivityEvent` here is the narrow
 * component-level transition.
 * ---------------------------------------------------------------------------
 */
export interface SpeechActivityEvent {
    /** Which transition happened. */
    eventType: SpeechActivityKind;
    /**
     * Wall-clock time of the transition, in milliseconds since epoch.
     * Aligns with rac_vad_output_t::timestamp_ms.
     */
    timestampMs: number;
    /**
     * Optional duration of the speech / silence that triggered this event,
     * in milliseconds. Set on SPEECH_ENDED to communicate the just-finished
     * utterance length; left zero on SPEECH_STARTED.
     */
    durationMs: number;
    confidence: number;
    result?: VADResult | undefined;
    segmentId?: string | undefined;
}
export interface VADStreamEvent {
    seq: number;
    timestampUs: number;
    requestId: string;
    kind: VADStreamEventKind;
    result?: VADResult | undefined;
    activity?: SpeechActivityEvent | undefined;
    statistics?: VADStatistics | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface VADServiceState {
    isReady: boolean;
    isSpeechActive: boolean;
    energyThreshold: number;
    sampleRate: number;
    frameLengthMs: number;
    currentModel?: string | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
export declare const VADConfiguration: MessageFns<VADConfiguration>;
export declare const VADOptions: MessageFns<VADOptions>;
export declare const VADAudioSource: MessageFns<VADAudioSource>;
export declare const VADProcessRequest: MessageFns<VADProcessRequest>;
export declare const VADProcessRequest_MetadataEntry: MessageFns<VADProcessRequest_MetadataEntry>;
export declare const VADResult: MessageFns<VADResult>;
export declare const VADStatistics: MessageFns<VADStatistics>;
export declare const SpeechActivityEvent: MessageFns<SpeechActivityEvent>;
export declare const VADStreamEvent: MessageFns<VADStreamEvent>;
export declare const VADServiceState: MessageFns<VADServiceState>;
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
