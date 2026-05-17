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
     * AUDIT (IDL-13): the C++ tokenizer / tool-prompt formatter
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
    /** Alias for id used by pre-proto SDK surfaces. */
    callId?: string | undefined;
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
     * AUDIT (IDL-13): the C++ tool-prompt formatter
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
    /** Alias for tool_call_id used by pre-proto SDK surfaces. */
    callId?: string | undefined;
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
    toolChoice: ToolChoiceMode;
    forcedToolName?: string | undefined;
    parallelToolCalls: boolean;
    requireJsonArguments: boolean;
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
    errorMessage?: string | undefined;
    errorCode: number;
    rawText: string;
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
    formatHint: string;
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
    formatHint: string;
    maxIterations: number;
    keepToolsAvailable: boolean;
    /**
     * proto3 `optional` enables presence detection (has_validate_calls()).
     * When unset, commons defaults to validate_calls=true (preserves the
     * historical hard-coded behavior and the native run-loop / session
     * contract that unknown tool calls short-circuit before host execution).
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
export declare const ToolValueJSON: {
    encode(message: ToolValueJSON, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolValueJSON;
    fromJSON(object: any): ToolValueJSON;
    toJSON(message: ToolValueJSON): unknown;
    create<I extends Exact<DeepPartial<ToolValueJSON>, I>>(base?: I): ToolValueJSON;
    fromPartial<I extends Exact<DeepPartial<ToolValueJSON>, I>>(object: I): ToolValueJSON;
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
export declare const ToolDefinition_MetadataEntry: {
    encode(message: ToolDefinition_MetadataEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolDefinition_MetadataEntry;
    fromJSON(object: any): ToolDefinition_MetadataEntry;
    toJSON(message: ToolDefinition_MetadataEntry): unknown;
    create<I extends Exact<DeepPartial<ToolDefinition_MetadataEntry>, I>>(base?: I): ToolDefinition_MetadataEntry;
    fromPartial<I extends Exact<DeepPartial<ToolDefinition_MetadataEntry>, I>>(object: I): ToolDefinition_MetadataEntry;
};
export declare const ToolCall: {
    encode(message: ToolCall, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCall;
    fromJSON(object: any): ToolCall;
    toJSON(message: ToolCall): unknown;
    create<I extends Exact<DeepPartial<ToolCall>, I>>(base?: I): ToolCall;
    fromPartial<I extends Exact<DeepPartial<ToolCall>, I>>(object: I): ToolCall;
};
export declare const ToolResult: {
    encode(message: ToolResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolResult;
    fromJSON(object: any): ToolResult;
    toJSON(message: ToolResult): unknown;
    create<I extends Exact<DeepPartial<ToolResult>, I>>(base?: I): ToolResult;
    fromPartial<I extends Exact<DeepPartial<ToolResult>, I>>(object: I): ToolResult;
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
export declare const ToolParseRequest: {
    encode(message: ToolParseRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolParseRequest;
    fromJSON(object: any): ToolParseRequest;
    toJSON(message: ToolParseRequest): unknown;
    create<I extends Exact<DeepPartial<ToolParseRequest>, I>>(base?: I): ToolParseRequest;
    fromPartial<I extends Exact<DeepPartial<ToolParseRequest>, I>>(object: I): ToolParseRequest;
};
export declare const ToolParseResult: {
    encode(message: ToolParseResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolParseResult;
    fromJSON(object: any): ToolParseResult;
    toJSON(message: ToolParseResult): unknown;
    create<I extends Exact<DeepPartial<ToolParseResult>, I>>(base?: I): ToolParseResult;
    fromPartial<I extends Exact<DeepPartial<ToolParseResult>, I>>(object: I): ToolParseResult;
};
export declare const ToolPromptFormatRequest: {
    encode(message: ToolPromptFormatRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolPromptFormatRequest;
    fromJSON(object: any): ToolPromptFormatRequest;
    toJSON(message: ToolPromptFormatRequest): unknown;
    create<I extends Exact<DeepPartial<ToolPromptFormatRequest>, I>>(base?: I): ToolPromptFormatRequest;
    fromPartial<I extends Exact<DeepPartial<ToolPromptFormatRequest>, I>>(object: I): ToolPromptFormatRequest;
};
export declare const ToolPromptFormatResult: {
    encode(message: ToolPromptFormatResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolPromptFormatResult;
    fromJSON(object: any): ToolPromptFormatResult;
    toJSON(message: ToolPromptFormatResult): unknown;
    create<I extends Exact<DeepPartial<ToolPromptFormatResult>, I>>(base?: I): ToolPromptFormatResult;
    fromPartial<I extends Exact<DeepPartial<ToolPromptFormatResult>, I>>(object: I): ToolPromptFormatResult;
};
export declare const ToolCallValidationRequest: {
    encode(message: ToolCallValidationRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCallValidationRequest;
    fromJSON(object: any): ToolCallValidationRequest;
    toJSON(message: ToolCallValidationRequest): unknown;
    create<I extends Exact<DeepPartial<ToolCallValidationRequest>, I>>(base?: I): ToolCallValidationRequest;
    fromPartial<I extends Exact<DeepPartial<ToolCallValidationRequest>, I>>(object: I): ToolCallValidationRequest;
};
export declare const ToolCallValidationResult: {
    encode(message: ToolCallValidationResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCallValidationResult;
    fromJSON(object: any): ToolCallValidationResult;
    toJSON(message: ToolCallValidationResult): unknown;
    create<I extends Exact<DeepPartial<ToolCallValidationResult>, I>>(base?: I): ToolCallValidationResult;
    fromPartial<I extends Exact<DeepPartial<ToolCallValidationResult>, I>>(object: I): ToolCallValidationResult;
};
export declare const ToolCallingStreamEvent: {
    encode(message: ToolCallingStreamEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCallingStreamEvent;
    fromJSON(object: any): ToolCallingStreamEvent;
    toJSON(message: ToolCallingStreamEvent): unknown;
    create<I extends Exact<DeepPartial<ToolCallingStreamEvent>, I>>(base?: I): ToolCallingStreamEvent;
    fromPartial<I extends Exact<DeepPartial<ToolCallingStreamEvent>, I>>(object: I): ToolCallingStreamEvent;
};
export declare const ToolRegistrySnapshot: {
    encode(message: ToolRegistrySnapshot, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolRegistrySnapshot;
    fromJSON(object: any): ToolRegistrySnapshot;
    toJSON(message: ToolRegistrySnapshot): unknown;
    create<I extends Exact<DeepPartial<ToolRegistrySnapshot>, I>>(base?: I): ToolRegistrySnapshot;
    fromPartial<I extends Exact<DeepPartial<ToolRegistrySnapshot>, I>>(object: I): ToolRegistrySnapshot;
};
export declare const ToolCallingSessionCreateRequest: {
    encode(message: ToolCallingSessionCreateRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCallingSessionCreateRequest;
    fromJSON(object: any): ToolCallingSessionCreateRequest;
    toJSON(message: ToolCallingSessionCreateRequest): unknown;
    create<I extends Exact<DeepPartial<ToolCallingSessionCreateRequest>, I>>(base?: I): ToolCallingSessionCreateRequest;
    fromPartial<I extends Exact<DeepPartial<ToolCallingSessionCreateRequest>, I>>(object: I): ToolCallingSessionCreateRequest;
};
export declare const ToolCallingSessionCreateResult: {
    encode(message: ToolCallingSessionCreateResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCallingSessionCreateResult;
    fromJSON(object: any): ToolCallingSessionCreateResult;
    toJSON(message: ToolCallingSessionCreateResult): unknown;
    create<I extends Exact<DeepPartial<ToolCallingSessionCreateResult>, I>>(base?: I): ToolCallingSessionCreateResult;
    fromPartial<I extends Exact<DeepPartial<ToolCallingSessionCreateResult>, I>>(object: I): ToolCallingSessionCreateResult;
};
export declare const ToolCallingSessionEvent: {
    encode(message: ToolCallingSessionEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCallingSessionEvent;
    fromJSON(object: any): ToolCallingSessionEvent;
    toJSON(message: ToolCallingSessionEvent): unknown;
    create<I extends Exact<DeepPartial<ToolCallingSessionEvent>, I>>(base?: I): ToolCallingSessionEvent;
    fromPartial<I extends Exact<DeepPartial<ToolCallingSessionEvent>, I>>(object: I): ToolCallingSessionEvent;
};
export declare const ToolCallingSessionStepWithResultRequest: {
    encode(message: ToolCallingSessionStepWithResultRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCallingSessionStepWithResultRequest;
    fromJSON(object: any): ToolCallingSessionStepWithResultRequest;
    toJSON(message: ToolCallingSessionStepWithResultRequest): unknown;
    create<I extends Exact<DeepPartial<ToolCallingSessionStepWithResultRequest>, I>>(base?: I): ToolCallingSessionStepWithResultRequest;
    fromPartial<I extends Exact<DeepPartial<ToolCallingSessionStepWithResultRequest>, I>>(object: I): ToolCallingSessionStepWithResultRequest;
};
export declare const ToolCallingSessionDestroyRequest: {
    encode(message: ToolCallingSessionDestroyRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ToolCallingSessionDestroyRequest;
    fromJSON(object: any): ToolCallingSessionDestroyRequest;
    toJSON(message: ToolCallingSessionDestroyRequest): unknown;
    create<I extends Exact<DeepPartial<ToolCallingSessionDestroyRequest>, I>>(base?: I): ToolCallingSessionDestroyRequest;
    fromPartial<I extends Exact<DeepPartial<ToolCallingSessionDestroyRequest>, I>>(object: I): ToolCallingSessionDestroyRequest;
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
