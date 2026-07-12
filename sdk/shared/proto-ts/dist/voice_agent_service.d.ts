import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { EventCategory } from "./component_types";
import { ErrorSeverity } from "./errors";
import { TTSOptions } from "./tts_options";
import { AudioEncoding, VoiceAgentComponentStates } from "./voice_events";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Empty request type — the voice agent already has its config set via
 * `rac_voice_agent_init()` at handle creation time. The Stream rpc just
 * opens a new event subscription on an existing handle.
 */
export interface VoiceAgentRequest {
    /**
     * Optional: filter the stream to only certain VoiceEvent.payload arms
     * (e.g. "user_said,assistant_token"). Empty = all events.
     */
    eventFilter: string;
    sessionId: string;
    categories: EventCategory[];
    minSeverity: ErrorSeverity;
    replayFromSeq: number;
    includeAudio: boolean;
}
/**
 * ---------------------------------------------------------------------------
 * One-shot voice-turn result.
 *
 * Mirrors Swift `VoiceAgentResult`, Kotlin `VoiceAgentResult`, RN
 * `VoiceTurnResult`, Web `VoiceAgentResult`, Flutter (TBD), and the C ABI
 * `rac_voice_agent_result_t` (rac/features/voice_agent/rac_voice_agent.h).
 * Returned by the `processVoiceTurn` ergonomic API where a single audio
 * blob produces transcription + assistant response + synthesized audio in
 * one call (as opposed to the streaming path served by the Stream rpc).
 * ---------------------------------------------------------------------------
 */
