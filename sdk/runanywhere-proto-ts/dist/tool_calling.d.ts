import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Supported parameter types.
 * ---------------------------------------------------------------------------
 */
export declare enum ToolParameterType {
    TOOL_PARAMETER_TYPE_UNSPECIFIED = 0,
    TOOL_PARAMETER_TYPE_STRING = 1,
    TOOL_PARAMETER_TYPE_NUMBER = 2,
    TOOL_PARAMETER_TYPE_BOOLEAN = 3,
    TOOL_PARAMETER_TYPE_OBJECT = 4,
    TOOL_PARAMETER_TYPE_ARRAY = 5,
    UNRECOGNIZED = -1
}
export declare function toolParameterTypeFromJSON(object: any): ToolParameterType;
export declare function toolParameterTypeToJSON(object: ToolParameterType): string;
/**
 * ---------------------------------------------------------------------------
 * Tool-call wire formats various LLM families emit. Strongly-typed counterpart
 * to `ToolCallingOptions.format_hint` (which remains a free-form string for
 * back-compat — the legacy values "default"/"lfm2"/"openai"/"auto" do not map
 * 1:1 to this enum).
 *
 * Drift across SDKs:
 *   - Swift's `ToolCallFormatName` (Public/Extensions/LLM/ToolCallingTypes.swift)
 *     today only exposes `default` and `lfm2` constants on a string-typed
 *     field — it is not yet an enum.
 *   - Kotlin/RN/Flutter/Web mirror the same string-keyed shape.
 * This enum is the union of formats LLM families actually emit; SDK frontends
 * should map their existing strings onto these values when surfacing the
 * strongly-typed field. Keep `format_hint` (string) populated for legacy
 * consumers until all SDKs migrate.
 * ---------------------------------------------------------------------------
 */
export declare enum ToolCallFormatName {
    TOOL_CALL_FORMAT_NAME_UNSPECIFIED = 0,
    TOOL_CALL_FORMAT_NAME_JSON = 1,
    TOOL_CALL_FORMAT_NAME_XML = 2,
    TOOL_CALL_FORMAT_NAME_NATIVE = 3,
    TOOL_CALL_FORMAT_NAME_PYTHONIC = 4,
    TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS = 5,
    TOOL_CALL_FORMAT_NAME_HERMES = 6,
    UNRECOGNIZED = -1
}
export declare function toolCallFormatNameFromJSON(object: any): ToolCallFormatName;
export declare function toolCallFormatNameToJSON(object: ToolCallFormatName): string;
/**
 * ---------------------------------------------------------------------------
 * JSON-typed scalar / composite carrier for tool arguments and results.
 * Mirrors Swift's ToolValue enum, Kotlin's sealed class, and the
 * TypeScript discriminated union. Used inside ToolParameter.enum_values
 * (string-only) and as the canonical wire shape when consumers want
 * strongly-typed arguments rather than raw JSON.
 * ---------------------------------------------------------------------------
 */
