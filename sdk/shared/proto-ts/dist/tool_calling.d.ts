import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
export declare const protobufPackage = "runanywhere.v1";
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
/** LFM2 names a model family in a wire enum, which the rest of the IDL avoids. */
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
/** A JSON value, typed rather than stringly. */
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
export interface ToolValueJSON {
    json: string;
}
export interface ToolParameter {
    name: string;
    type: ToolParameterType;
    description: string;
    required: boolean;
    enumValues: string[];
    /** Escape hatch for parameters the typed shape cannot express. */
    jsonSchema?: string | undefined;
    defaultValue?: ToolValue | undefined;
}
export interface ToolDefinition {
    name: string;
    description: string;
    /** Use parameters for the typed form, or json_schema for a raw one. */
    parameters: ToolParameter[];
    jsonSchema?: string | undefined;
    category?: string | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface ToolDefinition_MetadataEntry {
    key: string;
    value: string;
}
export interface ToolCall {
    id: string;
    name: string;
    argumentsJson: string;
    /** "function" is the only value today. Empty = unset. */
    type: string;
    createdAtMs: number;
    /** The model text this call was parsed out of. */
    rawText?: string | undefined;
}
export interface ToolResult {
    toolCallId: string;
    name: string;
    resultJson: string;
    startedAtMs: number;
    completedAtMs: number;
    /** Unset means the tool ran successfully; fall back to result_json semantics. */
    error?: SDKError | undefined;
}
export interface ToolCallingOptions {
    /** Empty means the SDK falls back to its registered tools. */
    tools: ToolDefinition[];
    /** Run tools automatically rather than handing calls back to the caller. */
    autoExecute?: boolean | undefined;
    replaceSystemPrompt: boolean;
    /** Keep offering tools after the first call resolves. */
    keepToolsAvailable: boolean;
    format?: ToolCallFormatName | undefined;
    /** Iteration cap on the run loop. */
    maxToolCalls?: number | undefined;
    /** forced_tool_name applies when tool_choice is SPECIFIC. */
    toolChoice: ToolChoiceMode;
    forcedToolName?: string | undefined;
    requireJsonArguments: boolean;
}
export interface ToolCallingResult {
    text: string;
    toolCalls: ToolCall[];
    toolResults: ToolResult[];
    /** False when the loop stopped at max_tool_calls with calls outstanding. */
    isComplete: boolean;
    conversationId?: string | undefined;
    iterationsUsed: number;
    rawText: string;
    thinkingContent?: string | undefined;
    error?: SDKError | undefined;
}
export interface ToolParseRequest {
    text: string;
    options?: ToolCallingOptions | undefined;
}
export interface ToolParseResult {
    hasToolCall: boolean;
    toolCalls: ToolCall[];
    /** Model text left over after the calls were extracted. */
    remainingText: string;
    error?: SDKError | undefined;
}
export interface ToolPromptFormatRequest {
    userPrompt: string;
    options?: ToolCallingOptions | undefined;
    /** Prior turn's results and text, for multi-iteration loops. */
    toolResults: ToolResult[];
    assistantText?: string | undefined;
}
export interface ToolPromptFormatResult {
    formattedPrompt: string;
    format: ToolCallFormatName;
    error?: SDKError | undefined;
}
export interface ToolCallValidationRequest {
    toolCall?: ToolCall | undefined;
    options?: ToolCallingOptions | undefined;
}
export interface ToolCallValidationResult {
    isValid: boolean;
    validationErrors: string[];
    matchedTool?: ToolDefinition | undefined;
    /** Arguments coerced to the matched tool's parameter types. */
    normalizedArgumentsJson: string;
    error?: SDKError | undefined;
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
