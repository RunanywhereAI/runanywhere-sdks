import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * JSON Schema primitive type — union across SDKs.
 * Sources pre-IDL:
 *   RN  StructuredOutputTypes.ts:12     ('string'|'number'|'integer'|
 *                                        'boolean'|'object'|'array'|'null')
 *   Web (delegates to llamacpp pkg; no own enum)
 *   Swift / Kotlin / Dart represent schema as a serialized JSON string today,
 *     so this enum canonicalizes the RN-defined union.
 * ---------------------------------------------------------------------------
 */
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
/**
 * ---------------------------------------------------------------------------
 * Sentiment label — union across SDKs.
 * Sources pre-IDL:
 *   RN  StructuredOutputTypes.ts:131    ('positive'|'negative'|'neutral')
 *   (Other SDKs do not yet define a Sentiment type; MIXED is added for
 *    completeness — common in industry sentiment APIs.)
 * ---------------------------------------------------------------------------
 */
export declare enum Sentiment {
    SENTIMENT_UNSPECIFIED = 0,
    SENTIMENT_POSITIVE = 1,
    SENTIMENT_NEGATIVE = 2,
    SENTIMENT_NEUTRAL = 3,
    SENTIMENT_MIXED = 4,
    UNRECOGNIZED = -1
}
export declare function sentimentFromJSON(object: any): Sentiment;
export declare function sentimentToJSON(object: Sentiment): string;
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
/**
 * ---------------------------------------------------------------------------
 * JSON Schema property — describes a single property within a schema.
 * Sources pre-IDL:
 *   RN  StructuredOutputTypes.ts:24     JSONSchemaProperty (type, description,
 *                                       enum, format, items, properties, …)
 *
 * proto3 does not allow direct self-referential message fields without
 * `optional` / explicit handle. Recursion is expressed via:
 *   - `items_schema`     — for array element types       (handle to JSONSchema)
 *   - `object_schema`    — for nested object types       (handle to JSONSchema)
 * Deeper recursion (a property whose items are themselves objects with
 * further nested properties) is represented by repeating the same indirection
 * inside the referenced JSONSchema. Very deep schemas are uncommon and
 * supported by chaining these handles.
 * ---------------------------------------------------------------------------
 */
