import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { TokenUsage } from "./token_usage";
export declare const protobufPackage = "runanywhere.v1";
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
/** Conversational role of one prior turn in `history`. */
export declare enum ToolCallingRole {
    TOOL_CALLING_ROLE_UNSPECIFIED = 0,
    TOOL_CALLING_ROLE_USER = 1,
    TOOL_CALLING_ROLE_ASSISTANT = 2,
    TOOL_CALLING_ROLE_SYSTEM = 3,
    UNRECOGNIZED = -1
}
export declare function toolCallingRoleFromJSON(object: any): ToolCallingRole;
export declare function toolCallingRoleToJSON(object: ToolCallingRole): string;
/**
 * ---------------------------------------------------------------------------
 * JSON-typed scalar / composite carrier for tool arguments and results.
 * Mirrors Swift's ToolValue enum, Kotlin's sealed class, and the
 * TypeScript discriminated union. Used as the canonical wire shape when
 * consumers want strongly-typed arguments rather than raw JSON.
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
 * Definition of a tool that the LLM can call.
 * ---------------------------------------------------------------------------
 */
export interface ToolDefinition {
    name: string;
    description: string;
    /**
     * OpenAI-compatible parameters schema: ONE JSON Schema object describing
     * this tool's arguments — the same shape solutions.proto's ToolSpec
     * already carries. One schema per tool is what OpenAI (`parameters`),
     * Anthropic (`input_schema`) and MCP (`inputSchema`) each publish.
     * "" or "{}" advertises a zero-argument tool.
     */
    parameters: string;
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
    /**
     * Correlation id, echoed back on ToolResult.tool_call_id. Caller-supplied
     * or generated; carried through parse AND validate unchanged. Never
     * derived from created_at_ms. Empty = unset.
     */
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
     * Wall-clock parse time, ms since epoch (second resolution today).
     * Diagnostic ONLY — never an identity, never used to correlate a call
     * with its result.
     */
    createdAtMs: number;
    /**
     * The exact model text this call was extracted FROM, including the tool
     * envelope. Diagnostic. Not the envelope-stripped text — that is
     * ToolParseResult.remaining_text.
     */
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
     * True when the tool failed, so commons tells the model the call errored
     * instead of feeding result_json back as data and the model can
     * self-correct. The proto3 zero value (false) is the correct default: a
     * ToolResult nobody touched reads as a good result, not a failed one.
     * Industry: Anthropic `is_error`, MCP `isError`.
     */
    isError: boolean;
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
     * Unset = true: the SDK runs your registered executor and closes the
     * loop. Explicit false returns the parsed ToolCall without invoking it.
     * Presence-tracked so "unset" is never confused with "explicitly false".
     */
    autoExecute?: boolean | undefined;
    /**
     * System prompt for tool-enabled generation. This is the ONLY channel
     * ToolPromptFormatRequest (a standalone verb with no enclosing
     * LLMGenerationOptions) has for a system prompt; when ToolCallingOptions
     * is embedded in LLMGenerationOptions, the child value wins when present
     * and options.system_prompt is the fallback.
     */
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
     * When true, one model turn may emit multiple tool-call envelopes;
     * commons parses and executes all of them before building a single
     * follow-up prompt. Default false preserves the historical
     * one-call-per-turn behavior.
     *
     * Wire history: field 15 originally carried this same bool flag, was
     * briefly reserved during a cleanup pass, then restored with identical
     * type and meaning. Do not reuse 15 for any other type. Schema-skew
     * fixtures under idl/codegen/tests cover old-writer/new-reader for this
     * field.
     */
    parallelToolCalls: boolean;
    /**
     * Maximum tool calls in one conversation turn. Unset/0 = the annotated
     * default applies.
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
    /**
     * Moved here from ToolCallingSessionCreateRequest so one message carries
     * the whole tool-generation policy.
     */
    topP?: number | undefined;
    /**
     * Unset = true: unknown tool calls short-circuit before host execution.
     * Callers that delegate validation/authorization to their executor or
     * use dynamic tool registries must explicitly set validate_calls=false.
     */
    validateCalls?: boolean | undefined;
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
    /** Number of LLM generation turns used, including the final synthesis turn. */
    iterationsUsed: number;
    errorMessage?: string | undefined;
    errorCode: number;
    /** Optional thinking/reasoning content extracted from the final response. */
    thinkingContent?: string | undefined;
    /**
     * Token usage aggregated across every LLM generation turn in the loop
     * (including the final synthesis turn). Lets a plain generate() that routed
     * through the tool loop report the same usage a non-tool generate would.
     */
    usage?: TokenUsage | undefined;
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
/**
 * One prior conversation turn, with its speaker stated rather than inferred
 * from list position.
 *
 * Declared here rather than importing chat.proto's ChatMessage/MessageRole:
 * chat.proto already imports tool_calling.proto, so that import would cycle.
 * Extracting ChatMessage + MessageRole into a leaf proto was considered and
 * rejected as a larger change than this surface warrants.
 *
 * Mapping from chat.proto: MESSAGE_ROLE_USER -> TOOL_CALLING_ROLE_USER,
 * MESSAGE_ROLE_ASSISTANT -> TOOL_CALLING_ROLE_ASSISTANT,
 * MESSAGE_ROLE_SYSTEM -> TOOL_CALLING_ROLE_SYSTEM. Tool calls and tool
 * results do NOT round-trip through history — only role + content do.
 */
export interface ToolCallingHistoryTurn {
    role: ToolCallingRole;
    content: string;
}
export interface ToolCallingSessionCreateRequest {
    /** The current turn's user prompt. */
    prompt: string;
    /**
     * Prior turns, EXCLUDING the current turn (which is `prompt`). commons
     * threads these into every generate in the loop so multi-turn tool use
     * keeps context.
     */
    history: ToolCallingHistoryTurn[];
    /**
     * THE single home for tool policy + sampling. No re-published copies:
     * every knob that used to be duplicated on this message (tools, format,
     * max_tool_calls, keep_tools_available, validate_calls, tool_choice,
     * forced_tool_name, max_output_tokens, temperature, top_p, system_prompt,
     * disable_thinking, auto_execute, replace_system_prompt,
     * require_json_arguments, parallel_tool_calls) lives on ToolCallingOptions.
     */
    options?: ToolCallingOptions | undefined;
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
export declare const ToolValue: MessageFns<ToolValue>;
export declare const ToolValueArray: MessageFns<ToolValueArray>;
export declare const ToolValueObject: MessageFns<ToolValueObject>;
export declare const ToolValueObject_FieldsEntry: MessageFns<ToolValueObject_FieldsEntry>;
export declare const ToolValueJSON: MessageFns<ToolValueJSON>;
export declare const ToolDefinition: MessageFns<ToolDefinition>;
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
export declare const ToolCallingHistoryTurn: MessageFns<ToolCallingHistoryTurn>;
export declare const ToolCallingSessionCreateRequest: MessageFns<ToolCallingSessionCreateRequest>;
export declare const ToolCallingSessionEvent: MessageFns<ToolCallingSessionEvent>;
export declare const ToolCallingSessionStepWithResultRequest: MessageFns<ToolCallingSessionStepWithResultRequest>;
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
