import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
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
 * Tool-call wire formats various LLM families emit. This enum is the single
 * portable format selector across commons and every generated SDK binding.
 * ---------------------------------------------------------------------------
 */
export declare enum ToolCallFormatName {
    TOOL_CALL_FORMAT_NAME_UNSPECIFIED = 0,
    TOOL_CALL_FORMAT_NAME_JSON = 1,
    TOOL_CALL_FORMAT_NAME_LFM2 = 7,
    UNRECOGNIZED = -1
}
export declare function toolCallFormatNameFromJSON(object: any): ToolCallFormatName;
export declare function toolCallFormatNameToJSON(object: ToolCallFormatName): string;
export declare enum ToolChoiceMode {
    TOOL_CHOICE_MODE_UNSPECIFIED = 0,
    TOOL_CHOICE_MODE_AUTO = 1,
    TOOL_CHOICE_MODE_NONE = 2,
    TOOL_CHOICE_MODE_REQUIRED = 3,
    TOOL_CHOICE_MODE_SPECIFIC = 4,
    UNRECOGNIZED = -1
}
export declare function toolChoiceModeFromJSON(object: any): ToolChoiceMode;
export declare function toolChoiceModeToJSON(object: ToolChoiceMode): string;
export declare enum ToolCallingStreamEventKind {
    TOOL_CALLING_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    TOOL_CALLING_STREAM_EVENT_KIND_MODEL_TOKEN = 1,
    TOOL_CALLING_STREAM_EVENT_KIND_TOOL_CALL_PARSED = 2,
    TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_STARTED = 3,
    TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_COMPLETED = 4,
    TOOL_CALLING_STREAM_EVENT_KIND_COMPLETED = 5,
    TOOL_CALLING_STREAM_EVENT_KIND_ERROR = 6,
    UNRECOGNIZED = -1
}
export declare function toolCallingStreamEventKindFromJSON(object: any): ToolCallingStreamEventKind;
export declare function toolCallingStreamEventKindToJSON(object: ToolCallingStreamEventKind): string;
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
 * String wrapper used by the rac_tool_value_to_json_proto /
 * rac_tool_value_from_json_proto ABIs. Carries either the JSON text rendered
 * from a ToolValue, or the JSON text that should be parsed back into a
 * ToolValue. Defined here (rather than reusing a stand-alone wrapper) so the
 * tool-calling round-trip stays self-contained in this proto.
 * ---------------------------------------------------------------------------
 */