export interface JSONSchemaProperty {
    /** Primitive / composite type for this property. */
    type: JSONSchemaType;
    /** Human-readable description (`description` in JSON Schema). */
    description?: string | undefined;
    /**
     * Allowed enum values (`enum` in JSON Schema). Strings only; numeric and
     * boolean enums are rare and serialized as strings here.
     */
    enumValues: string[];
    /**
     * String format hint (`format` in JSON Schema): "email", "uri",
     * "date-time", etc.
     */
    format?: string | undefined;
    /** Element schema when `type == JSON_SCHEMA_TYPE_ARRAY`. */
    itemsSchema?: JSONSchema | undefined;
    /** Nested object schema when `type == JSON_SCHEMA_TYPE_OBJECT`. */
    objectSchema?: JSONSchema | undefined;
    /** Common validation constraints carried by RN/Web schema builders. */
    minimum?: number | undefined;
    maximum?: number | undefined;
    minLength?: number | undefined;
    maxLength?: number | undefined;
    pattern?: string | undefined;
    minItems?: number | undefined;
    maxItems?: number | undefined;
    defaultJson?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * JSON Schema definition — top-level schema for structured output.
 * Sources pre-IDL:
 *   RN  StructuredOutputTypes.ts:59     JSONSchema (extends JSONSchemaProperty
 *                                       with $schema, $id, title, definitions,
 *                                       $ref, allOf/anyOf/oneOf/not)
 * ---------------------------------------------------------------------------
 */
export interface JSONSchema {
    /** Root type for this schema (commonly OBJECT or ARRAY). */
    type: JSONSchemaType;
    /** Map of property name -> property definition. */
    properties: {
        [key: string]: JSONSchemaProperty;
    };
    /** Names of required properties (`required` in JSON Schema). */
    required: string[];
    /** Element schema when the root `type == JSON_SCHEMA_TYPE_ARRAY`. */
    items?: JSONSchemaProperty | undefined;
    /** Whether properties not declared in `properties` are allowed. */
    additionalProperties?: boolean | undefined;
    /**
     * JSON Schema document metadata / composition fields. Field names avoid
     * `$` in generated APIs while preserving JSON names for serializers.
     */
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
/**
 * ---------------------------------------------------------------------------
 * Structured output options — request-side configuration for a structured
 * generation call. Wraps a JSONSchema plus generation flags.
 * Sources pre-IDL:
 *   Swift  LLMTypes.swift:533           StructuredOutputConfig
 *   Kotlin LLMTypes.kt:242              StructuredOutputConfig
 *   Dart   structured_output_types.dart StructuredOutputConfig (incl. strict)
 *   RN     StructuredOutputTypes.ts:76  StructuredOutputOptions
 * ---------------------------------------------------------------------------
 */
export interface StructuredOutputOptions {
    /** Schema describing the desired output shape. */
    schema?: JSONSchema | undefined;
    /** Whether to embed the schema text in the LLM prompt. */
    includeSchemaInPrompt: boolean;
    /** Strict schema adherence — rejects outputs that don't fully validate. */
    strictMode?: boolean | undefined;
    /**
     * Raw JSON Schema string for C ABI and SDKs that already carry schema as
     * serialized JSON instead of the typed JSONSchema tree.
     */
    jsonSchema?: string | undefined;
    /** Optional generated type/name hints used by Swift/Kotlin/Dart wrappers. */
    typeName?: string | undefined;
    name?: string | undefined;
    mode: StructuredOutputMode;
    regexPattern?: string | undefined;
    grammar?: string | undefined;
    repairJson: boolean;
    maxRetries: number;
}
/**
 * ---------------------------------------------------------------------------
 * Structured output validation result — populated after the model returns.
 * Sources pre-IDL:
 *   Swift  LLMTypes.swift:585           StructuredOutputValidation
 *   Kotlin LLMTypes.kt:278              StructuredOutputValidation
 *   Dart   structured_output_types.dart StructuredOutputValidation
 * ---------------------------------------------------------------------------
 */
export interface StructuredOutputValidation {
    /** Whether the parsed output validates against the requested schema. */
    isValid: boolean;
    /** Whether the raw text contained any parseable JSON object. */
    containsJson: boolean;
    /** Validation / parse error message when `is_valid == false`. */
    errorMessage?: string | undefined;
    /** Original raw model output (for debugging / fallback parsing). */
    rawOutput?: string | undefined;
    /**
     * JSON substring extracted from raw_output before validation, when the
     * extractor found one.
     */
    extractedJson?: string | undefined;
    validationErrors: string[];
    validationTimeMs: number;
}
/**
 * ---------------------------------------------------------------------------
 * Structured output result — generic envelope returned by structured calls.
 * `parsed_json` is a UTF-8 JSON-encoded byte payload to keep the result
 * language-agnostic; SDKs deserialize into their concrete typed value.
 * Sources pre-IDL:
 *   RN     StructuredOutputTypes.ts:93  StructuredOutputResult<T> (data, raw,
 *                                       success, error)
 *   Dart   structured_output_types.dart StructuredOutputResult<T> (result,
 *                                       rawText, metrics)
 * ---------------------------------------------------------------------------
 */
export interface StructuredOutputResult {
    /** JSON-encoded parsed value (UTF-8 bytes). */
    parsedJson: Uint8Array;
    /** Validation / parse outcome. */
    validation?: StructuredOutputValidation | undefined;
    /** Raw model text prior to parsing (optional, useful for retries). */
    rawText?: string | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
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
    errorMessage?: string | undefined;
    errorCode: number;
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
    seq: number;
    timestampUs: number;
    requestId: string;
    kind: StructuredOutputStreamEventKind;
    token: string;
    partialJson?: string | undefined;
    validation?: StructuredOutputValidation | undefined;
    result?: StructuredOutputResult | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
/**
 * ---------------------------------------------------------------------------
 * Named entity — single span identified within input text.
 * Sources pre-IDL:
 *   RN  StructuredOutputTypes.ts:143    NamedEntity (text, type, startOffset,
 *                                       endOffset, confidence)
 * ---------------------------------------------------------------------------
 */
export interface NamedEntity {
    /** Surface form of the entity exactly as it appeared in input. */
    text: string;
    /** Entity class label, e.g. "PERSON", "ORG", "LOCATION". */
    entityType: string;
    /** UTF-16 / character start offset (inclusive) within input text. */
    startOffset: number;
    /** UTF-16 / character end offset (exclusive) within input text. */
    endOffset: number;
    /** Model confidence in [0.0, 1.0]. */
    confidence: number;
}
/**
 * ---------------------------------------------------------------------------
 * Entity extraction result — list of entities pulled from a document.
 * Sources pre-IDL:
 *   RN  StructuredOutputTypes.ts:110    EntityExtractionResult<T>
 *                                       (entities, confidence)
 * Note: RN's per-result `confidence` is dropped in favor of per-entity
 * confidence on `NamedEntity`, which is the more granular and useful form.
 * ---------------------------------------------------------------------------
 */
export interface EntityExtractionResult {
    entities: NamedEntity[];
}
/**
 * ---------------------------------------------------------------------------
 * Classification candidate — alternative label considered.
 * Sources pre-IDL:
 *   RN  StructuredOutputTypes.ts:118    ClassificationResult.alternatives item
 * ---------------------------------------------------------------------------
 */
export interface ClassificationCandidate {
    label: string;
    confidence: number;
}
/**
 * ---------------------------------------------------------------------------
 * Classification result — top label plus optional alternatives.
 * Sources pre-IDL:
 *   RN  StructuredOutputTypes.ts:118    ClassificationResult (category,
 *                                       confidence, alternatives)
 * Note: RN names the field `category`; canonicalized here to `label`, which
 * matches industry classifier APIs (HuggingFace, OpenAI, etc.).
 * ---------------------------------------------------------------------------
 */
export interface ClassificationResult {
    label: string;
    confidence: number;
    alternatives: ClassificationCandidate[];
}
/**
 * ---------------------------------------------------------------------------
 * Sentiment analysis result — overall sentiment plus per-class scores.
 * Sources pre-IDL:
 *   RN  StructuredOutputTypes.ts:130    SentimentResult (sentiment, score,
 *                                       aspects)
 * ---------------------------------------------------------------------------
 */
export interface SentimentResult {
    sentiment: Sentiment;
    /** Aggregate confidence in the chosen sentiment label, [0.0, 1.0]. */
    confidence: number;
    /** Per-class soft scores (optional). Absent fields are unscored. */
    positiveScore?: number | undefined;
    negativeScore?: number | undefined;
    neutralScore?: number | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Named entity recognition result — alias-style wrapper carrying entities.
 * Equivalent in shape to `EntityExtractionResult`; both are kept so SDKs that
 * distinguish "extraction" (instruction-driven) from "NER" (model-native)
 * can route to the appropriate type without ambiguity.
 * Sources pre-IDL:
 *   RN  StructuredOutputTypes.ts:154    NERResult (entities)
 * ---------------------------------------------------------------------------
 */
export interface NERResult {
    entities: NamedEntity[];
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
export declare const EntityExtractionResult: MessageFns<EntityExtractionResult>;
export declare const ClassificationCandidate: MessageFns<ClassificationCandidate>;
export declare const ClassificationResult: MessageFns<ClassificationResult>;
export declare const SentimentResult: MessageFns<SentimentResult>;
export declare const NERResult: MessageFns<NERResult>;
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
