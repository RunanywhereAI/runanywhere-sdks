import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { LLMGenerationOptions } from "./llm_options";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Frontends switch on the SolutionConfig oneof case. This enum exists only
 * for logs and handles, and its numbers now match the oneof tags.
 */
export declare enum SolutionType {
    SOLUTION_TYPE_UNSPECIFIED = 0,
    /** SOLUTION_TYPE_VOICE_AGENT - SolutionConfig.voice_agent = 1 */
    SOLUTION_TYPE_VOICE_AGENT = 1,
    /** SOLUTION_TYPE_RAG - SolutionConfig.rag         = 2 */
    SOLUTION_TYPE_RAG = 2,
    /** SOLUTION_TYPE_AGENT_LOOP - SolutionConfig.agent_loop  = 4 */
    SOLUTION_TYPE_AGENT_LOOP = 4,
    /** SOLUTION_TYPE_TIME_SERIES - SolutionConfig.time_series = 5 */
    SOLUTION_TYPE_TIME_SERIES = 5,
    UNRECOGNIZED = -1
}
export declare function solutionTypeFromJSON(object: any): SolutionType;
export declare function solutionTypeToJSON(object: SolutionType): string;
export declare enum AudioSource {
    AUDIO_SOURCE_UNSPECIFIED = 0,
    AUDIO_SOURCE_MICROPHONE = 1,
    AUDIO_SOURCE_FILE = 2,
    /** AUDIO_SOURCE_CALLBACK - Frontend feeds frames through the C ABI */
    AUDIO_SOURCE_CALLBACK = 3,
    UNRECOGNIZED = -1
}
export declare function audioSourceFromJSON(object: any): AudioSource;
export declare function audioSourceToJSON(object: AudioSource): string;
export declare enum VectorStore {
    VECTOR_STORE_UNSPECIFIED = 0,
    /** VECTOR_STORE_USEARCH - in-process HNSW */
    VECTOR_STORE_USEARCH = 1,
    /** VECTOR_STORE_PGVECTOR - server deployments only, no on-device path */
    VECTOR_STORE_PGVECTOR = 2,
    UNRECOGNIZED = -1
}
export declare function vectorStoreFromJSON(object: any): VectorStore;
export declare function vectorStoreToJSON(object: VectorStore): string;
export interface SolutionConfig {
    voiceAgent?: VoiceAgentConfig | undefined;
    rag?: RAGConfig | undefined;
    agentLoop?: AgentLoopConfig | undefined;
    timeSeries?: TimeSeriesConfig | undefined;
}
export interface SolutionHandle {
    handleId: string;
    solutionType: string;
    createdAtMs: number;
    /** Engine-specific, e.g. "running" or "stopped". */
    state?: string | undefined;
}
export interface VoiceAgentConfig {
    llmModelId: string;
    sttModelId: string;
    ttsModelId: string;
    vadModelId: string;
    ttsVoiceId: string;
    sampleRateHz: number;
    chunkMs: number;
    /** audio_file_path applies when audio_source is FILE. */
    audioSource: AudioSource;
    audioFilePath: string;
    /** Unset means enabled. */
    enableBargeIn?: boolean | undefined;
    bargeInThresholdMs: number;
    generation?: LLMGenerationOptions | undefined;
    maxContextTokens: number;
    /** Emit partial transcripts as non-final user-said events. */
    emitPartials: boolean;
}
export interface RAGConfig {
    embedModelId: string;
    rerankModelId: string;
    llmModelId: string;
    vectorStore: VectorStore;
    vectorStorePath: string;
    /** Retrieve this many candidates, then keep this many after reranking. */
    retrieveK: number;
    rerankTop: number;
    /** BM25 term-saturation and length-normalization parameters. */
    bm25K1: number;
    bm25B: number;
    /** Reciprocal-rank-fusion smoothing constant. */
    rrfK: number;
    promptTemplate: string;
}
export interface AgentLoopConfig {
    llmModelId: string;
    systemPrompt: string;
    tools: ToolSpec[];
    maxIterations: number;
    maxContextTokens: number;
}
export interface ToolSpec {
    name: string;
    description: string;
    /** OpenAI-compatible parameters schema. */
    jsonSchema: string;
}
export interface TimeSeriesConfig {
    anomalyModelId: string;
    llmModelId: string;
    /** Samples per window, and how far the window advances each step. */
    windowSize: number;
    stride: number;
    anomalyThreshold: number;
}
export declare const SolutionConfig: MessageFns<SolutionConfig>;
export declare const SolutionHandle: MessageFns<SolutionHandle>;
export declare const VoiceAgentConfig: MessageFns<VoiceAgentConfig>;
export declare const RAGConfig: MessageFns<RAGConfig>;
export declare const AgentLoopConfig: MessageFns<AgentLoopConfig>;
export declare const ToolSpec: MessageFns<ToolSpec>;
export declare const TimeSeriesConfig: MessageFns<TimeSeriesConfig>;
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
