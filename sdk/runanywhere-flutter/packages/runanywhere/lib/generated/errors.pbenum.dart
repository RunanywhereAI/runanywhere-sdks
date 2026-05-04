//
//  Generated code. Do not modify.
//  source: errors.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

///  ---------------------------------------------------------------------------
///  ErrorCategory — coarse-grained logical grouping for filtering / analytics.
///
///  This is the union of all categories declared across SDKs, condensed to the
///  minimum stable set. The task spec pins a 9-case enum (UNSPECIFIED, NETWORK,
///  VALIDATION, MODEL, COMPONENT, IO, AUTH, INTERNAL, CONFIGURATION); that set
///  covers every category currently in use except for the per-modality ones
///  (STT, TTS, LLM, VAD, VLM, etc.) which are intentionally folded into
///  COMPONENT. Per-modality routing is recovered at runtime from the source
///  of the failure (the `c_abi_code` numeric value uniquely identifies the
///  component) and from `ErrorContext.operation` — there is no need to encode
///  modality twice.
///
///  Sources pre-IDL:
///    C ABI   rac_structured_error.h:46  rac_error_category_t — 15 cases incl.
///                                       stt/tts/llm/vad/vlm/etc.
///    Swift   ErrorCategory.swift:11     16 cases incl. rag.
///    Kotlin  ErrorCategory.kt:19        18 cases incl. CONFIGURATION,
///                                       INITIALIZATION, FILE_RESOURCE,
///                                       OPERATION, PLATFORM (no per-modality).
///    Dart    error_category.dart:3      27 cases (superset).
///    RN      ErrorCategory.ts:10        12 cases.
///    Web     ErrorTypes.ts              (none — only SDKErrorCode exists).
///
///  The drift here is severe — every SDK uses a different category vocabulary.
///  Codegen MUST collapse to the 9 canonical buckets below.
///  ---------------------------------------------------------------------------
class ErrorCategory extends $pb.ProtobufEnum {
  static const ErrorCategory ERROR_CATEGORY_UNSPECIFIED = ErrorCategory._(0, _omitEnumNames ? '' : 'ERROR_CATEGORY_UNSPECIFIED');
  static const ErrorCategory ERROR_CATEGORY_NETWORK = ErrorCategory._(1, _omitEnumNames ? '' : 'ERROR_CATEGORY_NETWORK');
  static const ErrorCategory ERROR_CATEGORY_VALIDATION = ErrorCategory._(2, _omitEnumNames ? '' : 'ERROR_CATEGORY_VALIDATION');
  static const ErrorCategory ERROR_CATEGORY_MODEL = ErrorCategory._(3, _omitEnumNames ? '' : 'ERROR_CATEGORY_MODEL');
  static const ErrorCategory ERROR_CATEGORY_COMPONENT = ErrorCategory._(4, _omitEnumNames ? '' : 'ERROR_CATEGORY_COMPONENT');
  static const ErrorCategory ERROR_CATEGORY_IO = ErrorCategory._(5, _omitEnumNames ? '' : 'ERROR_CATEGORY_IO');
  static const ErrorCategory ERROR_CATEGORY_AUTH = ErrorCategory._(6, _omitEnumNames ? '' : 'ERROR_CATEGORY_AUTH');
  static const ErrorCategory ERROR_CATEGORY_INTERNAL = ErrorCategory._(7, _omitEnumNames ? '' : 'ERROR_CATEGORY_INTERNAL');
  static const ErrorCategory ERROR_CATEGORY_CONFIGURATION = ErrorCategory._(8, _omitEnumNames ? '' : 'ERROR_CATEGORY_CONFIGURATION');

  static const $core.List<ErrorCategory> values = <ErrorCategory> [
    ERROR_CATEGORY_UNSPECIFIED,
    ERROR_CATEGORY_NETWORK,
    ERROR_CATEGORY_VALIDATION,
    ERROR_CATEGORY_MODEL,
    ERROR_CATEGORY_COMPONENT,
    ERROR_CATEGORY_IO,
    ERROR_CATEGORY_AUTH,
    ERROR_CATEGORY_INTERNAL,
    ERROR_CATEGORY_CONFIGURATION,
  ];

  static final $core.Map<$core.int, ErrorCategory> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ErrorCategory? valueOf($core.int value) => _byValue[value];

  const ErrorCategory._($core.int v, $core.String n) : super(v, n);
}

class ErrorSeverity extends $pb.ProtobufEnum {
  static const ErrorSeverity ERROR_SEVERITY_UNSPECIFIED = ErrorSeverity._(0, _omitEnumNames ? '' : 'ERROR_SEVERITY_UNSPECIFIED');
  static const ErrorSeverity ERROR_SEVERITY_DEBUG = ErrorSeverity._(1, _omitEnumNames ? '' : 'ERROR_SEVERITY_DEBUG');
  static const ErrorSeverity ERROR_SEVERITY_INFO = ErrorSeverity._(2, _omitEnumNames ? '' : 'ERROR_SEVERITY_INFO');
  static const ErrorSeverity ERROR_SEVERITY_WARNING = ErrorSeverity._(3, _omitEnumNames ? '' : 'ERROR_SEVERITY_WARNING');
  static const ErrorSeverity ERROR_SEVERITY_ERROR = ErrorSeverity._(4, _omitEnumNames ? '' : 'ERROR_SEVERITY_ERROR');
  static const ErrorSeverity ERROR_SEVERITY_CRITICAL = ErrorSeverity._(5, _omitEnumNames ? '' : 'ERROR_SEVERITY_CRITICAL');

