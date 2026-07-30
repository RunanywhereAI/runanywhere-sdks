import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Coarse routing bucket. Per-modality errors (STT, TTS, LLM, VAD, VLM) fold
 * into COMPONENT; the modality is recoverable from c_abi_code and
 * ErrorContext.operation, so it is not encoded twice.
 */
export declare enum ErrorCategory {
    ERROR_CATEGORY_UNSPECIFIED = 0,
    /** ERROR_CATEGORY_NETWORK - wire, HTTP, download, server, timeout */
    ERROR_CATEGORY_NETWORK = 1,
    /** ERROR_CATEGORY_VALIDATION - invalid args, empty input, format */
    ERROR_CATEGORY_VALIDATION = 2,
    /** ERROR_CATEGORY_MODEL - not-found, load-failed, incompatible */
    ERROR_CATEGORY_MODEL = 3,
    /** ERROR_CATEGORY_COMPONENT - STT/TTS/LLM/VAD/VLM/etc. lifecycle */
    ERROR_CATEGORY_COMPONENT = 4,
    /** ERROR_CATEGORY_IO - file system, storage, audio buffers */
    ERROR_CATEGORY_IO = 5,
    /** ERROR_CATEGORY_AUTH - API key, unauthorized, forbidden */
    ERROR_CATEGORY_AUTH = 6,
    /** ERROR_CATEGORY_INTERNAL - unknown, not-implemented, internal */
    ERROR_CATEGORY_INTERNAL = 7,
    /** ERROR_CATEGORY_CONFIGURATION - env mismatch, init not done, bad cfg */
    ERROR_CATEGORY_CONFIGURATION = 8,
    UNRECOGNIZED = -1
}
export declare function errorCategoryFromJSON(object: any): ErrorCategory;
export declare function errorCategoryToJSON(object: ErrorCategory): string;
export declare enum ErrorSeverity {
    ERROR_SEVERITY_UNSPECIFIED = 0,
    ERROR_SEVERITY_DEBUG = 1,
    ERROR_SEVERITY_INFO = 2,
    ERROR_SEVERITY_WARNING = 3,
    ERROR_SEVERITY_ERROR = 4,
    ERROR_SEVERITY_CRITICAL = 5,
    UNRECOGNIZED = -1
}
export declare function errorSeverityFromJSON(object: any): ErrorSeverity;
export declare function errorSeverityToJSON(object: ErrorSeverity): string;
/**
 * proto3 forbids negative enum values, so each constant is the absolute
 * magnitude of its C ABI code: ERROR_CODE_<NAME> = abs(RAC_ERROR_<NAME>).
 * SDKError.c_abi_code carries the signed original.
 *
 * The trailing macro names below are kept because they are the cross-reference
 * into rac_error.h; where the C ABI defines two names for one value, the alias
 * is noted.
 */
