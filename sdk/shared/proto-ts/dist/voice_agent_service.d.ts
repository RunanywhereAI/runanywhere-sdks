import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { EventCategory } from "./component_types";
import { ErrorSeverity, SDKError } from "./errors";
import { LLMGenerationOptions } from "./llm_options";
import { AudioEncoding } from "./model_types";
import { TTSOptions } from "./tts_options";
import { VADConfiguration } from "./vad_options";
import { VoiceAgentComponentStates } from "./voice_events";
export declare const protobufPackage = "runanywhere.v1";
/** Subscription parameters for the agent's event stream. */
export interface VoiceAgentRequest {
    eventFilter: string;
    sessionId: string;
    categories: EventCategory[];
    minSeverity: ErrorSeverity;
    replayFromSeq: number;
    includeAudio: boolean;
}
export interface VoiceAgentResult {
    speechDetected: boolean;
    transcription?: string | undefined;
    assistantResponse?: string | undefined;
    thinkingContent?: string | undefined;
    synthesizedAudio?: Uint8Array | undefined;
    finalState?: VoiceAgentComponentStates | undefined;
    /** Required to interpret synthesized_audio. */
    synthesizedAudioSampleRateHz: number;
    synthesizedAudioChannels: number;
    synthesizedAudioEncoding: AudioEncoding;
    sessionId: string;
    turnId: string;
    /** Per-stage timings, then the wall-clock total. */
    sttTimeMs: number;
    llmTimeMs: number;
    ttsTimeMs: number;
    totalTimeMs: number;
    error?: SDKError | undefined;
}
/** One-shot turn: audio in, transcription plus response plus audio out. */
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
export interface VoiceAgentAudioFrame {
    audioData: Uint8Array;
    sampleRate: number;
    channels: number;
    encoding: AudioEncoding;
    isFinal: boolean;
}
/**
 * Commons reads silence_duration_ms and max_tokens. The remaining fields are
 * declared but not consumed by the C++ voice agent.
 */
export interface VoiceSessionConfig {
    silenceDurationMs: number;
    speechThreshold: number;
    autoPlayTts: boolean;
    continuousMode: boolean;
    thinkingModeEnabled: boolean;
    maxTokens: number;
    maxRecordingDurationMs: number;
    languageCode?: string | undefined;
    voiceId?: string | undefined;
}
export interface AudioPipelineConfig {
    cooldownDurationMs: number;
    strictTransitions: boolean;
    maxTtsDurationMs: number;
}
/**
 * Each component takes a path, an id, or a name; commons resolves whichever is
 * present through the model registry.
 */
export interface VoiceAgentComposeConfig {
    sttModelPath?: string | undefined;
    sttModelId?: string | undefined;
    sttModelName?: string | undefined;
    llmModelPath?: string | undefined;
    llmModelId?: string | undefined;
    llmModelName?: string | undefined;
    ttsVoicePath?: string | undefined;
    ttsVoiceId?: string | undefined;
    ttsVoiceName?: string | undefined;
    vadConfig?: VADConfiguration | undefined;
    llmGeneration?: LLMGenerationOptions | undefined;
    sessionConfig?: VoiceSessionConfig | undefined;
    audioPipelineConfig?: AudioPipelineConfig | undefined;
    sessionId?: string | undefined;
    defaultLanguageCode?: string | undefined;
}
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
export declare const VoiceAgentAudioFrame: MessageFns<VoiceAgentAudioFrame>;
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
