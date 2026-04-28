import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * ErrorCategory — coarse-grained logical grouping for filtering / analytics.
 *
 * This is the union of all categories declared across SDKs, condensed to the
 * minimum stable set. The task spec pins a 9-case enum (UNSPECIFIED, NETWORK,
 * VALIDATION, MODEL, COMPONENT, IO, AUTH, INTERNAL, CONFIGURATION); that set
 * covers every category currently in use except for the per-modality ones
 * (STT, TTS, LLM, VAD, VLM, etc.) which are intentionally folded into
 * COMPONENT. Per-modality routing is recovered at runtime from the source
 * of the failure (the `c_abi_code` numeric value uniquely identifies the
 * component) and from `ErrorContext.operation` — there is no need to encode
 * modality twice.
 *
 * Sources pre-IDL:
 *   C ABI   rac_structured_error.h:46  rac_error_category_t — 15 cases incl.
 *                                      stt/tts/llm/vad/vlm/etc.
 *   Swift   ErrorCategory.swift:11     16 cases incl. rag.
 *   Kotlin  ErrorCategory.kt:19        18 cases incl. CONFIGURATION,
 *                                      INITIALIZATION, FILE_RESOURCE,
 *                                      OPERATION, PLATFORM (no per-modality).
 *   Dart    error_category.dart:3      27 cases (superset).
 *   RN      ErrorCategory.ts:10        12 cases.
 *   Web     ErrorTypes.ts              (none — only SDKErrorCode exists).
 *
 * The drift here is severe — every SDK uses a different category vocabulary.
 * Codegen MUST collapse to the 9 canonical buckets below.
 * ---------------------------------------------------------------------------
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
/**
 * ---------------------------------------------------------------------------
 * ErrorCode — exhaustive enumeration of every distinct numeric error code in
 * the C ABI (`rac_result_t`).
 *
 * proto3 forbids negative enum values, so the proto enum holds POSITIVE
 * values that mirror the *absolute* magnitude of each C ABI code. The signed
 * `rac_result_t` numeric value is preserved on `SDKError.c_abi_code` so
 * platforms can round-trip the original C ABI integer. The naming scheme is:
 *
 *     ERROR_CODE_<NAME> = abs(RAC_ERROR_<NAME>)
 *
 * (e.g. RAC_ERROR_MODEL_NOT_FOUND = -110 → ERROR_CODE_MODEL_NOT_FOUND = 110)
 *
 * `ERROR_CODE_UNSPECIFIED = 0` covers proto3's required zero-default; the
 * C ABI's `RAC_SUCCESS = 0` is NOT an error and MUST NOT appear inside an
 * SDKError.code (an SDKError implies a failure; success is signalled by the
 * absence of an SDKError). The zero-value enum entry exists only because
 * proto3 mandates it.
 *
 * CRITICAL: Do not change the numeric values without coordinated
 * migrations across every SDK *and* the C ABI. Adding new values is safe;
 * removing or renumbering is a wire-format break.
 *
 * All values below are sourced from
 * `sdk/runanywhere-commons/include/rac/core/rac_error.h`. Aliases (codes
 * where the C ABI defines two distinct macro names for the same numeric
 * value) are documented inline; we pick one canonical name per numeric value
 * to keep proto enum values unique.
 * ---------------------------------------------------------------------------
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
    /** ERROR_CODE_ABI_VERSION_MISMATCH - -- Plugin (GAP 02 / GAP 03; -810..-829) ------------------------------- */
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
 * ---------------------------------------------------------------------------
 * ErrorContext — debugging metadata captured at the throw site.
 *
 * Sources pre-IDL:
 *   C ABI   rac_structured_error.h:102  rac_error_t fields source_file,
 *                                       source_line, source_function plus a
 *                                       rac_stack_frame_t[32] fixed-size
 *                                       stack capture and 3 custom k/v slots
 *                                       (custom_key1..3 / custom_value1..3).
 *                                       The fixed-shape custom slots flatten
 *                                       to a `metadata` map<string,string> in
 *                                       proto.
 *   Swift   ErrorContext.swift          (matches Dart equivalent).
 *   Kotlin  SDKError.kt                 No ErrorContext — uses Throwable.cause
 *                                       only. Will pick up source location
 *                                       from this proto on regeneration.
 *   Dart    error_context.dart:4        StackTrace? stackTrace, String file,
 *                                       int line, String function, DateTime
 *                                       timestamp, String threadInfo.
 *   RN      ErrorContext.ts:11          stackTrace[], file, line, function,
 *                                       timestamp, threadInfo.
 *   Web     ErrorTypes.ts               (no context type).
 *
 * Stack traces are intentionally NOT modeled here — they are platform-shaped
 * (string lines on RN/Dart, rac_stack_frame_t[] on C, StackTrace on Dart) and
 * belong in a platform-local logging path, not in the wire IDL. If the C ABI
 * ever ships symbolicated frames, add a `repeated StackFrame frames` field
 * guarded by a feature flag.
 * ---------------------------------------------------------------------------
 */