export declare enum ErrorCode {
    ERROR_CODE_UNSPECIFIED = 0,
    /** ERROR_CODE_NOT_INITIALIZED - -- Initialization (-100..-109) ----------------------------------------- */
    ERROR_CODE_NOT_INITIALIZED = 100,
    /** ERROR_CODE_ALREADY_INITIALIZED - RAC_ERROR_ALREADY_INITIALIZED */
    ERROR_CODE_ALREADY_INITIALIZED = 101,
    /** ERROR_CODE_INITIALIZATION_FAILED - RAC_ERROR_INITIALIZATION_FAILED */
    ERROR_CODE_INITIALIZATION_FAILED = 102,
    /** ERROR_CODE_INVALID_CONFIGURATION - RAC_ERROR_INVALID_CONFIGURATION */
    ERROR_CODE_INVALID_CONFIGURATION = 103,
    /** ERROR_CODE_INVALID_API_KEY - RAC_ERROR_INVALID_API_KEY */
    ERROR_CODE_INVALID_API_KEY = 104,
    /** ERROR_CODE_ENVIRONMENT_MISMATCH - RAC_ERROR_ENVIRONMENT_MISMATCH */
    ERROR_CODE_ENVIRONMENT_MISMATCH = 105,
    /** ERROR_CODE_INVALID_PARAMETER - RAC_ERROR_INVALID_PARAMETER */
    ERROR_CODE_INVALID_PARAMETER = 106,
    /** ERROR_CODE_MODEL_NOT_FOUND - -- Model (-110..-129) -------------------------------------------------- */
    ERROR_CODE_MODEL_NOT_FOUND = 110,
    /** ERROR_CODE_MODEL_LOAD_FAILED - RAC_ERROR_MODEL_LOAD_FAILED */
    ERROR_CODE_MODEL_LOAD_FAILED = 111,
    /** ERROR_CODE_MODEL_VALIDATION_FAILED - RAC_ERROR_MODEL_VALIDATION_FAILED */
    ERROR_CODE_MODEL_VALIDATION_FAILED = 112,
    /** ERROR_CODE_MODEL_INCOMPATIBLE - RAC_ERROR_MODEL_INCOMPATIBLE */
    ERROR_CODE_MODEL_INCOMPATIBLE = 113,
    /** ERROR_CODE_INVALID_MODEL_FORMAT - RAC_ERROR_INVALID_MODEL_FORMAT */
    ERROR_CODE_INVALID_MODEL_FORMAT = 114,
    /** ERROR_CODE_MODEL_STORAGE_CORRUPTED - RAC_ERROR_MODEL_STORAGE_CORRUPTED */
    ERROR_CODE_MODEL_STORAGE_CORRUPTED = 115,
    /** ERROR_CODE_MODEL_NOT_LOADED - RAC_ERROR_MODEL_NOT_LOADED */
    ERROR_CODE_MODEL_NOT_LOADED = 116,
    /** ERROR_CODE_GENERATION_FAILED - -- Generation (-130..-149) -------------------------------------------- */
    ERROR_CODE_GENERATION_FAILED = 130,
    /** ERROR_CODE_GENERATION_TIMEOUT - RAC_ERROR_GENERATION_TIMEOUT */
    ERROR_CODE_GENERATION_TIMEOUT = 131,
    /** ERROR_CODE_CONTEXT_TOO_LONG - RAC_ERROR_CONTEXT_TOO_LONG */
    ERROR_CODE_CONTEXT_TOO_LONG = 132,
    /** ERROR_CODE_TOKEN_LIMIT_EXCEEDED - RAC_ERROR_TOKEN_LIMIT_EXCEEDED */
    ERROR_CODE_TOKEN_LIMIT_EXCEEDED = 133,
    /** ERROR_CODE_COST_LIMIT_EXCEEDED - RAC_ERROR_COST_LIMIT_EXCEEDED */
    ERROR_CODE_COST_LIMIT_EXCEEDED = 134,
    /** ERROR_CODE_INFERENCE_FAILED - RAC_ERROR_INFERENCE_FAILED */
    ERROR_CODE_INFERENCE_FAILED = 135,
    /** ERROR_CODE_GENERATION_CANCELLED - RAC_ERROR_GENERATION_CANCELLED */
    ERROR_CODE_GENERATION_CANCELLED = 136,
    /** ERROR_CODE_NETWORK_UNAVAILABLE - -- Network (-150..-179) ------------------------------------------------ */
    ERROR_CODE_NETWORK_UNAVAILABLE = 150,
    /** ERROR_CODE_NETWORK_ERROR - RAC_ERROR_NETWORK_ERROR */
    ERROR_CODE_NETWORK_ERROR = 151,
    /** ERROR_CODE_REQUEST_FAILED - RAC_ERROR_REQUEST_FAILED */
    ERROR_CODE_REQUEST_FAILED = 152,
    /** ERROR_CODE_DOWNLOAD_FAILED - RAC_ERROR_DOWNLOAD_FAILED */
    ERROR_CODE_DOWNLOAD_FAILED = 153,
    /** ERROR_CODE_SERVER_ERROR - RAC_ERROR_SERVER_ERROR */
    ERROR_CODE_SERVER_ERROR = 154,
    /** ERROR_CODE_TIMEOUT - RAC_ERROR_TIMEOUT */
    ERROR_CODE_TIMEOUT = 155,
    /** ERROR_CODE_INVALID_RESPONSE - RAC_ERROR_INVALID_RESPONSE */
    ERROR_CODE_INVALID_RESPONSE = 156,
    /** ERROR_CODE_HTTP_ERROR - RAC_ERROR_HTTP_ERROR */
    ERROR_CODE_HTTP_ERROR = 157,
    /** ERROR_CODE_CONNECTION_LOST - RAC_ERROR_CONNECTION_LOST */
    ERROR_CODE_CONNECTION_LOST = 158,
    /** ERROR_CODE_PARTIAL_DOWNLOAD - RAC_ERROR_PARTIAL_DOWNLOAD */
    ERROR_CODE_PARTIAL_DOWNLOAD = 159,
    /** ERROR_CODE_HTTP_REQUEST_FAILED - RAC_ERROR_HTTP_REQUEST_FAILED */
    ERROR_CODE_HTTP_REQUEST_FAILED = 160,
    /** ERROR_CODE_HTTP_NOT_SUPPORTED - RAC_ERROR_HTTP_NOT_SUPPORTED */
    ERROR_CODE_HTTP_NOT_SUPPORTED = 161,
    /** ERROR_CODE_INSUFFICIENT_STORAGE - -- Storage (-180..-219) ------------------------------------------------ */
    ERROR_CODE_INSUFFICIENT_STORAGE = 180,
    /** ERROR_CODE_STORAGE_FULL - RAC_ERROR_STORAGE_FULL */
    ERROR_CODE_STORAGE_FULL = 181,
    /** ERROR_CODE_STORAGE_ERROR - RAC_ERROR_STORAGE_ERROR */
    ERROR_CODE_STORAGE_ERROR = 182,
    /** ERROR_CODE_FILE_NOT_FOUND - RAC_ERROR_FILE_NOT_FOUND */
    ERROR_CODE_FILE_NOT_FOUND = 183,
    /** ERROR_CODE_FILE_READ_FAILED - RAC_ERROR_FILE_READ_FAILED */
    ERROR_CODE_FILE_READ_FAILED = 184,
    /** ERROR_CODE_FILE_WRITE_FAILED - RAC_ERROR_FILE_WRITE_FAILED */
    ERROR_CODE_FILE_WRITE_FAILED = 185,
    /** ERROR_CODE_PERMISSION_DENIED - RAC_ERROR_PERMISSION_DENIED */
    ERROR_CODE_PERMISSION_DENIED = 186,
    /** ERROR_CODE_DELETE_FAILED - RAC_ERROR_DELETE_FAILED (alias: RAC_ERROR_FILE_DELETE_FAILED) */
    ERROR_CODE_DELETE_FAILED = 187,
    /** ERROR_CODE_MOVE_FAILED - RAC_ERROR_MOVE_FAILED */
    ERROR_CODE_MOVE_FAILED = 188,
    /** ERROR_CODE_DIRECTORY_CREATION_FAILED - RAC_ERROR_DIRECTORY_CREATION_FAILED */
    ERROR_CODE_DIRECTORY_CREATION_FAILED = 189,
    /** ERROR_CODE_DIRECTORY_NOT_FOUND - RAC_ERROR_DIRECTORY_NOT_FOUND */
    ERROR_CODE_DIRECTORY_NOT_FOUND = 190,
    /** ERROR_CODE_INVALID_PATH - RAC_ERROR_INVALID_PATH */
    ERROR_CODE_INVALID_PATH = 191,
    /** ERROR_CODE_INVALID_FILE_NAME - RAC_ERROR_INVALID_FILE_NAME */
    ERROR_CODE_INVALID_FILE_NAME = 192,
    /** ERROR_CODE_TEMP_FILE_CREATION_FAILED - RAC_ERROR_TEMP_FILE_CREATION_FAILED */
    ERROR_CODE_TEMP_FILE_CREATION_FAILED = 193,
    /** ERROR_CODE_HARDWARE_UNSUPPORTED - -- Hardware (-220..-229) ----------------------------------------------- */
    ERROR_CODE_HARDWARE_UNSUPPORTED = 220,
    /** ERROR_CODE_INSUFFICIENT_MEMORY - RAC_ERROR_INSUFFICIENT_MEMORY (alias: RAC_ERROR_OUT_OF_MEMORY) */
    ERROR_CODE_INSUFFICIENT_MEMORY = 221,
    /** ERROR_CODE_COMPONENT_NOT_READY - -- Component state (-230..-249) --------------------------------------- */
    ERROR_CODE_COMPONENT_NOT_READY = 230,
    /** ERROR_CODE_INVALID_STATE - RAC_ERROR_INVALID_STATE */
    ERROR_CODE_INVALID_STATE = 231,
    /** ERROR_CODE_SERVICE_NOT_AVAILABLE - RAC_ERROR_SERVICE_NOT_AVAILABLE */
    ERROR_CODE_SERVICE_NOT_AVAILABLE = 232,
    /** ERROR_CODE_SERVICE_BUSY - RAC_ERROR_SERVICE_BUSY */
    ERROR_CODE_SERVICE_BUSY = 233,
    /** ERROR_CODE_PROCESSING_FAILED - RAC_ERROR_PROCESSING_FAILED */
    ERROR_CODE_PROCESSING_FAILED = 234,
    /** ERROR_CODE_START_FAILED - RAC_ERROR_START_FAILED */
    ERROR_CODE_START_FAILED = 235,
    /** ERROR_CODE_NOT_SUPPORTED - RAC_ERROR_NOT_SUPPORTED */
    ERROR_CODE_NOT_SUPPORTED = 236,
    /** ERROR_CODE_VALIDATION_FAILED - -- Validation (-250..-279) -------------------------------------------- */
    ERROR_CODE_VALIDATION_FAILED = 250,
    /** ERROR_CODE_INVALID_INPUT - RAC_ERROR_INVALID_INPUT */
    ERROR_CODE_INVALID_INPUT = 251,
    /** ERROR_CODE_INVALID_FORMAT - RAC_ERROR_INVALID_FORMAT */
    ERROR_CODE_INVALID_FORMAT = 252,
    /** ERROR_CODE_EMPTY_INPUT - RAC_ERROR_EMPTY_INPUT */
    ERROR_CODE_EMPTY_INPUT = 253,
    /** ERROR_CODE_TEXT_TOO_LONG - RAC_ERROR_TEXT_TOO_LONG */
    ERROR_CODE_TEXT_TOO_LONG = 254,
    /** ERROR_CODE_INVALID_SSML - RAC_ERROR_INVALID_SSML */
    ERROR_CODE_INVALID_SSML = 255,
    /** ERROR_CODE_INVALID_SPEAKING_RATE - RAC_ERROR_INVALID_SPEAKING_RATE */
    ERROR_CODE_INVALID_SPEAKING_RATE = 256,
    /** ERROR_CODE_INVALID_PITCH - RAC_ERROR_INVALID_PITCH */
    ERROR_CODE_INVALID_PITCH = 257,
    /** ERROR_CODE_INVALID_VOLUME - RAC_ERROR_INVALID_VOLUME */
    ERROR_CODE_INVALID_VOLUME = 258,
    /** ERROR_CODE_INVALID_ARGUMENT - RAC_ERROR_INVALID_ARGUMENT */
    ERROR_CODE_INVALID_ARGUMENT = 259,
    /** ERROR_CODE_NULL_POINTER - RAC_ERROR_NULL_POINTER */
    ERROR_CODE_NULL_POINTER = 260,
    /** ERROR_CODE_BUFFER_TOO_SMALL - RAC_ERROR_BUFFER_TOO_SMALL */
    ERROR_CODE_BUFFER_TOO_SMALL = 261,
    /** ERROR_CODE_OUTPUT_TRUNCATED - RAC_ERROR_OUTPUT_TRUNCATED */
    ERROR_CODE_OUTPUT_TRUNCATED = 262,
    /** ERROR_CODE_AUDIO_FORMAT_NOT_SUPPORTED - -- Audio (-280..-299) ------------------------------------------------- */
    ERROR_CODE_AUDIO_FORMAT_NOT_SUPPORTED = 280,
    /** ERROR_CODE_AUDIO_SESSION_FAILED - RAC_ERROR_AUDIO_SESSION_FAILED */
    ERROR_CODE_AUDIO_SESSION_FAILED = 281,
    /** ERROR_CODE_MICROPHONE_PERMISSION_DENIED - RAC_ERROR_MICROPHONE_PERMISSION_DENIED */
    ERROR_CODE_MICROPHONE_PERMISSION_DENIED = 282,
    /** ERROR_CODE_INSUFFICIENT_AUDIO_DATA - RAC_ERROR_INSUFFICIENT_AUDIO_DATA */
    ERROR_CODE_INSUFFICIENT_AUDIO_DATA = 283,
    /** ERROR_CODE_EMPTY_AUDIO_BUFFER - RAC_ERROR_EMPTY_AUDIO_BUFFER */
    ERROR_CODE_EMPTY_AUDIO_BUFFER = 284,
    /** ERROR_CODE_AUDIO_SESSION_ACTIVATION_FAILED - RAC_ERROR_AUDIO_SESSION_ACTIVATION_FAILED */
    ERROR_CODE_AUDIO_SESSION_ACTIVATION_FAILED = 285,
    /** ERROR_CODE_LANGUAGE_NOT_SUPPORTED - -- Language / voice (-300..-319) -------------------------------------- */
    ERROR_CODE_LANGUAGE_NOT_SUPPORTED = 300,
    /** ERROR_CODE_VOICE_NOT_AVAILABLE - RAC_ERROR_VOICE_NOT_AVAILABLE */
    ERROR_CODE_VOICE_NOT_AVAILABLE = 301,
    /** ERROR_CODE_STREAMING_NOT_SUPPORTED - RAC_ERROR_STREAMING_NOT_SUPPORTED */
    ERROR_CODE_STREAMING_NOT_SUPPORTED = 302,
    /** ERROR_CODE_STREAM_CANCELLED - RAC_ERROR_STREAM_CANCELLED */
    ERROR_CODE_STREAM_CANCELLED = 303,
    /** ERROR_CODE_AUTHENTICATION_FAILED - -- Authentication (-320..-329) ---------------------------------------- */
    ERROR_CODE_AUTHENTICATION_FAILED = 320,
    /** ERROR_CODE_UNAUTHORIZED - RAC_ERROR_UNAUTHORIZED */
    ERROR_CODE_UNAUTHORIZED = 321,
    /** ERROR_CODE_FORBIDDEN - RAC_ERROR_FORBIDDEN */
    ERROR_CODE_FORBIDDEN = 322,
    /** ERROR_CODE_KEYCHAIN_ERROR - -- Security (-330..-349) ---------------------------------------------- */
    ERROR_CODE_KEYCHAIN_ERROR = 330,
    /** ERROR_CODE_ENCODING_ERROR - RAC_ERROR_ENCODING_ERROR */
    ERROR_CODE_ENCODING_ERROR = 331,
    /** ERROR_CODE_DECODING_ERROR - RAC_ERROR_DECODING_ERROR */
    ERROR_CODE_DECODING_ERROR = 332,
    /** ERROR_CODE_SECURE_STORAGE_FAILED - RAC_ERROR_SECURE_STORAGE_FAILED */
    ERROR_CODE_SECURE_STORAGE_FAILED = 333,
    /** ERROR_CODE_EXTRACTION_FAILED - -- Extraction (-350..-369) -------------------------------------------- */
    ERROR_CODE_EXTRACTION_FAILED = 350,
    /** ERROR_CODE_CHECKSUM_MISMATCH - RAC_ERROR_CHECKSUM_MISMATCH */
    ERROR_CODE_CHECKSUM_MISMATCH = 351,
    /** ERROR_CODE_UNSUPPORTED_ARCHIVE - RAC_ERROR_UNSUPPORTED_ARCHIVE */
    ERROR_CODE_UNSUPPORTED_ARCHIVE = 352,
    /** ERROR_CODE_CALIBRATION_FAILED - -- Calibration (-370..-379) ------------------------------------------- */
    ERROR_CODE_CALIBRATION_FAILED = 370,
    /** ERROR_CODE_CALIBRATION_TIMEOUT - RAC_ERROR_CALIBRATION_TIMEOUT */
    ERROR_CODE_CALIBRATION_TIMEOUT = 371,
    /** ERROR_CODE_CANCELLED - -- Cancellation (-380..-389) ------------------------------------------ */
    ERROR_CODE_CANCELLED = 380,
    /** ERROR_CODE_MODULE_NOT_FOUND - -- Module / service (-400..-499) -------------------------------------- */
    ERROR_CODE_MODULE_NOT_FOUND = 400,
    /** ERROR_CODE_MODULE_ALREADY_REGISTERED - RAC_ERROR_MODULE_ALREADY_REGISTERED */
    ERROR_CODE_MODULE_ALREADY_REGISTERED = 401,
    /** ERROR_CODE_MODULE_LOAD_FAILED - RAC_ERROR_MODULE_LOAD_FAILED */
    ERROR_CODE_MODULE_LOAD_FAILED = 402,
    /** ERROR_CODE_SERVICE_NOT_FOUND - RAC_ERROR_SERVICE_NOT_FOUND */
    ERROR_CODE_SERVICE_NOT_FOUND = 410,
    /** ERROR_CODE_SERVICE_ALREADY_REGISTERED - RAC_ERROR_SERVICE_ALREADY_REGISTERED */
    ERROR_CODE_SERVICE_ALREADY_REGISTERED = 411,
    /** ERROR_CODE_SERVICE_CREATE_FAILED - RAC_ERROR_SERVICE_CREATE_FAILED */
    ERROR_CODE_SERVICE_CREATE_FAILED = 412,
    /** ERROR_CODE_CAPABILITY_NOT_FOUND - RAC_ERROR_CAPABILITY_NOT_FOUND */
    ERROR_CODE_CAPABILITY_NOT_FOUND = 420,
    /** ERROR_CODE_PROVIDER_NOT_FOUND - RAC_ERROR_PROVIDER_NOT_FOUND */
    ERROR_CODE_PROVIDER_NOT_FOUND = 421,
    /** ERROR_CODE_NO_CAPABLE_PROVIDER - RAC_ERROR_NO_CAPABLE_PROVIDER */
    ERROR_CODE_NO_CAPABLE_PROVIDER = 422,
    /** ERROR_CODE_NOT_FOUND - RAC_ERROR_NOT_FOUND */
    ERROR_CODE_NOT_FOUND = 423,
    /** ERROR_CODE_ADAPTER_NOT_SET - -- Platform adapter (-500..-599) -------------------------------------- */
    ERROR_CODE_ADAPTER_NOT_SET = 500,
    /** ERROR_CODE_BACKEND_NOT_FOUND - -- Backend (-600..-699) ----------------------------------------------- */
    ERROR_CODE_BACKEND_NOT_FOUND = 600,
    /** ERROR_CODE_BACKEND_NOT_READY - RAC_ERROR_BACKEND_NOT_READY */
    ERROR_CODE_BACKEND_NOT_READY = 601,
    /** ERROR_CODE_BACKEND_INIT_FAILED - RAC_ERROR_BACKEND_INIT_FAILED */
    ERROR_CODE_BACKEND_INIT_FAILED = 602,
    /** ERROR_CODE_BACKEND_BUSY - RAC_ERROR_BACKEND_BUSY */
    ERROR_CODE_BACKEND_BUSY = 603,
    /** ERROR_CODE_BACKEND_UNAVAILABLE - RAC_ERROR_BACKEND_UNAVAILABLE */
    ERROR_CODE_BACKEND_UNAVAILABLE = 604,
    /** ERROR_CODE_RUNTIME_UNAVAILABLE - RAC_ERROR_RUNTIME_UNAVAILABLE */
    ERROR_CODE_RUNTIME_UNAVAILABLE = 605,
    /** ERROR_CODE_BACKEND_ERROR - RAC_ERROR_BACKEND_ERROR (generic backend failure) */
    ERROR_CODE_BACKEND_ERROR = 606,
    /** ERROR_CODE_INVALID_HANDLE - RAC_ERROR_INVALID_HANDLE */
    ERROR_CODE_INVALID_HANDLE = 610,
    /** ERROR_CODE_EVENT_INVALID_CATEGORY - -- Event (-700..-799) ------------------------------------------------- */
    ERROR_CODE_EVENT_INVALID_CATEGORY = 700,
    /** ERROR_CODE_EVENT_SUBSCRIPTION_FAILED - RAC_ERROR_EVENT_SUBSCRIPTION_FAILED */
    ERROR_CODE_EVENT_SUBSCRIPTION_FAILED = 701,
    /** ERROR_CODE_EVENT_PUBLISH_FAILED - RAC_ERROR_EVENT_PUBLISH_FAILED */
    ERROR_CODE_EVENT_PUBLISH_FAILED = 702,
    /** ERROR_CODE_NOT_IMPLEMENTED - -- Other (-800..-899) ------------------------------------------------- */
    ERROR_CODE_NOT_IMPLEMENTED = 800,
    /** ERROR_CODE_FEATURE_NOT_AVAILABLE - RAC_ERROR_FEATURE_NOT_AVAILABLE */
    ERROR_CODE_FEATURE_NOT_AVAILABLE = 801,
    /** ERROR_CODE_FRAMEWORK_NOT_AVAILABLE - RAC_ERROR_FRAMEWORK_NOT_AVAILABLE */
    ERROR_CODE_FRAMEWORK_NOT_AVAILABLE = 802,
    /** ERROR_CODE_UNSUPPORTED_MODALITY - RAC_ERROR_UNSUPPORTED_MODALITY */
    ERROR_CODE_UNSUPPORTED_MODALITY = 803,
    /** ERROR_CODE_UNKNOWN - RAC_ERROR_UNKNOWN */
    ERROR_CODE_UNKNOWN = 804,
    /** ERROR_CODE_INTERNAL - RAC_ERROR_INTERNAL */
    ERROR_CODE_INTERNAL = 805,
    /** ERROR_CODE_ABI_VERSION_MISMATCH - -- Plugin (-810..-829) ------------------------------------------------ */
    ERROR_CODE_ABI_VERSION_MISMATCH = 810,
    /** ERROR_CODE_CAPABILITY_UNSUPPORTED - RAC_ERROR_CAPABILITY_UNSUPPORTED */
    ERROR_CODE_CAPABILITY_UNSUPPORTED = 811,
    /** ERROR_CODE_PLUGIN_DUPLICATE - RAC_ERROR_PLUGIN_DUPLICATE */
    ERROR_CODE_PLUGIN_DUPLICATE = 812,
    /** ERROR_CODE_PLUGIN_LOAD_FAILED - RAC_ERROR_PLUGIN_LOAD_FAILED */
    ERROR_CODE_PLUGIN_LOAD_FAILED = 820,
    /** ERROR_CODE_PLUGIN_BUSY - RAC_ERROR_PLUGIN_BUSY */
    ERROR_CODE_PLUGIN_BUSY = 821,
    /**
     * ERROR_CODE_WASM_LOAD_FAILED - -- Web-only WASM codes (-900..-903) -----------------------------------
     * The C ABI reserves -900..-999 for future use. The Web SDK currently
     * squats four codes here for WASM bridge failures; codegen tags these
     * as platform=web only. They are preserved verbatim so existing Web
     * consumers don't break, but new SDKs SHOULD NOT emit them.
     * Source: sdk/runanywhere-web/packages/core/src/Foundation/ErrorTypes.ts:58
     */
    ERROR_CODE_WASM_LOAD_FAILED = 900,
    ERROR_CODE_WASM_NOT_LOADED = 901,
    ERROR_CODE_WASM_CALLBACK_ERROR = 902,
    ERROR_CODE_WASM_MEMORY_ERROR = 903,
    UNRECOGNIZED = -1
}
export declare function errorCodeFromJSON(object: any): ErrorCode;
export declare function errorCodeToJSON(object: ErrorCode): string;
/**
 * Debugging metadata captured at the throw site. Stack traces are deliberately
 * absent: they are platform-shaped and belong in platform-local logging.
 */
