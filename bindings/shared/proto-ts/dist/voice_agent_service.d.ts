import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { LLMGenerationOptions } from "./llm_options";
import { AudioEncoding } from "./model_types";
import { TTSOptions } from "./tts_options";
import { VADConfiguration } from "./vad_options";
import { VoiceAgentComponentStates } from "./voice_events";
export declare const protobufPackage = "runanywhere.v1";
export interface VoiceAgentResult {
    speechDetected: boolean;
    transcription?: string | undefined;
    assistantResponse?: string | undefined;
    thinkingContent?: string | undefined;
    synthesizedAudio?: Uint8Array | undefined;
    finalState?: VoiceAgentComponentStates | undefined;
}
/**
 * Turn detection. Field names, units and semantics follow OpenAI Realtime
 * `session.audio.input.turn_detection`.
 */
export interface TurnDetection {
    type: TurnDetection_Type;
    /**
     * Activation threshold, 0..1 — the same normalized scale as
     * VADConfiguration.activation_threshold, and the value that wins on the
     * voice-agent path when both are set. Raise it for noisy rooms.
     * 0 means unset; commons applies 0.5.
     */
    threshold: number;
    /**
     * Silence after speech before the turn is closed.
     * 0 means unset; commons applies 500.
     */
    silenceDurationMs: number;
    /**
     * Audio retained before speech onset so the first word is not clipped.
     * 0 means unset; commons applies 300.
     */
    prefixPaddingMs: number;
    /**
     * Unset means true. False makes the agent finish its sentence
     * (kiosk, scripted disclosure).
     */
    interruptResponse?: boolean | undefined;
    /** Unset means true. False means the app drives replies itself via say(). */
    createResponse?: boolean | undefined;
}
export declare enum TurnDetection_Type {
    /** TURN_DETECTION_TYPE_UNSPECIFIED - treated as VAD */
    TURN_DETECTION_TYPE_UNSPECIFIED = 0,
    /** TURN_DETECTION_TYPE_VAD - the VAD decides end-of-turn */
    TURN_DETECTION_TYPE_VAD = 1,
    /** TURN_DETECTION_TYPE_MANUAL - push-to-talk: app closes the turn */
    TURN_DETECTION_TYPE_MANUAL = 2,
    UNRECOGNIZED = -1
}
export declare function turnDetection_TypeFromJSON(object: any): TurnDetection_Type;
export declare function turnDetection_TypeToJSON(object: TurnDetection_Type): string;
/**
 * One-shot turn: audio in, transcription plus response plus audio out.
 *
 * audio_data must be PCM signed 16-bit little-endian, mono, 16 kHz. Commons
 * rejects any other encoding, but it does NOT check or resample the sample
 * rate or the channel count — feeding anything else yields a wrong transcript
 * rather than an error.
 */
export interface VoiceAgentTurnRequest {
    requestId: string;
    sessionId: string;
    audioData: Uint8Array;
    /**
     * BCP-47 STT language for this turn only. Overrides
     * VoiceAgentComposeConfig.language. Unset means the session language, or
     * model auto-detection when that is unset too.
     */
    language?: string | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface VoiceAgentTurnRequest_MetadataEntry {
    key: string;
    value: string;
}
/** Streamed capture frame. Same fixed input contract as VoiceAgentTurnRequest. */
export interface VoiceAgentAudioFrame {
    audioData: Uint8Array;
    sampleRateHz: number;
    channels: number;
    /**
     * Commons accepts AUDIO_ENCODING_UNSPECIFIED and AUDIO_ENCODING_PCM_S16_LE
     * and rejects every other value.
     */
    encoding: AudioEncoding;
    isFinal: boolean;
}
/**
 * Each component takes a path or an id; commons resolves the id through the
 * model registry.
 */
export interface VoiceAgentComposeConfig {
    /**
     * Normal choice is the id (resolved via the model registry); path is the
     * escape hatch for an artifact you staged yourself.
     */
    sttModelPath?: string | undefined;
    sttModelId?: string | undefined;
    llmModelPath?: string | undefined;
    llmModelId?: string | undefined;
    ttsVoicePath?: string | undefined;
    ttsVoiceId?: string | undefined;
    vadConfig?: VADConfiguration | undefined;
    llmGeneration?: LLMGenerationOptions | undefined;
    /**
     * System prompt for the agent. Governs persona AND spoken delivery
     * ("talk quickly", "sound warm"), not just content. Same name and role as
     * OpenAI Realtime `session.instructions`. Unset uses the commons voice
     * default (short, spoken, no markdown).
     *
     * This is the only system prompt the voice path reads:
     * llm_generation.system_prompt is IGNORED here.
     */
    instructions?: string | undefined;
    turnDetection?: TurnDetection | undefined;
    /**
     * BCP-47 STT language for the whole session. One spelling across this
     * domain and stt_options.proto. Unset means the model auto-detects.
     * Per-turn override: VoiceAgentTurnRequest.language.
     */
    language?: string | undefined;
}
export interface VoiceAgentTranscribeProtoRequest {
    audioData: Uint8Array;
    sessionId: string;
    /** BCP-47. Empty means auto-detect. */
    language: string;
}
export interface VoiceAgentSynthesizeSpeechProtoRequest {
    text: string;
    sessionId: string;
    options?: TTSOptions | undefined;
}
export declare const VoiceAgentResult: MessageFns<VoiceAgentResult>;
export declare const TurnDetection: MessageFns<TurnDetection>;
export declare const VoiceAgentTurnRequest: MessageFns<VoiceAgentTurnRequest>;
export declare const VoiceAgentTurnRequest_MetadataEntry: MessageFns<VoiceAgentTurnRequest_MetadataEntry>;
export declare const VoiceAgentAudioFrame: MessageFns<VoiceAgentAudioFrame>;
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
