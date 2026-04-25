import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
export declare enum AudioSource {
    AUDIO_SOURCE_UNSPECIFIED = 0,
    /** AUDIO_SOURCE_MICROPHONE - Platform mic (default) */
    AUDIO_SOURCE_MICROPHONE = 1,
    /** AUDIO_SOURCE_FILE - Path supplied in audio_file_path */
    AUDIO_SOURCE_FILE = 2,
    /** AUDIO_SOURCE_CALLBACK - Frontend feeds frames via C ABI */
    AUDIO_SOURCE_CALLBACK = 3,
    UNRECOGNIZED = -1
}
export declare function audioSourceFromJSON(object: any): AudioSource;
export declare function audioSourceToJSON(object: AudioSource): string;
export declare enum VectorStore {
    VECTOR_STORE_UNSPECIFIED = 0,
    /** VECTOR_STORE_USEARCH - default, in-process HNSW */
    VECTOR_STORE_USEARCH = 1,
    /** VECTOR_STORE_PGVECTOR - remote, server deployments only */
    VECTOR_STORE_PGVECTOR = 2,
    UNRECOGNIZED = -1
}
export declare function vectorStoreFromJSON(object: any): VectorStore;
export declare function vectorStoreToJSON(object: VectorStore): string;
/** Top-level union dispatched to the matching solution loader. */
export interface SolutionConfig {
    voiceAgent?: VoiceAgentConfig | undefined;
    rag?: RAGConfig | undefined;
    wakeWord?: WakeWordConfig | undefined;
    agentLoop?: AgentLoopConfig | undefined;
    timeSeries?: TimeSeriesConfig | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * VoiceAgent — the canonical streaming voice AI loop.
 * ---------------------------------------------------------------------------
 */
export interface VoiceAgentConfig {
    /** Model identifiers — resolved against the model registry. */
    llmModelId: string;
    /** e.g. "whisper-base" */
    sttModelId: string;
    /** e.g. "kokoro" */
    ttsModelId: string;
    /** e.g. "silero-v5" */
    vadModelId: string;
    /** Audio configuration. */
    sampleRateHz: number;
    /** default 20 */
    chunkMs: number;
    audioSource: AudioSource;
    /**
     * Absolute path to an audio file. Required when `audio_source` is
     * `AUDIO_SOURCE_FILE`; ignored for MICROPHONE / CALLBACK sources.
     */
    audioFilePath: string;
    /** Barge-in behavior. */
    enableBargeIn: boolean;
    /** default 200 */
    bargeInThresholdMs: number;
    /** LLM behavior. */
    systemPrompt: string;
    maxContextTokens: number;
    temperature: number;
    /** Emit partial transcripts as UserSaidEvent{is_final=false}. */
    emitPartials: boolean;
    /** Emit thought tokens (qwen3, deepseek-r1) separately from answer tokens. */
    emitThoughts: boolean;
}
/**
 * ---------------------------------------------------------------------------
 * RAG — retrieve → rerank → prompt → LLM.
 * ---------------------------------------------------------------------------
 */
export interface RAGConfig {
    /** e.g. "bge-small-en-v1.5" */
    embedModelId: string;
    /** e.g. "bge-reranker-v2-m3" */
    rerankModelId: string;
    llmModelId: string;
    /** Vector store — USearch (in-process HNSW, default) or remote pgvector. */
    vectorStore: VectorStore;
    /** Local path for USearch index */
    vectorStorePath: string;
    /** default 24 */
    retrieveK: number;
    /** default 6 */
    rerankTop: number;
    /** BM25 parameters. */
    bm25K1: number;
    /** default 0.75 */
    bm25B: number;
    /** RRF fusion parameter. */
    rrfK: number;
    /** Prompt template. Supports {{context}} and {{query}} placeholders. */
    promptTemplate: string;
}
/**
 * ---------------------------------------------------------------------------
 * Wake word — always-on listener that emits a pulse on keyword detection.
 * ---------------------------------------------------------------------------
 */
export interface WakeWordConfig {
    /** e.g. "hey-mycroft-v1", "kws-zipformer-gigaspeech" */
    modelId: string;
    /** Phrase to detect */
    keyword: string;
    /** 0.0..1.0, engine-dependent */
    threshold: number;
    /** How much audio to emit before the trigger */
    preRollMs: number;
    /** default 16000 */
    sampleRateHz: number;
}
/**
 * ---------------------------------------------------------------------------
 * Agent loop — multi-turn LLM with tool calling.
 * ---------------------------------------------------------------------------
 */
export interface AgentLoopConfig {
    llmModelId: string;
    systemPrompt: string;
    tools: ToolSpec[];
    /** default 10 */
    maxIterations: number;
    maxContextTokens: number;
}
export interface ToolSpec {
    name: string;
    description: string;
    /** Parameters schema, OpenAI-compatible */
    jsonSchema: string;
}
/**
 * ---------------------------------------------------------------------------
 * Time series — window + anomaly_detect + generate_text.
 * ---------------------------------------------------------------------------
 */
export interface TimeSeriesConfig {
    anomalyModelId: string;
    llmModelId: string;
    /** Samples per window */
    windowSize: number;
    stride: number;
    anomalyThreshold: number;
}
export declare const SolutionConfig: {
    encode(message: SolutionConfig, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): SolutionConfig;
    fromJSON(object: any): SolutionConfig;
    toJSON(message: SolutionConfig): unknown;
    create<I extends Exact<DeepPartial<SolutionConfig>, I>>(base?: I): SolutionConfig;
    fromPartial<I extends Exact<DeepPartial<SolutionConfig>, I>>(object: I): SolutionConfig;
};
export declare const VoiceAgentConfig: {
    encode(message: VoiceAgentConfig, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): VoiceAgentConfig;
    fromJSON(object: any): VoiceAgentConfig;
    toJSON(message: VoiceAgentConfig): unknown;
    create<I extends Exact<DeepPartial<VoiceAgentConfig>, I>>(base?: I): VoiceAgentConfig;
    fromPartial<I extends Exact<DeepPartial<VoiceAgentConfig>, I>>(object: I): VoiceAgentConfig;
};
export declare const RAGConfig: {
    encode(message: RAGConfig, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGConfig;
    fromJSON(object: any): RAGConfig;
    toJSON(message: RAGConfig): unknown;
    create<I extends Exact<DeepPartial<RAGConfig>, I>>(base?: I): RAGConfig;
    fromPartial<I extends Exact<DeepPartial<RAGConfig>, I>>(object: I): RAGConfig;
};
export declare const WakeWordConfig: {
    encode(message: WakeWordConfig, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): WakeWordConfig;
    fromJSON(object: any): WakeWordConfig;
    toJSON(message: WakeWordConfig): unknown;
    create<I extends Exact<DeepPartial<WakeWordConfig>, I>>(base?: I): WakeWordConfig;
    fromPartial<I extends Exact<DeepPartial<WakeWordConfig>, I>>(object: I): WakeWordConfig;
};
export declare const AgentLoopConfig: {
    encode(message: AgentLoopConfig, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): AgentLoopConfig;
    fromJSON(object: any): AgentLoopConfig;
    toJSON(message: AgentLoopConfig): unknown;
    create<I extends Exact<DeepPartial<AgentLoopConfig>, I>>(base?: I): AgentLoopConfig;
    fromPartial<I extends Exact<DeepPartial<AgentLoopConfig>, I>>(object: I): AgentLoopConfig;
};
export declare const ToolSpec: {
    encode(message: ToolSpec, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolSpec;
    fromJSON(object: any): ToolSpec;
    toJSON(message: ToolSpec): unknown;
    create<I extends Exact<DeepPartial<ToolSpec>, I>>(base?: I): ToolSpec;
    fromPartial<I extends Exact<DeepPartial<ToolSpec>, I>>(object: I): ToolSpec;
};
export declare const TimeSeriesConfig: {
    encode(message: TimeSeriesConfig, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TimeSeriesConfig;
    fromJSON(object: any): TimeSeriesConfig;
    toJSON(message: TimeSeriesConfig): unknown;
    create<I extends Exact<DeepPartial<TimeSeriesConfig>, I>>(base?: I): TimeSeriesConfig;
    fromPartial<I extends Exact<DeepPartial<TimeSeriesConfig>, I>>(object: I): TimeSeriesConfig;
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
//# sourceMappingURL=solutions.d.ts.map