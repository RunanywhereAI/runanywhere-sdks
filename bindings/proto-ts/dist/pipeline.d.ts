import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
export declare enum DeviceAffinity {
    DEVICE_AFFINITY_UNSPECIFIED = 0,
    DEVICE_AFFINITY_ANY = 1,
    DEVICE_AFFINITY_CPU = 2,
    DEVICE_AFFINITY_GPU = 3,
    /**
     * DEVICE_AFFINITY_NPU - Vendor-neutral neural accelerator: Apple Neural Engine, Qualcomm
     * Hexagon NPU, etc. The YAML loader already accepts "npu" for this value.
     */
    DEVICE_AFFINITY_NPU = 4,
    UNRECOGNIZED = -1
}
export declare function deviceAffinityFromJSON(object: any): DeviceAffinity;
export declare function deviceAffinityToJSON(object: DeviceAffinity): string;
export declare enum EdgePolicy {
    EDGE_POLICY_UNSPECIFIED = 0,
    EDGE_POLICY_BLOCK = 1,
    EDGE_POLICY_DROP_OLDEST = 2,
    EDGE_POLICY_DROP_NEWEST = 3,
    UNRECOGNIZED = -1
}
export declare function edgePolicyFromJSON(object: any): EdgePolicy;
export declare function edgePolicyToJSON(object: EdgePolicy): string;
export interface PipelineSpec {
    /** e.g. "voice_agent_basic". */
    name: string;
    operators: OperatorSpec[];
    edges: EdgeSpec[];
    options?: PipelineOptions | undefined;
}
export interface OperatorSpec {
    name: string;
    type: string;
    params: {
        [key: string]: string;
    };
    /** Bypasses priority-based engine selection. */
    pinnedEngine: string;
    modelId: string;
    device: DeviceAffinity;
}
export interface OperatorSpec_ParamsEntry {
    key: string;
    value: string;
}
export interface EdgeSpec {
    from: string;
    to: string;
    /** Queue depth, and what happens when it fills. */
    capacity: number;
    policy: EdgePolicy;
}
export interface PipelineOptions {
    latencyBudgetMs: number;
    emitMetrics: boolean;
    /** Reject a spec with unknown operators instead of skipping them. */
    strictValidation: boolean;
}
export declare const PipelineSpec: MessageFns<PipelineSpec>;
export declare const OperatorSpec: MessageFns<OperatorSpec>;
export declare const OperatorSpec_ParamsEntry: MessageFns<OperatorSpec_ParamsEntry>;
export declare const EdgeSpec: MessageFns<EdgeSpec>;
export declare const PipelineOptions: MessageFns<PipelineOptions>;
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