export interface VoiceAgentResult {
    /** Whether the input audio passed VAD's speech-detected check. */
    speechDetected: boolean;
    /** Transcribed text from STT. Unset when speech_detected=false. */
    transcription?: string | undefined;
    /**
     * Generated assistant response text from the LLM. Unset when STT
     * produced no transcription or LLM was skipped.
     */
    assistantResponse?: string | undefined;
    /**
     * Thinking content extracted from `<think>...</think>` tags
     * (qwen3, deepseek-r1). Unset when the active LLM does not emit
     * a chain-of-thought trace.
     */
    thinkingContent?: string | undefined;
    /**
     * Synthesized audio data from TTS. Encoding follows AudioFrameEvent
     * conventions (typically PCM-F32-LE, sample rate per voice). Unset
     * when TTS was skipped or auto_play_tts=false in VoiceSessionConfig.
     */
    synthesizedAudio?: Uint8Array | undefined;
    /**
     * Component states captured at the end of the turn — useful for UIs
     * surfacing readiness / partial-failure breakdowns alongside the
     * final result. Unset when the caller does not ask for it.
     */
    finalState?: VoiceAgentComponentStates | undefined;
    /**
     * Audio metadata for synthesized_audio. 0/UNSPECIFIED = backend default
     * or unknown.
     */
    synthesizedAudioSampleRateHz: number;
    synthesizedAudioChannels: number;
    synthesizedAudioEncoding: AudioEncoding;
    sessionId: string;
    turnId: string;
    sttTimeMs: number;
    llmTimeMs: number;
    ttsTimeMs: number;
    totalTimeMs: number;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface VoiceAgentTurnRequest {
    requestId: string;
    sessionId: string;
    audioData: Uint8Array;
    sampleRateHz: number;
    channels: number;
    encoding: AudioEncoding;
    sessionConfig?: VoiceSessionConfig | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface VoiceAgentTurnRequest_MetadataEntry {
    key: string;
    value: string;
}
/**
 * ---------------------------------------------------------------------------
 * Voice session behavior configuration.
 *
 * Mirrors Swift `VoiceSessionConfig` and Kotlin `VoiceSessionConfig`.
 * Controls runtime behavior of the voice agent's session loop — silence
 * timing, speech threshold, auto-TTS playback, continuous mode, and
 * LLM thinking-mode toggle.
 * ---------------------------------------------------------------------------
 */
export interface VoiceSessionConfig {
    /**
     * Silence duration (milliseconds) before processing the speech
     * buffer. Default per Swift/Kotlin: 1500 ms.
     */
    silenceDurationMs: number;
    /**
     * Minimum audio level to detect speech (0.0 - 1.0). Default per
     * Swift/Kotlin: 0.1.
     */
    speechThreshold: number;
    /** Whether to auto-play TTS response after synthesis. Default true. */
    autoPlayTts: boolean;
    /** Whether to auto-resume listening after TTS playback. Default true. */
    continuousMode: boolean;
    /**
     * Whether thinking mode is enabled for the LLM (qwen3, deepseek-r1).
     * Default false.
     */
    thinkingModeEnabled: boolean;
    /** Optional per-turn LLM max token limit. 0 = LLM/default. */
    maxTokens: number;
    /** Maximum recording duration before forcing an end-of-turn. 0 = default. */
    maxRecordingDurationMs: number;
    /** Optional language/voice hints passed to STT/TTS adapters. */
    languageCode?: string | undefined;
    voiceId?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Audio pipeline state-manager configuration.
 *
 * Mirrors rac_audio_pipeline_config_t and the Swift state-manager knobs used
 * to prevent microphone/TTS feedback loops.
 * ---------------------------------------------------------------------------
 */
export interface AudioPipelineConfig {
    cooldownDurationMs: number;
    strictTransitions: boolean;
    maxTtsDurationMs: number;
}
/**
 * ---------------------------------------------------------------------------
 * Aggregated voice-agent compose configuration.
 *
 * Mirrors the C ABI `rac_voice_agent_config_t` and Swift
 * `VoiceAgentConfiguration`. The existing `runanywhere.v1.VoiceAgentConfig`
 * (idl/solutions.proto) is kept frozen for the SolutionConfig oneof — this
 * new message provides the fine-grained sub-component view consumed by the
 * `rac_voice_agent_initialize()` C entry-point.
 *
 * Each sub-config string field uses a "model_id" naming convention; the
 * runtime resolves IDs against the model registry. An empty string means
 * "use the currently loaded model/voice for that capability".
 * ---------------------------------------------------------------------------
 */
export interface VoiceAgentComposeConfig {
    /**
     * -------------------------------------------------------------------
     * STT sub-config (mirrors rac_voice_agent_stt_config_t).
     * -------------------------------------------------------------------
     */
    sttModelPath?: string | undefined;
    sttModelId?: string | undefined;
    sttModelName?: string | undefined;
    /**
     * -------------------------------------------------------------------
     * LLM sub-config (mirrors rac_voice_agent_llm_config_t).
     * -------------------------------------------------------------------
     */
    llmModelPath?: string | undefined;
    llmModelId?: string | undefined;
    llmModelName?: string | undefined;
    /**
     * -------------------------------------------------------------------
     * TTS sub-config (mirrors rac_voice_agent_tts_config_t).
     * -------------------------------------------------------------------
     */
    ttsVoicePath?: string | undefined;
    ttsVoiceId?: string | undefined;
    ttsVoiceName?: string | undefined;
    /**
     * -------------------------------------------------------------------
     * VAD sub-config (mirrors rac_voice_agent_vad_config_t).
     * -------------------------------------------------------------------
     */
    vadSampleRate: number;
    /** default 0.1 */
    vadFrameLength: number;
    /** default 0.005 */
    vadEnergyThreshold: number;
    /**
     * -------------------------------------------------------------------
     * Session-behavior sub-config. Optional so the C ABI can be invoked
     * without runtime-behavior overrides (engine defaults applied).
     * -------------------------------------------------------------------
     */
    sessionConfig?: VoiceSessionConfig | undefined;
    /**
     * Audio state-machine behavior. Optional so defaults can be applied by
     * the native voice-agent implementation.
     */
    audioPipelineConfig?: AudioPipelineConfig | undefined;
    /** Correlation and defaults for event streams and one-shot turn APIs. */
    sessionId?: string | undefined;
    defaultLanguageCode?: string | undefined;
}
/** Helper-level proto requests for voice-agent sub-components. */
export interface VoiceAgentTranscribeProtoRequest {
    audioData: Uint8Array;
    sessionId: string;
    sampleRate: number;
    languageHint: string;
    channels: number;
    encoding: AudioEncoding;
}
export interface VoiceAgentSynthesizeSpeechProtoRequest {
    text: string;
    sessionId: string;
    options?: TTSOptions | undefined;
}
export declare const VoiceAgentRequest: MessageFns<VoiceAgentRequest>;
export declare const VoiceAgentResult: MessageFns<VoiceAgentResult>;
export declare const VoiceAgentTurnRequest: MessageFns<VoiceAgentTurnRequest>;
export declare const VoiceAgentTurnRequest_MetadataEntry: MessageFns<VoiceAgentTurnRequest_MetadataEntry>;
export declare const VoiceSessionConfig: MessageFns<VoiceSessionConfig>;
export declare const AudioPipelineConfig: MessageFns<AudioPipelineConfig>;
export declare const VoiceAgentComposeConfig: MessageFns<VoiceAgentComposeConfig>;
export declare const VoiceAgentTranscribeProtoRequest: MessageFns<VoiceAgentTranscribeProtoRequest>;
export declare const VoiceAgentSynthesizeSpeechProtoRequest: MessageFns<VoiceAgentSynthesizeSpeechProtoRequest>;
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
