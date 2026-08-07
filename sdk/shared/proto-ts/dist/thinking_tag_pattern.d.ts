import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * The single home for reasoning control. Composed surfaces (tool calling, RAG,
 * voice agent) inherit it through the embedded LLMGenerationOptions.
 */
export declare enum ReasoningMode {
    /** REASONING_MODE_UNSPECIFIED - Reasoning-capable models think; others don't. */
    REASONING_MODE_UNSPECIFIED = 0,
    /** REASONING_MODE_OFF - Commons applies the model's no-think directive at the prompt level. */
    REASONING_MODE_OFF = 1,
    /** REASONING_MODE_ON - Request thinking on models where it is optional. */
    REASONING_MODE_ON = 2,
    UNRECOGNIZED = -1
}
export declare function reasoningModeFromJSON(object: any): ReasoningMode;
export declare function reasoningModeToJSON(object: ReasoningMode): string;
/**
 * Extracts a model's reasoning block from raw output, for families like Qwen3
 * and LFM2 that wrap it in <think>...</think>. Used both per-call and as
 * ModelInfo catalog metadata.
 */
export interface ThinkingTagPattern {
    /** Empty defaults to "<think>". */
    openTag: string;
    /** Empty defaults to "</think>". */
    closeTag: string;
}
export interface ReasoningOptions {
    mode: ReasoningMode;
    /**
     * Emit thought tokens to the caller as TokenKind.THOUGHT events plus
     * result thinking_content. False strips them.
     */
    includeInOutput: boolean;
    /** For models whose thinking markers differ from the catalog default. */
    pattern?: ThinkingTagPattern | undefined;
}
export declare const ThinkingTagPattern: MessageFns<ThinkingTagPattern>;
export declare const ReasoningOptions: MessageFns<ReasoningOptions>;
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
