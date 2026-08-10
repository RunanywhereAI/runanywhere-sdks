import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
export declare const protobufPackage = "runanywhere.v1";
export interface StructuredOutputOptions {
    /**
     * Also render the schema into the system prompt, not just constrain
     * decoding. Costs input tokens and invalidates the thread's prompt cache.
     * Default true (matches Apple FoundationModels includeSchemaInPrompt).
     */
    includeSchemaInPrompt?: boolean | undefined;
    /** A JSON Schema document, verbatim. Unsupported keywords are rejected. */
    schema?: string | undefined;
    /** GBNF/EBNF grammar text. On-device only. */
    grammar?: string | undefined;
    /** Regular expression the whole output must match. On-device only. */
    regex?: string | undefined;
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
