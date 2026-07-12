import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * SolutionType — discriminator for the kind of solution backing a
 * `SolutionConfig` / `SolutionHandle`. Mirrors the `SolutionConfig.config`
 * oneof arms so frontends can switch on a single enum value rather than
 * inspecting the oneof shape.
 * ---------------------------------------------------------------------------
 */
export declare enum SolutionType {
    SOLUTION_TYPE_UNSPECIFIED = 0,
    SOLUTION_TYPE_VOICE_AGENT = 1,
    SOLUTION_TYPE_RAG = 2,
    SOLUTION_TYPE_TIME_SERIES = 4,
    SOLUTION_TYPE_AGENT_LOOP = 5,
    UNRECOGNIZED = -1
}
export declare function solutionTypeFromJSON(object: any): SolutionType;
export declare function solutionTypeToJSON(object: SolutionType): string;
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
    agentLoop?: AgentLoopConfig | undefined;
    timeSeries?: TimeSeriesConfig | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * SolutionHandle — opaque, serialisable descriptor for a started solution.
 *
 * The native side owns a `rac_solution_handle_t`; this message is the
 * language-agnostic shape that frontends (Swift `SolutionHandle` class,
 * Kotlin/Flutter/RN/Web equivalents) carry across the C ABI to identify
 * the underlying instance. Lifecycle verbs (start/stop/cancel/feed/destroy)
 * are issued against the C handle keyed by `handle_id`.
 * ---------------------------------------------------------------------------
 */
export interface SolutionHandle {
    /**
     * Stable, opaque identifier minted by the core for this solution
     * instance. Used as the lookup key for lifecycle calls.
     */
    handleId: string;
    /**
     * String discriminator for the solution kind, e.g. "voice_agent",
     * "rag", "time_series", "agent_loop". Free-form for
     * forward-compat with future solutions; canonical values match the
     * `SolutionType` enum names lower-cased.
     */
    solutionType: string;
    /** Wall-clock creation timestamp (ms since Unix epoch). */
    createdAtMs: number;
    /**
     * Optional engine-specific state string (e.g. "created", "running",
     * "stopped"). Empty when the host hasn't surfaced state.
     */
    state?: string | undefined;
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
    /**
     * pass3-syn-025/030: explicit TTS voice id for multi-voice TTS engines
     * (Piper, eSpeak-NG, Sherpa-ONNX-TTS multi-voice). When unset, callers
     * fall back to using tts_model_id as the voice id — correct for
     * single-voice engines, wrong for multi-voice. Aligns the caller-facing
     * VoiceAgentConfig with the commons-facing RAVoiceAgentComposeConfig
     * (voice_agent_service.proto:214) which already exposes tts_voice_id.
     */
    ttsVoiceId: string;
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
    enableBargeIn?: boolean | undefined;
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
    /**
     * Optional explicit solution-kind tag. Redundant with the `SolutionConfig`
     * oneof arm; provided so callers that pass this message standalone (or
     * log it) can read a single discriminator. Defaults to UNSPECIFIED.
     */
    typeKind?: SolutionType | undefined;
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
    /** Optional explicit solution-kind tag. See `SolutionType`. */
    typeKind?: SolutionType | undefined;
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
    /** Optional explicit solution-kind tag. See `SolutionType`. */
    typeKind?: SolutionType | undefined;
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
    /** Optional explicit solution-kind tag. See `SolutionType`. */
    typeKind?: SolutionType | undefined;
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