export interface ErrorContext {
    /**
     * Free-form key/value pairs for telemetry tagging. Maps onto the C ABI's
     * three custom_key/custom_value slots and Dart's `Map<String, dynamic>`
     * (after string-coercion).
     */
    metadata: {
        [key: string]: string;
    };
    /** __FILE__ at the throw site. C ABI cap is RAC_MAX_METADATA_STRING (256). */
    sourceFile?: string | undefined;
    /** __LINE__ at the throw site. */
    sourceLine?: number | undefined;
    /**
     * Logical operation name ("loadModel", "generate", "transcribeStream",
     * ...). Lets clients route on operation without parsing free-text.
     * Maps roughly onto Dart's `function` field and C ABI's source_function;
     * we use the more generic "operation" name because some platforms (C++,
     * Swift) symbolicate the function name from the stack frame instead.
     */
    operation?: string | undefined;
}
export interface ErrorContext_MetadataEntry {
    key: string;
    value: string;
}
/**
 * ---------------------------------------------------------------------------
 * SDKError — the unified error payload every SDK throws / returns.
 *
 * Sources pre-IDL:
 *   C ABI   rac_structured_error.h:102  rac_error_t (code, category, message,
 *                                       source location, stack trace,
 *                                       underlying_code, underlying_message,
 *                                       model_id, framework, session_id,
 *                                       timestamp_ms, 3 custom k/v slots).
 *   Swift   (no concrete SDKError type was located; Swift code uses
 *           ErrorCode + ErrorCategory + a SDKErrorProtocol shape that
 *           matches this message; the migrated Swift SDK in sdk/swift/ will
 *           be regenerated from this proto).
 *   Kotlin  SDKError.kt:27              data class (code, category, message,
 *                                       cause).
 *   Dart    sdk_error.dart:13           class SDKError (message, type,
 *                                       underlyingError, context).
 *   RN      SDKError.ts:147             class SDKError (code, legacyCode?,
 *                                       category, underlyingError, context,
 *                                       details?).
 *   Web     ErrorTypes.ts:68            class SDKError (code, details?).
 *
 * Wire contract:
 *   * `code` — required. Always non-zero (zero indicates success and there
 *     should be no SDKError to begin with). Codegen MUST refuse to emit
 *     ERROR_CODE_UNSPECIFIED at runtime.
 *   * `category` — required. Coarse routing bucket. May be UNSPECIFIED only
 *     when `code` itself doesn't fit any bucket cleanly (rare).
 *   * `message` — required, human-readable, non-localized. Localization is a
 *     consumer concern.
 *   * `context` — optional. Source location + telemetry metadata.
 *   * `c_abi_code` — optional. Negative `rac_result_t` integer from the C ABI
 *     (e.g. -110 for MODEL_NOT_FOUND). Allows lossless round-trip with the
 *     C ABI even when intermediate platforms (Kotlin, Dart, RN) use a
 *     positive-numbered local enum. If `code` is set, `c_abi_code` MUST
 *     equal `-int32(code)` for codes ≤ 899; for the Web-only WASM codes
 *     (≥ 900) `c_abi_code` is unset because no canonical C ABI value exists.
 *   * `nested_message` — optional. Underlying-error message as captured at
 *     wrap time. Mirrors Swift's RunAnywhereError.underlyingError.localizedDesc
 *     and Kotlin's Throwable.cause.message.
 * ---------------------------------------------------------------------------
 */
export interface SDKError {
    code: ErrorCode;
    category: ErrorCategory;
    message: string;
    context?: ErrorContext | undefined;
    /**
     * Negative rac_result_t value from the C ABI. May be negative; preserved
     * via int32 (proto3 int32 is signed). Unset when the failure originated
     * outside the C ABI (e.g. a pure-Web WASM failure).
     */
    cAbiCode?: number | undefined;
    /** Underlying error's message (the "caused by" chain), if any. */
    nestedMessage?: string | undefined;
}
export declare const ErrorContext: {
    encode(message: ErrorContext, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ErrorContext;
    fromJSON(object: any): ErrorContext;
    toJSON(message: ErrorContext): unknown;
    create<I extends Exact<DeepPartial<ErrorContext>, I>>(base?: I): ErrorContext;
    fromPartial<I extends Exact<DeepPartial<ErrorContext>, I>>(object: I): ErrorContext;
};
export declare const ErrorContext_MetadataEntry: {
    encode(message: ErrorContext_MetadataEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ErrorContext_MetadataEntry;
    fromJSON(object: any): ErrorContext_MetadataEntry;
    toJSON(message: ErrorContext_MetadataEntry): unknown;
    create<I extends Exact<DeepPartial<ErrorContext_MetadataEntry>, I>>(base?: I): ErrorContext_MetadataEntry;
    fromPartial<I extends Exact<DeepPartial<ErrorContext_MetadataEntry>, I>>(object: I): ErrorContext_MetadataEntry;
};
export declare const SDKError: {
    encode(message: SDKError, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): SDKError;
    fromJSON(object: any): SDKError;
    toJSON(message: SDKError): unknown;
    create<I extends Exact<DeepPartial<SDKError>, I>>(base?: I): SDKError;
    fromPartial<I extends Exact<DeepPartial<SDKError>, I>>(object: I): SDKError;
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
//# sourceMappingURL=errors.d.ts.map