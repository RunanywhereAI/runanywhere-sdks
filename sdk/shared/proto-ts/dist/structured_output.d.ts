import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
export declare const protobufPackage = "runanywhere.v1";
export declare enum JSONSchemaType {
    JSON_SCHEMA_TYPE_UNSPECIFIED = 0,
    JSON_SCHEMA_TYPE_OBJECT = 1,
    JSON_SCHEMA_TYPE_ARRAY = 2,
    JSON_SCHEMA_TYPE_STRING = 3,
    JSON_SCHEMA_TYPE_NUMBER = 4,
    JSON_SCHEMA_TYPE_INTEGER = 5,
    JSON_SCHEMA_TYPE_BOOLEAN = 6,
    JSON_SCHEMA_TYPE_NULL = 7,
    UNRECOGNIZED = -1
}
export declare function jSONSchemaTypeFromJSON(object: any): JSONSchemaType;
export declare function jSONSchemaTypeToJSON(object: JSONSchemaType): string;
export declare enum StructuredOutputMode {
    STRUCTURED_OUTPUT_MODE_UNSPECIFIED = 0,
    STRUCTURED_OUTPUT_MODE_JSON_SCHEMA = 1,
    STRUCTURED_OUTPUT_MODE_JSON_OBJECT = 2,
    STRUCTURED_OUTPUT_MODE_REGEX = 3,
    STRUCTURED_OUTPUT_MODE_GRAMMAR = 4,
    UNRECOGNIZED = -1
}
export declare function structuredOutputModeFromJSON(object: any): StructuredOutputMode;
export declare function structuredOutputModeToJSON(object: StructuredOutputMode): string;
export declare enum StructuredOutputStreamEventKind {
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN = 1,
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_PARTIAL_JSON = 2,
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_VALIDATION = 3,
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED = 4,
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR = 5,
    UNRECOGNIZED = -1
}
export declare function structuredOutputStreamEventKindFromJSON(object: any): StructuredOutputStreamEventKind;
export declare function structuredOutputStreamEventKindToJSON(object: StructuredOutputStreamEventKind): string;
export interface JSONSchemaProperty {
    type: JSONSchemaType;
    description?: string | undefined;
    enumValues: string[];
    format?: string | undefined;
    /** items_schema for arrays, object_schema for nested objects. */
    itemsSchema?: JSONSchema | undefined;
    objectSchema?: JSONSchema | undefined;
    minimum?: number | undefined;
    maximum?: number | undefined;
    minLength?: number | undefined;
    maxLength?: number | undefined;
    pattern?: string | undefined;
    minItems?: number | undefined;
    maxItems?: number | undefined;
    defaultJson?: string | undefined;
}
export interface JSONSchema {
    type: JSONSchemaType;
    properties: {
        [key: string]: JSONSchemaProperty;
    };
    required: string[];
    items?: JSONSchemaProperty | undefined;
    additionalProperties?: boolean | undefined;
    schemaUri?: string | undefined;
    idUri?: string | undefined;
    title?: string | undefined;
    description?: string | undefined;
    definitions: {
        [key: string]: JSONSchema;
    };
    ref?: string | undefined;
    allOf: JSONSchema[];
    anyOf: JSONSchema[];
    oneOf: JSONSchema[];
    notSchema?: JSONSchema | undefined;
    /** Escape hatch for schemas the typed shape above cannot express. */
    rawJson?: string | undefined;
}
export interface JSONSchema_PropertiesEntry {
    key: string;
    value?: JSONSchemaProperty | undefined;
}
export interface JSONSchema_DefinitionsEntry {
    key: string;
    value?: JSONSchema | undefined;
}
export interface StructuredOutputOptions {
    includeSchemaInPrompt: boolean;
    /** Not read by commons. */
    strictMode?: boolean | undefined;
    schema?: JSONSchema | undefined;
    jsonSchema?: string | undefined;
    /** Matches OpenAI's json_schema.name. */
    name?: string | undefined;
    mode: StructuredOutputMode;
    regexPattern?: string | undefined;
    grammar?: string | undefined;
    /** Attempt to repair malformed JSON before failing. */
    repairJson: boolean;
    maxRetries: number;
}
export interface StructuredOutputValidation {
    isValid: boolean;
    containsJson: boolean;
    rawOutput?: string | undefined;
    extractedJson?: string | undefined;
    validationErrors: string[];
    validationTimeMs: number;
    error?: SDKError | undefined;
}
export interface StructuredOutputResult {
    parsedJson: Uint8Array;
    validation?: StructuredOutputValidation | undefined;
    rawText?: string | undefined;
    error?: SDKError | undefined;
}
export interface StructuredOutputParseRequest {
    requestId: string;
    text: string;
    options?: StructuredOutputOptions | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface StructuredOutputParseRequest_MetadataEntry {
    key: string;
    value: string;
}
export interface StructuredOutputValidationRequest {
    text: string;
    options?: StructuredOutputOptions | undefined;
}
export interface StructuredOutputPromptResult {
    preparedPrompt: string;
    systemPrompt?: string | undefined;
    jsonSchema?: string | undefined;
    regexPattern?: string | undefined;
    grammar?: string | undefined;
    error?: SDKError | undefined;
}
export interface StructuredOutputRequest {
    requestId: string;
    prompt: string;
    options?: StructuredOutputOptions | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface StructuredOutputRequest_MetadataEntry {
    key: string;
    value: string;
}
export interface StructuredOutputStreamEvent {
    timestampUs: number;
    requestId: string;
    kind: StructuredOutputStreamEventKind;
    token: string;
    partialJson?: string | undefined;
    validation?: StructuredOutputValidation | undefined;
    result?: StructuredOutputResult | undefined;
    error?: SDKError | undefined;
}
/** Character offsets into the source text. */
export interface NamedEntity {
    text: string;
    entityType: string;
    startOffset: number;
    endOffset: number;
    confidence: number;
}
export declare const JSONSchemaProperty: MessageFns<JSONSchemaProperty>;
export declare const JSONSchema: MessageFns<JSONSchema>;
export declare const JSONSchema_PropertiesEntry: MessageFns<JSONSchema_PropertiesEntry>;
export declare const JSONSchema_DefinitionsEntry: MessageFns<JSONSchema_DefinitionsEntry>;
export declare const StructuredOutputOptions: MessageFns<StructuredOutputOptions>;
export declare const StructuredOutputValidation: MessageFns<StructuredOutputValidation>;
export declare const StructuredOutputResult: MessageFns<StructuredOutputResult>;
export declare const StructuredOutputParseRequest: MessageFns<StructuredOutputParseRequest>;
export declare const StructuredOutputParseRequest_MetadataEntry: MessageFns<StructuredOutputParseRequest_MetadataEntry>;
export declare const StructuredOutputValidationRequest: MessageFns<StructuredOutputValidationRequest>;
export declare const StructuredOutputPromptResult: MessageFns<StructuredOutputPromptResult>;
export declare const StructuredOutputRequest: MessageFns<StructuredOutputRequest>;
export declare const StructuredOutputRequest_MetadataEntry: MessageFns<StructuredOutputRequest_MetadataEntry>;
export declare const StructuredOutputStreamEvent: MessageFns<StructuredOutputStreamEvent>;
export declare const NamedEntity: MessageFns<NamedEntity>;
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