  static const $core.List<ErrorSeverity> values = <ErrorSeverity> [
    ERROR_SEVERITY_UNSPECIFIED,
    ERROR_SEVERITY_DEBUG,
    ERROR_SEVERITY_INFO,
    ERROR_SEVERITY_WARNING,
    ERROR_SEVERITY_ERROR,
    ERROR_SEVERITY_CRITICAL,
  ];

  static final $core.Map<$core.int, ErrorSeverity> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ErrorSeverity? valueOf($core.int value) => _byValue[value];

  const ErrorSeverity._($core.int v, $core.String n) : super(v, n);
}

///  ---------------------------------------------------------------------------
///  ErrorCode — exhaustive enumeration of every distinct numeric error code in
///  the C ABI (`rac_result_t`).
///
///  proto3 forbids negative enum values, so the proto enum holds POSITIVE
///  values that mirror the *absolute* magnitude of each C ABI code. The signed
///  `rac_result_t` numeric value is preserved on `SDKError.c_abi_code` so
///  platforms can round-trip the original C ABI integer. The naming scheme is:
///
///      ERROR_CODE_<NAME> = abs(RAC_ERROR_<NAME>)
///
///  (e.g. RAC_ERROR_MODEL_NOT_FOUND = -110 → ERROR_CODE_MODEL_NOT_FOUND = 110)
///
///  `ERROR_CODE_UNSPECIFIED = 0` covers proto3's required zero-default; the
///  C ABI's `RAC_SUCCESS = 0` is NOT an error and MUST NOT appear inside an
///  SDKError.code (an SDKError implies a failure; success is signalled by the
///  absence of an SDKError). The zero-value enum entry exists only because
///  proto3 mandates it.
///
///  CRITICAL: Do not change the numeric values without coordinated
///  migrations across every SDK *and* the C ABI. Adding new values is safe;
///  removing or renumbering is a wire-format break.
///
///  All values below are sourced from
///  `sdk/runanywhere-commons/include/rac/core/rac_error.h`. Aliases (codes
///  where the C ABI defines two distinct macro names for the same numeric
///  value) are documented inline; we pick one canonical name per numeric value
///  to keep proto enum values unique.
///  ---------------------------------------------------------------------------
class ErrorCode extends $pb.ProtobufEnum {
  static const ErrorCode ERROR_CODE_UNSPECIFIED = ErrorCode._(0, _omitEnumNames ? '' : 'ERROR_CODE_UNSPECIFIED');
  static const ErrorCode ERROR_CODE_NOT_INITIALIZED = ErrorCode._(100, _omitEnumNames ? '' : 'ERROR_CODE_NOT_INITIALIZED');
  static const ErrorCode ERROR_CODE_ALREADY_INITIALIZED = ErrorCode._(101, _omitEnumNames ? '' : 'ERROR_CODE_ALREADY_INITIALIZED');
  static const ErrorCode ERROR_CODE_INITIALIZATION_FAILED = ErrorCode._(102, _omitEnumNames ? '' : 'ERROR_CODE_INITIALIZATION_FAILED');
  static const ErrorCode ERROR_CODE_INVALID_CONFIGURATION = ErrorCode._(103, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_CONFIGURATION');
  static const ErrorCode ERROR_CODE_INVALID_API_KEY = ErrorCode._(104, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_API_KEY');
  static const ErrorCode ERROR_CODE_ENVIRONMENT_MISMATCH = ErrorCode._(105, _omitEnumNames ? '' : 'ERROR_CODE_ENVIRONMENT_MISMATCH');
  static const ErrorCode ERROR_CODE_INVALID_PARAMETER = ErrorCode._(106, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_PARAMETER');
  static const ErrorCode ERROR_CODE_MODEL_NOT_FOUND = ErrorCode._(110, _omitEnumNames ? '' : 'ERROR_CODE_MODEL_NOT_FOUND');
  static const ErrorCode ERROR_CODE_MODEL_LOAD_FAILED = ErrorCode._(111, _omitEnumNames ? '' : 'ERROR_CODE_MODEL_LOAD_FAILED');
  static const ErrorCode ERROR_CODE_MODEL_VALIDATION_FAILED = ErrorCode._(112, _omitEnumNames ? '' : 'ERROR_CODE_MODEL_VALIDATION_FAILED');
  static const ErrorCode ERROR_CODE_MODEL_INCOMPATIBLE = ErrorCode._(113, _omitEnumNames ? '' : 'ERROR_CODE_MODEL_INCOMPATIBLE');
  static const ErrorCode ERROR_CODE_INVALID_MODEL_FORMAT = ErrorCode._(114, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_MODEL_FORMAT');
  static const ErrorCode ERROR_CODE_MODEL_STORAGE_CORRUPTED = ErrorCode._(115, _omitEnumNames ? '' : 'ERROR_CODE_MODEL_STORAGE_CORRUPTED');
  static const ErrorCode ERROR_CODE_MODEL_NOT_LOADED = ErrorCode._(116, _omitEnumNames ? '' : 'ERROR_CODE_MODEL_NOT_LOADED');
  static const ErrorCode ERROR_CODE_GENERATION_FAILED = ErrorCode._(130, _omitEnumNames ? '' : 'ERROR_CODE_GENERATION_FAILED');
  static const ErrorCode ERROR_CODE_GENERATION_TIMEOUT = ErrorCode._(131, _omitEnumNames ? '' : 'ERROR_CODE_GENERATION_TIMEOUT');
  static const ErrorCode ERROR_CODE_CONTEXT_TOO_LONG = ErrorCode._(132, _omitEnumNames ? '' : 'ERROR_CODE_CONTEXT_TOO_LONG');
  static const ErrorCode ERROR_CODE_TOKEN_LIMIT_EXCEEDED = ErrorCode._(133, _omitEnumNames ? '' : 'ERROR_CODE_TOKEN_LIMIT_EXCEEDED');
  static const ErrorCode ERROR_CODE_COST_LIMIT_EXCEEDED = ErrorCode._(134, _omitEnumNames ? '' : 'ERROR_CODE_COST_LIMIT_EXCEEDED');
  static const ErrorCode ERROR_CODE_INFERENCE_FAILED = ErrorCode._(135, _omitEnumNames ? '' : 'ERROR_CODE_INFERENCE_FAILED');
  static const ErrorCode ERROR_CODE_NETWORK_UNAVAILABLE = ErrorCode._(150, _omitEnumNames ? '' : 'ERROR_CODE_NETWORK_UNAVAILABLE');
  static const ErrorCode ERROR_CODE_NETWORK_ERROR = ErrorCode._(151, _omitEnumNames ? '' : 'ERROR_CODE_NETWORK_ERROR');
  static const ErrorCode ERROR_CODE_REQUEST_FAILED = ErrorCode._(152, _omitEnumNames ? '' : 'ERROR_CODE_REQUEST_FAILED');
  static const ErrorCode ERROR_CODE_DOWNLOAD_FAILED = ErrorCode._(153, _omitEnumNames ? '' : 'ERROR_CODE_DOWNLOAD_FAILED');
  static const ErrorCode ERROR_CODE_SERVER_ERROR = ErrorCode._(154, _omitEnumNames ? '' : 'ERROR_CODE_SERVER_ERROR');
  static const ErrorCode ERROR_CODE_TIMEOUT = ErrorCode._(155, _omitEnumNames ? '' : 'ERROR_CODE_TIMEOUT');
  static const ErrorCode ERROR_CODE_INVALID_RESPONSE = ErrorCode._(156, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_RESPONSE');
  static const ErrorCode ERROR_CODE_HTTP_ERROR = ErrorCode._(157, _omitEnumNames ? '' : 'ERROR_CODE_HTTP_ERROR');
  static const ErrorCode ERROR_CODE_CONNECTION_LOST = ErrorCode._(158, _omitEnumNames ? '' : 'ERROR_CODE_CONNECTION_LOST');
  static const ErrorCode ERROR_CODE_PARTIAL_DOWNLOAD = ErrorCode._(159, _omitEnumNames ? '' : 'ERROR_CODE_PARTIAL_DOWNLOAD');
  static const ErrorCode ERROR_CODE_HTTP_REQUEST_FAILED = ErrorCode._(160, _omitEnumNames ? '' : 'ERROR_CODE_HTTP_REQUEST_FAILED');
  static const ErrorCode ERROR_CODE_HTTP_NOT_SUPPORTED = ErrorCode._(161, _omitEnumNames ? '' : 'ERROR_CODE_HTTP_NOT_SUPPORTED');
  static const ErrorCode ERROR_CODE_INSUFFICIENT_STORAGE = ErrorCode._(180, _omitEnumNames ? '' : 'ERROR_CODE_INSUFFICIENT_STORAGE');
  static const ErrorCode ERROR_CODE_STORAGE_FULL = ErrorCode._(181, _omitEnumNames ? '' : 'ERROR_CODE_STORAGE_FULL');
  static const ErrorCode ERROR_CODE_STORAGE_ERROR = ErrorCode._(182, _omitEnumNames ? '' : 'ERROR_CODE_STORAGE_ERROR');
  static const ErrorCode ERROR_CODE_FILE_NOT_FOUND = ErrorCode._(183, _omitEnumNames ? '' : 'ERROR_CODE_FILE_NOT_FOUND');
  static const ErrorCode ERROR_CODE_FILE_READ_FAILED = ErrorCode._(184, _omitEnumNames ? '' : 'ERROR_CODE_FILE_READ_FAILED');
  static const ErrorCode ERROR_CODE_FILE_WRITE_FAILED = ErrorCode._(185, _omitEnumNames ? '' : 'ERROR_CODE_FILE_WRITE_FAILED');
  static const ErrorCode ERROR_CODE_PERMISSION_DENIED = ErrorCode._(186, _omitEnumNames ? '' : 'ERROR_CODE_PERMISSION_DENIED');
  static const ErrorCode ERROR_CODE_DELETE_FAILED = ErrorCode._(187, _omitEnumNames ? '' : 'ERROR_CODE_DELETE_FAILED');
  static const ErrorCode ERROR_CODE_MOVE_FAILED = ErrorCode._(188, _omitEnumNames ? '' : 'ERROR_CODE_MOVE_FAILED');
  static const ErrorCode ERROR_CODE_DIRECTORY_CREATION_FAILED = ErrorCode._(189, _omitEnumNames ? '' : 'ERROR_CODE_DIRECTORY_CREATION_FAILED');
  static const ErrorCode ERROR_CODE_DIRECTORY_NOT_FOUND = ErrorCode._(190, _omitEnumNames ? '' : 'ERROR_CODE_DIRECTORY_NOT_FOUND');
  static const ErrorCode ERROR_CODE_INVALID_PATH = ErrorCode._(191, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_PATH');
  static const ErrorCode ERROR_CODE_INVALID_FILE_NAME = ErrorCode._(192, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_FILE_NAME');
  static const ErrorCode ERROR_CODE_TEMP_FILE_CREATION_FAILED = ErrorCode._(193, _omitEnumNames ? '' : 'ERROR_CODE_TEMP_FILE_CREATION_FAILED');
  static const ErrorCode ERROR_CODE_HARDWARE_UNSUPPORTED = ErrorCode._(220, _omitEnumNames ? '' : 'ERROR_CODE_HARDWARE_UNSUPPORTED');
  static const ErrorCode ERROR_CODE_INSUFFICIENT_MEMORY = ErrorCode._(221, _omitEnumNames ? '' : 'ERROR_CODE_INSUFFICIENT_MEMORY');
  static const ErrorCode ERROR_CODE_COMPONENT_NOT_READY = ErrorCode._(230, _omitEnumNames ? '' : 'ERROR_CODE_COMPONENT_NOT_READY');
  static const ErrorCode ERROR_CODE_INVALID_STATE = ErrorCode._(231, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_STATE');
  static const ErrorCode ERROR_CODE_SERVICE_NOT_AVAILABLE = ErrorCode._(232, _omitEnumNames ? '' : 'ERROR_CODE_SERVICE_NOT_AVAILABLE');
  static const ErrorCode ERROR_CODE_SERVICE_BUSY = ErrorCode._(233, _omitEnumNames ? '' : 'ERROR_CODE_SERVICE_BUSY');
  static const ErrorCode ERROR_CODE_PROCESSING_FAILED = ErrorCode._(234, _omitEnumNames ? '' : 'ERROR_CODE_PROCESSING_FAILED');
  static const ErrorCode ERROR_CODE_START_FAILED = ErrorCode._(235, _omitEnumNames ? '' : 'ERROR_CODE_START_FAILED');
  static const ErrorCode ERROR_CODE_NOT_SUPPORTED = ErrorCode._(236, _omitEnumNames ? '' : 'ERROR_CODE_NOT_SUPPORTED');
  static const ErrorCode ERROR_CODE_VALIDATION_FAILED = ErrorCode._(250, _omitEnumNames ? '' : 'ERROR_CODE_VALIDATION_FAILED');
  static const ErrorCode ERROR_CODE_INVALID_INPUT = ErrorCode._(251, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_INPUT');
  static const ErrorCode ERROR_CODE_INVALID_FORMAT = ErrorCode._(252, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_FORMAT');
  static const ErrorCode ERROR_CODE_EMPTY_INPUT = ErrorCode._(253, _omitEnumNames ? '' : 'ERROR_CODE_EMPTY_INPUT');
  static const ErrorCode ERROR_CODE_TEXT_TOO_LONG = ErrorCode._(254, _omitEnumNames ? '' : 'ERROR_CODE_TEXT_TOO_LONG');
  static const ErrorCode ERROR_CODE_INVALID_SSML = ErrorCode._(255, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_SSML');
  static const ErrorCode ERROR_CODE_INVALID_SPEAKING_RATE = ErrorCode._(256, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_SPEAKING_RATE');
  static const ErrorCode ERROR_CODE_INVALID_PITCH = ErrorCode._(257, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_PITCH');
  static const ErrorCode ERROR_CODE_INVALID_VOLUME = ErrorCode._(258, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_VOLUME');
  static const ErrorCode ERROR_CODE_INVALID_ARGUMENT = ErrorCode._(259, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_ARGUMENT');
  static const ErrorCode ERROR_CODE_NULL_POINTER = ErrorCode._(260, _omitEnumNames ? '' : 'ERROR_CODE_NULL_POINTER');
  static const ErrorCode ERROR_CODE_BUFFER_TOO_SMALL = ErrorCode._(261, _omitEnumNames ? '' : 'ERROR_CODE_BUFFER_TOO_SMALL');
  static const ErrorCode ERROR_CODE_AUDIO_FORMAT_NOT_SUPPORTED = ErrorCode._(280, _omitEnumNames ? '' : 'ERROR_CODE_AUDIO_FORMAT_NOT_SUPPORTED');
  static const ErrorCode ERROR_CODE_AUDIO_SESSION_FAILED = ErrorCode._(281, _omitEnumNames ? '' : 'ERROR_CODE_AUDIO_SESSION_FAILED');
  static const ErrorCode ERROR_CODE_MICROPHONE_PERMISSION_DENIED = ErrorCode._(282, _omitEnumNames ? '' : 'ERROR_CODE_MICROPHONE_PERMISSION_DENIED');
  static const ErrorCode ERROR_CODE_INSUFFICIENT_AUDIO_DATA = ErrorCode._(283, _omitEnumNames ? '' : 'ERROR_CODE_INSUFFICIENT_AUDIO_DATA');
  static const ErrorCode ERROR_CODE_EMPTY_AUDIO_BUFFER = ErrorCode._(284, _omitEnumNames ? '' : 'ERROR_CODE_EMPTY_AUDIO_BUFFER');
  static const ErrorCode ERROR_CODE_AUDIO_SESSION_ACTIVATION_FAILED = ErrorCode._(285, _omitEnumNames ? '' : 'ERROR_CODE_AUDIO_SESSION_ACTIVATION_FAILED');
  static const ErrorCode ERROR_CODE_LANGUAGE_NOT_SUPPORTED = ErrorCode._(300, _omitEnumNames ? '' : 'ERROR_CODE_LANGUAGE_NOT_SUPPORTED');
  static const ErrorCode ERROR_CODE_VOICE_NOT_AVAILABLE = ErrorCode._(301, _omitEnumNames ? '' : 'ERROR_CODE_VOICE_NOT_AVAILABLE');
  static const ErrorCode ERROR_CODE_STREAMING_NOT_SUPPORTED = ErrorCode._(302, _omitEnumNames ? '' : 'ERROR_CODE_STREAMING_NOT_SUPPORTED');
  static const ErrorCode ERROR_CODE_STREAM_CANCELLED = ErrorCode._(303, _omitEnumNames ? '' : 'ERROR_CODE_STREAM_CANCELLED');
  static const ErrorCode ERROR_CODE_AUTHENTICATION_FAILED = ErrorCode._(320, _omitEnumNames ? '' : 'ERROR_CODE_AUTHENTICATION_FAILED');
  static const ErrorCode ERROR_CODE_UNAUTHORIZED = ErrorCode._(321, _omitEnumNames ? '' : 'ERROR_CODE_UNAUTHORIZED');
  static const ErrorCode ERROR_CODE_FORBIDDEN = ErrorCode._(322, _omitEnumNames ? '' : 'ERROR_CODE_FORBIDDEN');
  static const ErrorCode ERROR_CODE_KEYCHAIN_ERROR = ErrorCode._(330, _omitEnumNames ? '' : 'ERROR_CODE_KEYCHAIN_ERROR');
  static const ErrorCode ERROR_CODE_ENCODING_ERROR = ErrorCode._(331, _omitEnumNames ? '' : 'ERROR_CODE_ENCODING_ERROR');
  static const ErrorCode ERROR_CODE_DECODING_ERROR = ErrorCode._(332, _omitEnumNames ? '' : 'ERROR_CODE_DECODING_ERROR');
  static const ErrorCode ERROR_CODE_SECURE_STORAGE_FAILED = ErrorCode._(333, _omitEnumNames ? '' : 'ERROR_CODE_SECURE_STORAGE_FAILED');
  static const ErrorCode ERROR_CODE_EXTRACTION_FAILED = ErrorCode._(350, _omitEnumNames ? '' : 'ERROR_CODE_EXTRACTION_FAILED');
  static const ErrorCode ERROR_CODE_CHECKSUM_MISMATCH = ErrorCode._(351, _omitEnumNames ? '' : 'ERROR_CODE_CHECKSUM_MISMATCH');
  static const ErrorCode ERROR_CODE_UNSUPPORTED_ARCHIVE = ErrorCode._(352, _omitEnumNames ? '' : 'ERROR_CODE_UNSUPPORTED_ARCHIVE');
  static const ErrorCode ERROR_CODE_CALIBRATION_FAILED = ErrorCode._(370, _omitEnumNames ? '' : 'ERROR_CODE_CALIBRATION_FAILED');
  static const ErrorCode ERROR_CODE_CALIBRATION_TIMEOUT = ErrorCode._(371, _omitEnumNames ? '' : 'ERROR_CODE_CALIBRATION_TIMEOUT');
  static const ErrorCode ERROR_CODE_CANCELLED = ErrorCode._(380, _omitEnumNames ? '' : 'ERROR_CODE_CANCELLED');
  static const ErrorCode ERROR_CODE_MODULE_NOT_FOUND = ErrorCode._(400, _omitEnumNames ? '' : 'ERROR_CODE_MODULE_NOT_FOUND');
  static const ErrorCode ERROR_CODE_MODULE_ALREADY_REGISTERED = ErrorCode._(401, _omitEnumNames ? '' : 'ERROR_CODE_MODULE_ALREADY_REGISTERED');
  static const ErrorCode ERROR_CODE_MODULE_LOAD_FAILED = ErrorCode._(402, _omitEnumNames ? '' : 'ERROR_CODE_MODULE_LOAD_FAILED');
  static const ErrorCode ERROR_CODE_SERVICE_NOT_FOUND = ErrorCode._(410, _omitEnumNames ? '' : 'ERROR_CODE_SERVICE_NOT_FOUND');
  static const ErrorCode ERROR_CODE_SERVICE_ALREADY_REGISTERED = ErrorCode._(411, _omitEnumNames ? '' : 'ERROR_CODE_SERVICE_ALREADY_REGISTERED');
  static const ErrorCode ERROR_CODE_SERVICE_CREATE_FAILED = ErrorCode._(412, _omitEnumNames ? '' : 'ERROR_CODE_SERVICE_CREATE_FAILED');
  static const ErrorCode ERROR_CODE_CAPABILITY_NOT_FOUND = ErrorCode._(420, _omitEnumNames ? '' : 'ERROR_CODE_CAPABILITY_NOT_FOUND');
  static const ErrorCode ERROR_CODE_PROVIDER_NOT_FOUND = ErrorCode._(421, _omitEnumNames ? '' : 'ERROR_CODE_PROVIDER_NOT_FOUND');
  static const ErrorCode ERROR_CODE_NO_CAPABLE_PROVIDER = ErrorCode._(422, _omitEnumNames ? '' : 'ERROR_CODE_NO_CAPABLE_PROVIDER');
  static const ErrorCode ERROR_CODE_NOT_FOUND = ErrorCode._(423, _omitEnumNames ? '' : 'ERROR_CODE_NOT_FOUND');
  static const ErrorCode ERROR_CODE_ADAPTER_NOT_SET = ErrorCode._(500, _omitEnumNames ? '' : 'ERROR_CODE_ADAPTER_NOT_SET');
  static const ErrorCode ERROR_CODE_BACKEND_NOT_FOUND = ErrorCode._(600, _omitEnumNames ? '' : 'ERROR_CODE_BACKEND_NOT_FOUND');
  static const ErrorCode ERROR_CODE_BACKEND_NOT_READY = ErrorCode._(601, _omitEnumNames ? '' : 'ERROR_CODE_BACKEND_NOT_READY');
  static const ErrorCode ERROR_CODE_BACKEND_INIT_FAILED = ErrorCode._(602, _omitEnumNames ? '' : 'ERROR_CODE_BACKEND_INIT_FAILED');
  static const ErrorCode ERROR_CODE_BACKEND_BUSY = ErrorCode._(603, _omitEnumNames ? '' : 'ERROR_CODE_BACKEND_BUSY');
  static const ErrorCode ERROR_CODE_BACKEND_UNAVAILABLE = ErrorCode._(604, _omitEnumNames ? '' : 'ERROR_CODE_BACKEND_UNAVAILABLE');
  static const ErrorCode ERROR_CODE_INVALID_HANDLE = ErrorCode._(610, _omitEnumNames ? '' : 'ERROR_CODE_INVALID_HANDLE');
  static const ErrorCode ERROR_CODE_EVENT_INVALID_CATEGORY = ErrorCode._(700, _omitEnumNames ? '' : 'ERROR_CODE_EVENT_INVALID_CATEGORY');
  static const ErrorCode ERROR_CODE_EVENT_SUBSCRIPTION_FAILED = ErrorCode._(701, _omitEnumNames ? '' : 'ERROR_CODE_EVENT_SUBSCRIPTION_FAILED');
  static const ErrorCode ERROR_CODE_EVENT_PUBLISH_FAILED = ErrorCode._(702, _omitEnumNames ? '' : 'ERROR_CODE_EVENT_PUBLISH_FAILED');
  static const ErrorCode ERROR_CODE_NOT_IMPLEMENTED = ErrorCode._(800, _omitEnumNames ? '' : 'ERROR_CODE_NOT_IMPLEMENTED');
  static const ErrorCode ERROR_CODE_FEATURE_NOT_AVAILABLE = ErrorCode._(801, _omitEnumNames ? '' : 'ERROR_CODE_FEATURE_NOT_AVAILABLE');
  static const ErrorCode ERROR_CODE_FRAMEWORK_NOT_AVAILABLE = ErrorCode._(802, _omitEnumNames ? '' : 'ERROR_CODE_FRAMEWORK_NOT_AVAILABLE');
  static const ErrorCode ERROR_CODE_UNSUPPORTED_MODALITY = ErrorCode._(803, _omitEnumNames ? '' : 'ERROR_CODE_UNSUPPORTED_MODALITY');
  static const ErrorCode ERROR_CODE_UNKNOWN = ErrorCode._(804, _omitEnumNames ? '' : 'ERROR_CODE_UNKNOWN');
  static const ErrorCode ERROR_CODE_INTERNAL = ErrorCode._(805, _omitEnumNames ? '' : 'ERROR_CODE_INTERNAL');
  static const ErrorCode ERROR_CODE_ABI_VERSION_MISMATCH = ErrorCode._(810, _omitEnumNames ? '' : 'ERROR_CODE_ABI_VERSION_MISMATCH');
  static const ErrorCode ERROR_CODE_CAPABILITY_UNSUPPORTED = ErrorCode._(811, _omitEnumNames ? '' : 'ERROR_CODE_CAPABILITY_UNSUPPORTED');
  static const ErrorCode ERROR_CODE_PLUGIN_DUPLICATE = ErrorCode._(812, _omitEnumNames ? '' : 'ERROR_CODE_PLUGIN_DUPLICATE');
  static const ErrorCode ERROR_CODE_PLUGIN_LOAD_FAILED = ErrorCode._(820, _omitEnumNames ? '' : 'ERROR_CODE_PLUGIN_LOAD_FAILED');
  static const ErrorCode ERROR_CODE_PLUGIN_BUSY = ErrorCode._(821, _omitEnumNames ? '' : 'ERROR_CODE_PLUGIN_BUSY');
  static const ErrorCode ERROR_CODE_WASM_LOAD_FAILED = ErrorCode._(900, _omitEnumNames ? '' : 'ERROR_CODE_WASM_LOAD_FAILED');
  static const ErrorCode ERROR_CODE_WASM_NOT_LOADED = ErrorCode._(901, _omitEnumNames ? '' : 'ERROR_CODE_WASM_NOT_LOADED');
  static const ErrorCode ERROR_CODE_WASM_CALLBACK_ERROR = ErrorCode._(902, _omitEnumNames ? '' : 'ERROR_CODE_WASM_CALLBACK_ERROR');
  static const ErrorCode ERROR_CODE_WASM_MEMORY_ERROR = ErrorCode._(903, _omitEnumNames ? '' : 'ERROR_CODE_WASM_MEMORY_ERROR');

  static const $core.List<ErrorCode> values = <ErrorCode> [
    ERROR_CODE_UNSPECIFIED,
    ERROR_CODE_NOT_INITIALIZED,
    ERROR_CODE_ALREADY_INITIALIZED,
    ERROR_CODE_INITIALIZATION_FAILED,
    ERROR_CODE_INVALID_CONFIGURATION,
    ERROR_CODE_INVALID_API_KEY,
    ERROR_CODE_ENVIRONMENT_MISMATCH,
    ERROR_CODE_INVALID_PARAMETER,
    ERROR_CODE_MODEL_NOT_FOUND,
    ERROR_CODE_MODEL_LOAD_FAILED,
    ERROR_CODE_MODEL_VALIDATION_FAILED,
    ERROR_CODE_MODEL_INCOMPATIBLE,
    ERROR_CODE_INVALID_MODEL_FORMAT,
    ERROR_CODE_MODEL_STORAGE_CORRUPTED,
    ERROR_CODE_MODEL_NOT_LOADED,
    ERROR_CODE_GENERATION_FAILED,
    ERROR_CODE_GENERATION_TIMEOUT,
    ERROR_CODE_CONTEXT_TOO_LONG,
    ERROR_CODE_TOKEN_LIMIT_EXCEEDED,
    ERROR_CODE_COST_LIMIT_EXCEEDED,
    ERROR_CODE_INFERENCE_FAILED,
    ERROR_CODE_NETWORK_UNAVAILABLE,
    ERROR_CODE_NETWORK_ERROR,
    ERROR_CODE_REQUEST_FAILED,
    ERROR_CODE_DOWNLOAD_FAILED,
    ERROR_CODE_SERVER_ERROR,
    ERROR_CODE_TIMEOUT,
    ERROR_CODE_INVALID_RESPONSE,
    ERROR_CODE_HTTP_ERROR,
    ERROR_CODE_CONNECTION_LOST,
    ERROR_CODE_PARTIAL_DOWNLOAD,
    ERROR_CODE_HTTP_REQUEST_FAILED,
    ERROR_CODE_HTTP_NOT_SUPPORTED,
    ERROR_CODE_INSUFFICIENT_STORAGE,
    ERROR_CODE_STORAGE_FULL,
    ERROR_CODE_STORAGE_ERROR,
    ERROR_CODE_FILE_NOT_FOUND,
    ERROR_CODE_FILE_READ_FAILED,
    ERROR_CODE_FILE_WRITE_FAILED,
    ERROR_CODE_PERMISSION_DENIED,
    ERROR_CODE_DELETE_FAILED,
    ERROR_CODE_MOVE_FAILED,
    ERROR_CODE_DIRECTORY_CREATION_FAILED,
    ERROR_CODE_DIRECTORY_NOT_FOUND,
    ERROR_CODE_INVALID_PATH,
    ERROR_CODE_INVALID_FILE_NAME,
    ERROR_CODE_TEMP_FILE_CREATION_FAILED,
    ERROR_CODE_HARDWARE_UNSUPPORTED,
    ERROR_CODE_INSUFFICIENT_MEMORY,
    ERROR_CODE_COMPONENT_NOT_READY,
    ERROR_CODE_INVALID_STATE,
    ERROR_CODE_SERVICE_NOT_AVAILABLE,
    ERROR_CODE_SERVICE_BUSY,
    ERROR_CODE_PROCESSING_FAILED,
    ERROR_CODE_START_FAILED,
    ERROR_CODE_NOT_SUPPORTED,
    ERROR_CODE_VALIDATION_FAILED,
    ERROR_CODE_INVALID_INPUT,
    ERROR_CODE_INVALID_FORMAT,
    ERROR_CODE_EMPTY_INPUT,
    ERROR_CODE_TEXT_TOO_LONG,
    ERROR_CODE_INVALID_SSML,
    ERROR_CODE_INVALID_SPEAKING_RATE,
    ERROR_CODE_INVALID_PITCH,
    ERROR_CODE_INVALID_VOLUME,
    ERROR_CODE_INVALID_ARGUMENT,
    ERROR_CODE_NULL_POINTER,
    ERROR_CODE_BUFFER_TOO_SMALL,
    ERROR_CODE_AUDIO_FORMAT_NOT_SUPPORTED,
    ERROR_CODE_AUDIO_SESSION_FAILED,
    ERROR_CODE_MICROPHONE_PERMISSION_DENIED,
    ERROR_CODE_INSUFFICIENT_AUDIO_DATA,
    ERROR_CODE_EMPTY_AUDIO_BUFFER,
    ERROR_CODE_AUDIO_SESSION_ACTIVATION_FAILED,
    ERROR_CODE_LANGUAGE_NOT_SUPPORTED,
    ERROR_CODE_VOICE_NOT_AVAILABLE,
    ERROR_CODE_STREAMING_NOT_SUPPORTED,
    ERROR_CODE_STREAM_CANCELLED,
    ERROR_CODE_AUTHENTICATION_FAILED,
    ERROR_CODE_UNAUTHORIZED,
    ERROR_CODE_FORBIDDEN,
    ERROR_CODE_KEYCHAIN_ERROR,
    ERROR_CODE_ENCODING_ERROR,
    ERROR_CODE_DECODING_ERROR,
    ERROR_CODE_SECURE_STORAGE_FAILED,
    ERROR_CODE_EXTRACTION_FAILED,
    ERROR_CODE_CHECKSUM_MISMATCH,
    ERROR_CODE_UNSUPPORTED_ARCHIVE,
    ERROR_CODE_CALIBRATION_FAILED,
    ERROR_CODE_CALIBRATION_TIMEOUT,
    ERROR_CODE_CANCELLED,
    ERROR_CODE_MODULE_NOT_FOUND,
    ERROR_CODE_MODULE_ALREADY_REGISTERED,
    ERROR_CODE_MODULE_LOAD_FAILED,
    ERROR_CODE_SERVICE_NOT_FOUND,
    ERROR_CODE_SERVICE_ALREADY_REGISTERED,
    ERROR_CODE_SERVICE_CREATE_FAILED,
    ERROR_CODE_CAPABILITY_NOT_FOUND,
    ERROR_CODE_PROVIDER_NOT_FOUND,
    ERROR_CODE_NO_CAPABLE_PROVIDER,
    ERROR_CODE_NOT_FOUND,
    ERROR_CODE_ADAPTER_NOT_SET,
    ERROR_CODE_BACKEND_NOT_FOUND,
    ERROR_CODE_BACKEND_NOT_READY,
    ERROR_CODE_BACKEND_INIT_FAILED,
    ERROR_CODE_BACKEND_BUSY,
    ERROR_CODE_BACKEND_UNAVAILABLE,
    ERROR_CODE_INVALID_HANDLE,
    ERROR_CODE_EVENT_INVALID_CATEGORY,
    ERROR_CODE_EVENT_SUBSCRIPTION_FAILED,
    ERROR_CODE_EVENT_PUBLISH_FAILED,
    ERROR_CODE_NOT_IMPLEMENTED,
    ERROR_CODE_FEATURE_NOT_AVAILABLE,
    ERROR_CODE_FRAMEWORK_NOT_AVAILABLE,
    ERROR_CODE_UNSUPPORTED_MODALITY,
    ERROR_CODE_UNKNOWN,
    ERROR_CODE_INTERNAL,
    ERROR_CODE_ABI_VERSION_MISMATCH,
    ERROR_CODE_CAPABILITY_UNSUPPORTED,
    ERROR_CODE_PLUGIN_DUPLICATE,
    ERROR_CODE_PLUGIN_LOAD_FAILED,
    ERROR_CODE_PLUGIN_BUSY,
    ERROR_CODE_WASM_LOAD_FAILED,
    ERROR_CODE_WASM_NOT_LOADED,
    ERROR_CODE_WASM_CALLBACK_ERROR,
    ERROR_CODE_WASM_MEMORY_ERROR,
  ];

  static final $core.Map<$core.int, ErrorCode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ErrorCode? valueOf($core.int value) => _byValue[value];

  const ErrorCode._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