export interface ErrorContext {
    /** Telemetry tagging. */
    metadata: {
        [key: string]: string;
    };
    sourceFile?: string | undefined;
    sourceLine?: number | undefined;
    /**
     * Logical operation ("loadModel", "generate", "transcribeStream"), so
     * clients can route without parsing free text.
     */
    operation?: string | undefined;
    /**
     * "<Message>.<field>" for validation errors. The generated validate()
     * emits this.
     */
    fieldPath?: string | undefined;
}
export interface ErrorContext_MetadataEntry {
    key: string;
    value: string;
}
/**
 * The unified error payload every SDK throws or returns.
 *
 * `code` is always non-zero: an SDKError implies failure, and success is
 * signalled by its absence. `message` is non-localized; localization is a
 * consumer concern.
 */
export interface SDKError {
    code: ErrorCode;
    category: ErrorCategory;
    message: string;
    context?: ErrorContext | undefined;
    /**
     * Signed rac_result_t. Equals -code for codes <= 899. Unset for the
     * Web-only WASM codes (>= 900), which have no C ABI counterpart, and for
     * failures originating outside the C ABI.
     */
    cAbiCode?: number | undefined;
    /** The "caused by" chain. */
    nestedMessage?: string | undefined;
    /**
     * `component` is a stable lowercase key ("llm", "stt", "rag", "download").
     * SDKEvent carries the enum-typed component instead.
     */
    timestampMs: number;
    severity: ErrorSeverity;
    component: string;
    retryable: boolean;
    remediationHint: string;
    correlationId: string;
}
export declare const ErrorContext: MessageFns<ErrorContext>;
export declare const ErrorContext_MetadataEntry: MessageFns<ErrorContext_MetadataEntry>;
export declare const SDKError: MessageFns<SDKError>;
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
