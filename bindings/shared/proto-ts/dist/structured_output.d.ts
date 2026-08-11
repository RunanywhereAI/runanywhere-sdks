import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
export declare const protobufPackage = "runanywhere.v1";
/**
 * How commons applies StructuredOutputOptions on the ordinary LLM generate
 * path. Platform SDKs must not invent a second policy.
 */
export declare enum StructuredOutputMode {
    STRUCTURED_OUTPUT_MODE_UNSPECIFIED = 0,
    /** STRUCTURED_OUTPUT_MODE_CONSTRAINED - Compile schema→GBNF (or honor grammar/regex) and constrain decoding. */
    STRUCTURED_OUTPUT_MODE_CONSTRAINED = 1,
    /** STRUCTURED_OUTPUT_MODE_VALIDATION_ONLY - Do not constrain decoding; validate the free-text result against schema. */
    STRUCTURED_OUTPUT_MODE_VALIDATION_ONLY = 2,
    /**
     * STRUCTURED_OUTPUT_MODE_REPAIR - Constrained (when a decoder arm is present), then one repair retry if
     * the first answer fails schema validation.
     */
    STRUCTURED_OUTPUT_MODE_REPAIR = 3,
    UNRECOGNIZED = -1
}
export declare function structuredOutputModeFromJSON(object: any): StructuredOutputMode;
export declare function structuredOutputModeToJSON(object: StructuredOutputMode): string;
export interface StructuredOutputOptions {
    /**
     * Also render the schema into the system prompt, not just constrain
     * decoding. Costs input tokens and invalidates the thread's prompt cache.
     * Default true (matches Apple FoundationModels includeSchemaInPrompt).
     */
    includeSchemaInPrompt?: boolean | undefined;
    /**
     * A JSON Schema document, verbatim. Unsupported keywords are rejected.
     * Commons compiles this to GBNF on the generate path (mode permitting).
     */
    schema?: string | undefined;
    /** GBNF/EBNF grammar text. On-device only. */
    grammar?: string | undefined;
    /** Regular expression the whole output must match. On-device only. */
    regex?: string | undefined;
    /** Unset = CONSTRAINED when a constraint arm is present, else free text. */
    mode?: StructuredOutputMode | undefined;
}
export interface StructuredOutputValidation {
    isValid: boolean;
    containsJson: boolean;
    rawOutput?: string | undefined;
    extractedJson?: string | undefined;
    validationErrors: string[];
    validationTimeMs: number;
    error?: SDKError | undefined;
    /** True when commons issued the single repair retry (mode=REPAIR). */
    repairAttempted: boolean;
    /** 0 = first pass only; 1 = repair pass produced the reported verdict. */
    repairAttempts: number;
}
export interface StructuredOutputResult {
    /** The extracted JSON document, as UTF-8 text. Parse it client-side. */
    json: string;
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
export interface StructuredOutputPromptResult {
    preparedPrompt: string;
    systemPrompt?: string | undefined;
    jsonSchema?: string | undefined;
    regexPattern?: string | undefined;
    grammar?: string | undefined;
    error?: SDKError | undefined;
}
export declare const StructuredOutputOptions: MessageFns<StructuredOutputOptions>;
export declare const StructuredOutputValidation: MessageFns<StructuredOutputValidation>;
export declare const StructuredOutputResult: MessageFns<StructuredOutputResult>;
export declare const StructuredOutputParseRequest: MessageFns<StructuredOutputParseRequest>;
export declare const StructuredOutputParseRequest_MetadataEntry: MessageFns<StructuredOutputParseRequest_MetadataEntry>;
export declare const StructuredOutputPromptResult: MessageFns<StructuredOutputPromptResult>;
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
