import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * The single home for reasoning/thinking control. Replaces the retired
 * per-message toggles (LLMGenerationOptions.disable_thinking,
 * ToolCallingOptions.disable_thinking, RAGQueryOptions.disable_thinking,
 * ToolCallingSessionCreateRequest.disable_thinking,
 * LLMGenerateRequest.emit_thoughts). Referenced from LLM and VLM generation
 * options; every composed surface (tool calling, RAG, voice agent) inherits
 * it through the embedded LLMGenerationOptions.
 * ---------------------------------------------------------------------------
 */
export declare enum ReasoningMode {
    /** REASONING_MODE_UNSPECIFIED - Model default: reasoning-capable models think, others don't. */
    REASONING_MODE_UNSPECIFIED = 0,
    /**
     * REASONING_MODE_OFF - Suppress the thinking phase (commons applies the model's no-think
     * directive at the prompt level).
     */
    REASONING_MODE_OFF = 1,
    /** REASONING_MODE_ON - Request the thinking phase on models where it is optional. */
    REASONING_MODE_ON = 2,
    UNRECOGNIZED = -1
}
export declare function reasoningModeFromJSON(object: any): ReasoningMode;
export declare function reasoningModeToJSON(object: ReasoningMode): string;
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
export interface ReasoningOptions {
    mode: ReasoningMode;
    /**
     * Emit thought tokens/content to the caller (stream TokenKind.THOUGHT
     * events and result thinking_content). False = thinking is stripped.
     */
    includeInOutput: boolean;
    /**
     * Tag override for models whose thinking markers differ from the
     * catalog default.
     */
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