export interface ToolValueJSON {
    json: string;
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
    jsonSchema?: string | undefined;
    defaultValue?: ToolValue | undefined;
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
    jsonSchema?: string | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface ToolDefinition_MetadataEntry {
    key: string;
    value: string;
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
    /**
     * JSON-encoded arguments. Empty object "{}" if no args.
     *
     * The C++ tokenizer / tool-prompt formatter
     * (sdk/runanywhere-commons/src/features/llm/tool_calling.cpp) reads
     * `arguments_json` directly when building LLM prompts. It is the
     * canonical wire shape for the prompt-formatting path.
     */
    argumentsJson: string;
    /**
     * Discriminator for OpenAI-compatible flows ("function" is the only
     * value at the moment). Empty = unset.
     */
    type: string;
    createdAtMs: number;
    rawText?: string | undefined;
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
    /**
     * JSON-encoded tool execution result.
     *
     * The C++ tool-prompt formatter
     * (`sdk/runanywhere-commons/src/features/llm/tool_calling.cpp:1870-1885`)
     * reads `result_json` directly when building follow-up LLM prompts after
     * tool execution. It is the canonical wire shape.
     */
    resultJson: string;
    error?: string | undefined;
    /**
     * Whether execution succeeded. If unset/false and error is empty,
     * consumers should fall back to result_json/error semantics.
     */
    success: boolean;
    startedAtMs: number;
    completedAtMs: number;
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
    /** Typed tool-call format. Unset lets commons select the model default. */
    format?: ToolCallFormatName | undefined;
    /**
     * Maximum tool calls in one conversation turn. Unset/0 = SDK default
     * (typically 5).
     */
    maxToolCalls?: number | undefined;
    toolChoice: ToolChoiceMode;
    forcedToolName?: string | undefined;
    requireJsonArguments: boolean;
    /**
     * When true, suppress the model's thinking/reasoning phase during
     * tool-enabled generation (commons prepends the model no-think directive
     * at the prompt level — same contract as
     * LLMGenerationOptions.disable_thinking). Default false.
     */
    disableThinking?: boolean | undefined;
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
    /** Number of LLM generation turns used, including the final synthesis turn. */
    iterationsUsed: number;
    errorMessage?: string | undefined;
    errorCode: number;
    rawText: string;
    /** Optional thinking/reasoning content extracted from the final response. */
    thinkingContent?: string | undefined;
}
export interface ToolParseRequest {
    text: string;
    options?: ToolCallingOptions | undefined;
}
export interface ToolParseResult {
    hasToolCall: boolean;
    toolCalls: ToolCall[];
    remainingText: string;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface ToolPromptFormatRequest {
    /**
     * User prompt to merge with tool instructions. Empty means return only
     * the tool-instruction block for the selected format.
     */
    userPrompt: string;
    /** Carries available tools plus format/choice/iteration constraints. */
    options?: ToolCallingOptions | undefined;
    /**
     * Tool results to include when formatting a follow-up prompt after host
     * execution. Empty means an initial tool-enabled prompt.
     */
    toolResults: ToolResult[];
    /** Assistant text emitted before tool execution, when available. */
    assistantText?: string | undefined;
}
export interface ToolPromptFormatResult {
    formattedPrompt: string;
    format: ToolCallFormatName;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface ToolCallValidationRequest {
    toolCall?: ToolCall | undefined;
    /**
     * Validation uses options.tools as the registry snapshot and honors
     * portable flags such as require_json_arguments and forced_tool_name.
     */
    options?: ToolCallingOptions | undefined;
}
export interface ToolCallValidationResult {
    isValid: boolean;
    validationErrors: string[];
    matchedTool?: ToolDefinition | undefined;
    normalizedArgumentsJson: string;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface ToolCallingStreamEvent {
    seq: number;
    timestampUs: number;
    conversationId: string;
    kind: ToolCallingStreamEventKind;
    token: string;
    toolCall?: ToolCall | undefined;
    toolResult?: ToolResult | undefined;
    result?: ToolCallingResult | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface ToolRegistrySnapshot {
    tools: ToolDefinition[];
    updatedAtMs: number;
}
export interface ToolCallingSessionCreateRequest {
    /** Prompt + LLM generation options inline (avoids cross-proto import cycle). */
    prompt: string;
    maxTokens: number;
    temperature: number;
    topP: number;
    systemPrompt: string;
    tools: ToolDefinition[];
    format: ToolCallFormatName;
    maxToolCalls: number;
    keepToolsAvailable: boolean;
    /**
     * proto3 `optional` enables presence detection (has_validate_calls()).
     * When unset, commons defaults to validate_calls=true so unknown tool
     * calls short-circuit before host execution.
     * Callers that delegate validation/authorization to their executor or
     * use dynamic tool registries must explicitly set validate_calls=false.
     */
    validateCalls?: boolean | undefined;
    /**
     * OpenAI-style tool_choice override surfaced through the high-level
     * run-loop / session APIs. The same fields exist on ToolCallingOptions
     * (fields 13/14); we re-publish them here so the canonical request
     * envelope can carry the policy without forcing callers to pass an
     * inline ToolCallingOptions. commons honors these on every
     * format/validate primitive via build_options_snapshot.
     */
    toolChoice?: ToolChoiceMode | undefined;
    forcedToolName?: string | undefined;
    /**
     * When true, suppress the model's thinking phase for every generate in
     * the loop/session (maps from ToolCallingOptions.disable_thinking; same
     * contract as LLMGenerationOptions.disable_thinking). Default false.
     */
    disableThinking: boolean;
    /**
     * Default true when absent. False returns the parsed ToolCall without
     * invoking the host executor.
     */
    autoExecute?: boolean | undefined;
    replaceSystemPrompt: boolean;
    requireJsonArguments: boolean;
}
export interface ToolCallingSessionCreateResult {
    sessionHandle: number;
}
export interface ToolCallingSessionEvent {
    /** serialized LLMStreamEvent proto */
    llmStreamEventBytes?: Uint8Array | undefined;
    toolCall?: ToolCall | undefined;
    finalResult?: ToolCallingResult | undefined;
    /** serialized SDKError proto */
    errorBytes?: Uint8Array | undefined;
    seq: number;
}
export interface ToolCallingSessionStepWithResultRequest {
    sessionHandle: number;
    toolCallId: string;
    resultJson: string;
    error?: string | undefined;
}
export interface ToolCallingSessionDestroyRequest {
    sessionHandle: number;
}
export declare const ToolValue: MessageFns<ToolValue>;
export declare const ToolValueArray: MessageFns<ToolValueArray>;
export declare const ToolValueObject: MessageFns<ToolValueObject>;
export declare const ToolValueObject_FieldsEntry: MessageFns<ToolValueObject_FieldsEntry>;
export declare const ToolValueJSON: MessageFns<ToolValueJSON>;
export declare const ToolParameter: MessageFns<ToolParameter>;
export declare const ToolDefinition: MessageFns<ToolDefinition>;
export declare const ToolDefinition_MetadataEntry: MessageFns<ToolDefinition_MetadataEntry>;
export declare const ToolCall: MessageFns<ToolCall>;
export declare const ToolResult: MessageFns<ToolResult>;
export declare const ToolCallingOptions: MessageFns<ToolCallingOptions>;
export declare const ToolCallingResult: MessageFns<ToolCallingResult>;
export declare const ToolParseRequest: MessageFns<ToolParseRequest>;
export declare const ToolParseResult: MessageFns<ToolParseResult>;
export declare const ToolPromptFormatRequest: MessageFns<ToolPromptFormatRequest>;
export declare const ToolPromptFormatResult: MessageFns<ToolPromptFormatResult>;
export declare const ToolCallValidationRequest: MessageFns<ToolCallValidationRequest>;
export declare const ToolCallValidationResult: MessageFns<ToolCallValidationResult>;
export declare const ToolCallingStreamEvent: MessageFns<ToolCallingStreamEvent>;
export declare const ToolRegistrySnapshot: MessageFns<ToolRegistrySnapshot>;
export declare const ToolCallingSessionCreateRequest: MessageFns<ToolCallingSessionCreateRequest>;
export declare const ToolCallingSessionCreateResult: MessageFns<ToolCallingSessionCreateResult>;
export declare const ToolCallingSessionEvent: MessageFns<ToolCallingSessionEvent>;
export declare const ToolCallingSessionStepWithResultRequest: MessageFns<ToolCallingSessionStepWithResultRequest>;
export declare const ToolCallingSessionDestroyRequest: MessageFns<ToolCallingSessionDestroyRequest>;
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
