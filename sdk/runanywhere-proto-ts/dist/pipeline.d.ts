import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
export declare enum DeviceAffinity {
    DEVICE_AFFINITY_UNSPECIFIED = 0,
    DEVICE_AFFINITY_ANY = 1,
    DEVICE_AFFINITY_CPU = 2,
    DEVICE_AFFINITY_GPU = 3,
    /** DEVICE_AFFINITY_ANE - Apple Neural Engine */
    DEVICE_AFFINITY_ANE = 4,
    UNRECOGNIZED = -1
}
export declare function deviceAffinityFromJSON(object: any): DeviceAffinity;
export declare function deviceAffinityToJSON(object: DeviceAffinity): string;
export declare enum EdgePolicy {
    EDGE_POLICY_UNSPECIFIED = 0,
    /** EDGE_POLICY_BLOCK - Producer blocks when channel is full (default, safest). */
    EDGE_POLICY_BLOCK = 1,
    /** EDGE_POLICY_DROP_OLDEST - Oldest item is dropped when channel is full (audio routing only). */
    EDGE_POLICY_DROP_OLDEST = 2,
    /** EDGE_POLICY_DROP_NEWEST - Newest item is dropped when channel is full (pager coalescing). */
    EDGE_POLICY_DROP_NEWEST = 3,
    UNRECOGNIZED = -1
}
export declare function edgePolicyFromJSON(object: any): EdgePolicy;
export declare function edgePolicyToJSON(object: EdgePolicy): string;
/**
 * A pipeline is a labelled DAG of operators connected by typed edges. There
 * are no cycles. Every input edge has a resolvable producer; every output
 * edge has at least one consumer.
 */
export interface PipelineSpec {
    /** Human-readable, e.g. "voice_agent_basic" */
    name: string;
    operators: OperatorSpec[];
    edges: EdgeSpec[];
    options?: PipelineOptions | undefined;
}
export interface OperatorSpec {
    /**
     * Unique within the spec, used as the prefix in edge endpoints like
     * "stt.final" or "llm.token".
     */
    name: string;
    /**
     * The primitive the operator implements: "generate_text", "transcribe",
     * "synthesize", "detect_voice", "embed", "rerank", "tokenize", "window",
     * or a solution-declared custom operator ("AudioSource", "AudioSink",
     * "SentenceDetector", "VectorSearch", "ContextBuild").
     */
    type: string;
    /**
     * Free-form parameters interpreted by the operator. The C++ loader
     * validates required keys per type before instantiating.
     */
    params: {
        [key: string]: string;
    };
    /**
     * Optional override of the engine that will serve this operator. When
     * empty, the L3 router picks based on capability + model format.
     */
    pinnedEngine: string;
    /** Optional model identifier (resolved against the model registry). */
    modelId: string;
    /**
     * Affinity hint: run this operator on CPU, GPU, or Neural Engine. The
     * scheduler may override if the requested device is unavailable.
     */
    device: DeviceAffinity;
}
export interface OperatorSpec_ParamsEntry {
    key: string;
    value: string;
}
export interface EdgeSpec {
    /**
     * Endpoints are formatted "<operator_name>.<port_name>".
     * Source port names are operator-specific output channels; sink port
     * names are operator-specific input channels. Typing is enforced by the
     * pipeline validator.
     */
    from: string;
    to: string;
    /**
     * Channel depth override. Proto3 scalars have no presence bit, so the
     * sentinel value 0 means "use the per-edge default (16 for PCM, 256 for
     * tokens, 32 for sentences)". uint32 keeps the wire representation
     * identical to int32 on the happy path while making negative inputs
     * statically unrepresentable.
     */
    capacity: number;
    policy: EdgePolicy;
}
export interface PipelineOptions {
    /**
     * Maximum end-to-end latency budget in milliseconds. The pipeline emits
     * a MetricsEvent with is_over_budget=true if exceeded.
     */
    latencyBudgetMs: number;
    /**
     * When true, the pipeline emits MetricsEvent on every VAD barge-in and
     * on pipeline stop.
     */
    emitMetrics: boolean;
    /**
     * When true, the pipeline validates the DAG for deadlocks and
     * disconnected edges before running.
     */
    strictValidation: boolean;
}
export declare const PipelineSpec: {
    encode(message: PipelineSpec, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): PipelineSpec;
    fromJSON(object: any): PipelineSpec;
    toJSON(message: PipelineSpec): unknown;
    create<I extends Exact<DeepPartial<PipelineSpec>, I>>(base?: I): PipelineSpec;
    fromPartial<I extends Exact<DeepPartial<PipelineSpec>, I>>(object: I): PipelineSpec;
};
export declare const OperatorSpec: {
    encode(message: OperatorSpec, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): OperatorSpec;
    fromJSON(object: any): OperatorSpec;
    toJSON(message: OperatorSpec): unknown;
    create<I extends Exact<DeepPartial<OperatorSpec>, I>>(base?: I): OperatorSpec;
    fromPartial<I extends Exact<DeepPartial<OperatorSpec>, I>>(object: I): OperatorSpec;
};
export declare const OperatorSpec_ParamsEntry: {
    encode(message: OperatorSpec_ParamsEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): OperatorSpec_ParamsEntry;
    fromJSON(object: any): OperatorSpec_ParamsEntry;
    toJSON(message: OperatorSpec_ParamsEntry): unknown;
    create<I extends Exact<DeepPartial<OperatorSpec_ParamsEntry>, I>>(base?: I): OperatorSpec_ParamsEntry;
    fromPartial<I extends Exact<DeepPartial<OperatorSpec_ParamsEntry>, I>>(object: I): OperatorSpec_ParamsEntry;
};
export declare const EdgeSpec: {
    encode(message: EdgeSpec, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): EdgeSpec;
    fromJSON(object: any): EdgeSpec;
    toJSON(message: EdgeSpec): unknown;
    create<I extends Exact<DeepPartial<EdgeSpec>, I>>(base?: I): EdgeSpec;
    fromPartial<I extends Exact<DeepPartial<EdgeSpec>, I>>(object: I): EdgeSpec;
};
export declare const PipelineOptions: {
    encode(message: PipelineOptions, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): PipelineOptions;
    fromJSON(object: any): PipelineOptions;
    toJSON(message: PipelineOptions): unknown;
    create<I extends Exact<DeepPartial<PipelineOptions>, I>>(base?: I): PipelineOptions;
    fromPartial<I extends Exact<DeepPartial<PipelineOptions>, I>>(object: I): PipelineOptions;
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
//# sourceMappingURL=pipeline.d.ts.map