export interface ToolValue {
    stringValue?: string | undefined;
    numberValue?: number | undefined;
    boolValue?: boolean | undefined;
    arrayValue?: ToolValueArray | undefined;
    objectValue?: ToolValueObject | undefined;
    /** true means JSON null */
    nullValue?: boolean | undefined;
}
export interface ToolValueArray {
    values: ToolValue[];
}
export interface ToolValueObject {
    fields: {
        [key: string]: ToolValue;
    };
}
export interface ToolValueObject_FieldsEntry {
    key: string;
    value?: ToolValue | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * A single parameter definition for a tool.
 * ---------------------------------------------------------------------------
 */
export interface ToolParameter {
    name: string;
    type: ToolParameterType;
    description: string;
    required: boolean;
    /** Allowed values for enum-like parameters. Empty = unconstrained. */
    enumValues: string[];
}
/**
 * ---------------------------------------------------------------------------
 * Definition of a tool that the LLM can call.
 * ---------------------------------------------------------------------------
 */
export interface ToolDefinition {
    name: string;
    description: string;
    parameters: ToolParameter[];
    /** Optional category for grouping tools in catalogs / UIs. */
    category?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * A tool call requested by the LLM. `arguments_json` is a JSON object
 * matching the parameter shape declared in the corresponding ToolDefinition.
 * ---------------------------------------------------------------------------
 */
export interface ToolCall {
    /** Unique ID (caller-supplied or generated). Empty = unset. */
    id: string;
    /** Tool name (matches ToolDefinition.name). */
    name: string;
    /** JSON-encoded arguments. Empty object "{}" if no args. */
    argumentsJson: string;
    /**
     * Discriminator for OpenAI-compatible flows ("function" is the only
     * value at the moment). Empty = unset.
     */
    type: string;
    /**
     * Strongly-typed arguments map for SDKs that do not want to parse
     * arguments_json. Producers should keep arguments_json populated for C++
     * tokenizer compatibility.
     */
    arguments: {
        [key: string]: ToolValue;
    };
    /** Alias for id used by pre-proto SDK surfaces. */
    callId?: string | undefined;
}
export interface ToolCall_ArgumentsEntry {
    key: string;
    value?: ToolValue | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Result of executing a tool. `result_json` is a JSON-encoded payload;
 * `error` is non-empty when the execution failed.
 * ---------------------------------------------------------------------------
 */
export interface ToolResult {
    toolCallId: string;
    name: string;
    resultJson: string;
    error?: string | undefined;
    /**
     * Whether execution succeeded. If unset/false and error is empty,
     * consumers should fall back to legacy result_json/error semantics.
     */
    success: boolean;
    /**
     * Strongly-typed result map for SDKs that do not want to parse
     * result_json. Producers should keep result_json populated for C++
     * tokenizer compatibility.
     */
    result: {
        [key: string]: ToolValue;
    };
    /** Alias for tool_call_id used by pre-proto SDK surfaces. */
    callId?: string | undefined;
}
export interface ToolResult_ResultEntry {
    key: string;
    value?: ToolValue | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Options for tool-enabled generation.
 * ---------------------------------------------------------------------------
 */
export interface ToolCallingOptions {
    /**
     * Available tools for this generation. If empty, the SDK falls back to
     * its registered tools (per-SDK convention).
     */
    tools: ToolDefinition[];
    /**
     * Maximum tool-call iterations in one conversation turn. 0 = SDK default
     * (typically 5).
     */
    maxIterations: number;
    /** Whether to auto-execute tools or hand them back to the caller. */
    autoExecute: boolean;
    /** Sampling temperature override (Swift: optional Float). */
    temperature?: number | undefined;
    /** Maximum tokens override. */
    maxTokens?: number | undefined;
    /** System prompt to use during tool-enabled generation. */
    systemPrompt?: string | undefined;
    /**
     * If true, replaces the system prompt entirely (no auto-injected
     * tool instructions).
     */
    replaceSystemPrompt: boolean;
    /**
     * If true, keeps tool definitions available across multiple sequential
     * tool calls in one generation.
     */
    keepToolsAvailable: boolean;
    /**
     * Tool-call format hint: "default" (JSON-tagged), "lfm2", "openai", "auto".
     * Empty = SDK default.
     */
    formatHint: string;
    /**
     * Strongly-typed tool-call format. Preferred over `format_hint` when set;
     * `format_hint` remains for legacy callers and per-SDK custom strings
     * that don't round-trip through this enum.
     */
    format?: ToolCallFormatName | undefined;
    /**
     * Caller-supplied system prompt that fully replaces the SDK-injected
     * tool-calling system prompt (rather than being merged with it).
     * Distinct from `system_prompt` (field 6), which is merged unless
     * `replace_system_prompt` is true.
     */
    customSystemPrompt?: string | undefined;
    /**
     * C ABI / SDK field name for max_iterations. 0 = use max_iterations or
     * SDK default.
     */
    maxToolCalls?: number | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Result of a tool-enabled generation.
 * ---------------------------------------------------------------------------
 */
export interface ToolCallingResult {
    /** Final text response from the assistant. */
    text: string;
    /** Tool calls the LLM made. */
    toolCalls: ToolCall[];
    /** Results of executed tools (only populated when auto_execute was true). */
    toolResults: ToolResult[];
    /** Whether the response is complete or waiting for more tool results. */
    isComplete: boolean;
    /** Conversation ID for continuing with tool results. */
    conversationId?: string | undefined;
    /** Number of tool-call iterations actually used. */
    iterationsUsed: number;
}
export declare const ToolValue: {
    encode(message: ToolValue, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolValue;
    fromJSON(object: any): ToolValue;
    toJSON(message: ToolValue): unknown;
    create<I extends Exact<DeepPartial<ToolValue>, I>>(base?: I): ToolValue;
    fromPartial<I extends Exact<DeepPartial<ToolValue>, I>>(object: I): ToolValue;
};
export declare const ToolValueArray: {
    encode(message: ToolValueArray, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolValueArray;
    fromJSON(object: any): ToolValueArray;
    toJSON(message: ToolValueArray): unknown;
    create<I extends Exact<DeepPartial<ToolValueArray>, I>>(base?: I): ToolValueArray;
    fromPartial<I extends Exact<DeepPartial<ToolValueArray>, I>>(object: I): ToolValueArray;
};
export declare const ToolValueObject: {
    encode(message: ToolValueObject, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolValueObject;
    fromJSON(object: any): ToolValueObject;
    toJSON(message: ToolValueObject): unknown;
    create<I extends Exact<DeepPartial<ToolValueObject>, I>>(base?: I): ToolValueObject;
    fromPartial<I extends Exact<DeepPartial<ToolValueObject>, I>>(object: I): ToolValueObject;
};
export declare const ToolValueObject_FieldsEntry: {
    encode(message: ToolValueObject_FieldsEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolValueObject_FieldsEntry;
    fromJSON(object: any): ToolValueObject_FieldsEntry;
    toJSON(message: ToolValueObject_FieldsEntry): unknown;
    create<I extends Exact<DeepPartial<ToolValueObject_FieldsEntry>, I>>(base?: I): ToolValueObject_FieldsEntry;
    fromPartial<I extends Exact<DeepPartial<ToolValueObject_FieldsEntry>, I>>(object: I): ToolValueObject_FieldsEntry;
};
export declare const ToolParameter: {
    encode(message: ToolParameter, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolParameter;
    fromJSON(object: any): ToolParameter;
    toJSON(message: ToolParameter): unknown;
    create<I extends Exact<DeepPartial<ToolParameter>, I>>(base?: I): ToolParameter;
    fromPartial<I extends Exact<DeepPartial<ToolParameter>, I>>(object: I): ToolParameter;
};
export declare const ToolDefinition: {
    encode(message: ToolDefinition, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolDefinition;
    fromJSON(object: any): ToolDefinition;
    toJSON(message: ToolDefinition): unknown;
    create<I extends Exact<DeepPartial<ToolDefinition>, I>>(base?: I): ToolDefinition;
    fromPartial<I extends Exact<DeepPartial<ToolDefinition>, I>>(object: I): ToolDefinition;
};
export declare const ToolCall: {
    encode(message: ToolCall, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCall;
    fromJSON(object: any): ToolCall;
    toJSON(message: ToolCall): unknown;
    create<I extends Exact<DeepPartial<ToolCall>, I>>(base?: I): ToolCall;
    fromPartial<I extends Exact<DeepPartial<ToolCall>, I>>(object: I): ToolCall;
};
export declare const ToolCall_ArgumentsEntry: {
    encode(message: ToolCall_ArgumentsEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCall_ArgumentsEntry;
    fromJSON(object: any): ToolCall_ArgumentsEntry;
    toJSON(message: ToolCall_ArgumentsEntry): unknown;
    create<I extends Exact<DeepPartial<ToolCall_ArgumentsEntry>, I>>(base?: I): ToolCall_ArgumentsEntry;
    fromPartial<I extends Exact<DeepPartial<ToolCall_ArgumentsEntry>, I>>(object: I): ToolCall_ArgumentsEntry;
};
export declare const ToolResult: {
    encode(message: ToolResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolResult;
    fromJSON(object: any): ToolResult;
    toJSON(message: ToolResult): unknown;
    create<I extends Exact<DeepPartial<ToolResult>, I>>(base?: I): ToolResult;
    fromPartial<I extends Exact<DeepPartial<ToolResult>, I>>(object: I): ToolResult;
};
export declare const ToolResult_ResultEntry: {
    encode(message: ToolResult_ResultEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolResult_ResultEntry;
    fromJSON(object: any): ToolResult_ResultEntry;
    toJSON(message: ToolResult_ResultEntry): unknown;
    create<I extends Exact<DeepPartial<ToolResult_ResultEntry>, I>>(base?: I): ToolResult_ResultEntry;
    fromPartial<I extends Exact<DeepPartial<ToolResult_ResultEntry>, I>>(object: I): ToolResult_ResultEntry;
};
export declare const ToolCallingOptions: {
    encode(message: ToolCallingOptions, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCallingOptions;
    fromJSON(object: any): ToolCallingOptions;
    toJSON(message: ToolCallingOptions): unknown;
    create<I extends Exact<DeepPartial<ToolCallingOptions>, I>>(base?: I): ToolCallingOptions;
    fromPartial<I extends Exact<DeepPartial<ToolCallingOptions>, I>>(object: I): ToolCallingOptions;
};
export declare const ToolCallingResult: {
    encode(message: ToolCallingResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCallingResult;
    fromJSON(object: any): ToolCallingResult;
    toJSON(message: ToolCallingResult): unknown;
    create<I extends Exact<DeepPartial<ToolCallingResult>, I>>(base?: I): ToolCallingResult;
    fromPartial<I extends Exact<DeepPartial<ToolCallingResult>, I>>(object: I): ToolCallingResult;
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
//# sourceMappingURL=tool_calling.d.ts.map