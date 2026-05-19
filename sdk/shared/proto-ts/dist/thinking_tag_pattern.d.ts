import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
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
export declare const ThinkingTagPattern: MessageFns<ThinkingTagPattern>;
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
