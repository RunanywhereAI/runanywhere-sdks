import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Pattern used to extract a model's "thinking" / reasoning block from its
 * raw output. Used by Qwen3 and LFM2 family models that emit
 * <think>...</think> wrappers. Shared by LLM generation options (per-call
 * override) and ModelInfo catalog metadata (default pattern for a model).
 * ---------------------------------------------------------------------------
 */
export interface ThinkingTagPattern {
    /** Opening tag string. Default if empty: "<think>". */
    openTag: string;
    /** Closing tag string. Default if empty: "</think>". */
    closeTag: string;
}
export declare const ThinkingTagPattern: {
    encode(message: ThinkingTagPattern, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ThinkingTagPattern;
    fromJSON(object: any): ThinkingTagPattern;
    toJSON(message: ThinkingTagPattern): unknown;
    create<I extends Exact<DeepPartial<ThinkingTagPattern>, I>>(base?: I): ThinkingTagPattern;
    fromPartial<I extends Exact<DeepPartial<ThinkingTagPattern>, I>>(object: I): ThinkingTagPattern;
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
