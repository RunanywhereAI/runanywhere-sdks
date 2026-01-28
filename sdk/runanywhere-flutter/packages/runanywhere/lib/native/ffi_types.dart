// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// =============================================================================
/// RunAnywhere Commons FFI Type Definitions
///
/// Dart FFI types matching the C API defined in rac_*.h headers
/// from runanywhere-commons library.
/// =============================================================================

// =============================================================================
// Basic Types (from rac_types.h)
// =============================================================================

/// Opaque handle for internal objects (rac_handle_t)
typedef RacHandle = Pointer<Void>;

/// Result type for all RAC functions (rac_result_t)
/// 0 = success, negative = error
typedef RacResult = Int32;

/// Boolean type for C compatibility (rac_bool_t)
typedef RacBool = Int32;

/// RAC boolean values
const int RAC_TRUE = 1;
const int RAC_FALSE = 0;

/// RAC success value
const int RAC_SUCCESS = 0;

// =============================================================================
// Result Codes (from rac_error.h)
// =============================================================================

/// Error codes matching rac_error.h
abstract class RacResultCode {
  // Success
  static const int success = 0;

  // Initialization errors (-100 to -109)
  static const int errorNotInitialized = -100;
  static const int errorAlreadyInitialized = -101;
  static const int errorInitializationFailed = -102;
  static const int errorInvalidConfiguration = -103;
  static const int errorInvalidApiKey = -104;
  static const int errorEnvironmentMismatch = -105;
  static const int errorInvalidParameter = -106;

  // Model errors (-110 to -129)
  static const int errorModelNotFound = -110;
  static const int errorModelLoadFailed = -111;
  static const int errorModelValidationFailed = -112;
  static const int errorModelIncompatible = -113;
  static const int errorInvalidModelFormat = -114;
  static const int errorModelStorageCorrupted = -115;
  static const int errorModelNotLoaded = -116;

  // Generation errors (-130 to -149)
  static const int errorGenerationFailed = -130;
  static const int errorGenerationTimeout = -131;
  static const int errorContextTooLong = -132;
  static const int errorTokenLimitExceeded = -133;
  static const int errorCostLimitExceeded = -134;
  static const int errorInferenceFailed = -135;

  // Network errors (-150 to -179)
  static const int errorNetworkUnavailable = -150;
  static const int errorNetworkError = -151;
  static const int errorRequestFailed = -152;
  static const int errorDownloadFailed = -153;
  static const int errorServerError = -154;
  static const int errorTimeout = -155;
  static const int errorInvalidResponse = -156;
  static const int errorHttpError = -157;
  static const int errorConnectionLost = -158;
  static const int errorPartialDownload = -159;

  // Storage errors (-180 to -219)
  static const int errorInsufficientStorage = -180;
  static const int errorStorageFull = -181;
  static const int errorStorageError = -182;
  static const int errorFileNotFound = -183;
  static const int errorFileReadFailed = -184;
  static const int errorFileWriteFailed = -185;
  static const int errorPermissionDenied = -186;
  static const int errorDeleteFailed = -187;
  static const int errorMoveFailed = -188;
  static const int errorDirectoryCreationFailed = -189;

  // Hardware errors (-220 to -229)
  static const int errorHardwareUnsupported = -220;
  static const int errorInsufficientMemory = -221;

  // Component state errors (-230 to -249)
  static const int errorComponentNotReady = -230;
  static const int errorInvalidState = -231;
  static const int errorServiceNotAvailable = -232;
  static const int errorServiceBusy = -233;
  static const int errorProcessingFailed = -234;
  static const int errorStartFailed = -235;
  static const int errorNotSupported = -236;

  // Validation errors (-250 to -279)
  static const int errorValidationFailed = -250;
  static const int errorInvalidInput = -251;
  static const int errorInvalidFormat = -252;
  static const int errorEmptyInput = -253;

  // Audio errors (-280 to -299)
  static const int errorAudioFormatNotSupported = -280;
  static const int errorAudioSessionFailed = -281;
  static const int errorMicrophonePermissionDenied = -282;
  static const int errorInsufficientAudioData = -283;

  // Language/voice errors (-300 to -319)
  static const int errorLanguageNotSupported = -300;
  static const int errorVoiceNotAvailable = -301;
  static const int errorStreamingNotSupported = -302;
  static const int errorStreamCancelled = -303;

  // Cancellation (-380 to -389)
  static const int errorCancelled = -380;

  // Module/service errors (-400 to -499)
  static const int errorModuleNotFound = -400;
  static const int errorModuleAlreadyRegistered = -401;
  static const int errorModuleLoadFailed = -402;
  static const int errorServiceNotFound = -410;
  static const int errorServiceAlreadyRegistered = -411;
  static const int errorServiceCreateFailed = -412;
  static const int errorCapabilityNotFound = -420;
  static const int errorProviderNotFound = -421;
  static const int errorNoCapableProvider = -422;
  static const int errorNotFound = -423;

  // Platform adapter errors (-500 to -599)
  static const int errorAdapterNotSet = -500;

  // Backend errors (-600 to -699)
  static const int errorBackendNotFound = -600;
  static const int errorBackendNotReady = -601;
  static const int errorBackendInitFailed = -602;
  static const int errorBackendBusy = -603;
  static const int errorInvalidHandle = -610;

  // Other errors (-800 to -899)
  static const int errorNotImplemented = -800;
  static const int errorFeatureNotAvailable = -801;
  static const int errorFrameworkNotAvailable = -802;
  static const int errorUnsupportedModality = -803;
  static const int errorUnknown = -804;
  static const int errorInternal = -805;

  /// Get human-readable message for an error code
  static String getMessage(int code) {
    switch (code) {
      case success:
        return 'Success';
      case errorNotInitialized:
        return 'Not initialized';
      case errorAlreadyInitialized:
        return 'Already initialized';
      case errorInitializationFailed:
        return 'Initialization failed';
      case errorInvalidConfiguration:
        return 'Invalid configuration';
      case errorModelNotFound:
        return 'Model not found';
      case errorModelLoadFailed:
        return 'Model load failed';
      case errorModelNotLoaded:
        return 'Model not loaded';
      case errorGenerationFailed:
        return 'Generation failed';
      case errorInferenceFailed:
        return 'Inference failed';
      case errorNetworkUnavailable:
        return 'Network unavailable';
      case errorDownloadFailed:
        return 'Download failed';
      case errorTimeout:
        return 'Timeout';
      case errorFileNotFound:
        return 'File not found';
      case errorInsufficientMemory:
        return 'Insufficient memory';
      case errorNotSupported:
        return 'Not supported';
      case errorCancelled:
        return 'Cancelled';
      case errorModuleNotFound:
        return 'Module not found';
      case errorModuleAlreadyRegistered:
        return 'Module already registered';
      case errorServiceNotFound:
        return 'Service not found';
      case errorBackendNotFound:
        return 'Backend not found';
      case errorInvalidHandle:
        return 'Invalid handle';
      case errorNotImplemented:
        return 'Not implemented';
      case errorUnknown:
        return 'Unknown error';
      default:
        return 'Error (code: $code)';
    }
  }
}

/// Alias for backward compatibility
typedef RaResultCode = RacResultCode;

// =============================================================================
// Capability Types (from rac_types.h)
// =============================================================================

/// Capability types supported by backends (rac_capability_t)
abstract class RacCapability {
  static const int unknown = 0;
  static const int textGeneration = 1;
  static const int embeddings = 2;
  static const int stt = 3;
  static const int tts = 4;
  static const int vad = 5;
  static const int diarization = 6;

  static String getName(int type) {
    switch (type) {
      case textGeneration:
        return 'Text Generation';
      case embeddings:
        return 'Embeddings';
      case stt:
        return 'Speech-to-Text';
      case tts:
        return 'Text-to-Speech';
      case vad:
        return 'Voice Activity Detection';
      case diarization:
        return 'Speaker Diarization';
      default:
        return 'Unknown';
    }
  }
}

// =============================================================================
// Device Types (from rac_types.h)
// =============================================================================

/// Device type for backend execution (rac_device_t)
abstract class RacDevice {
  static const int cpu = 0;
  static const int gpu = 1;
  static const int npu = 2;
  static const int auto = 3;

  static String getName(int type) {
    switch (type) {
      case cpu:
        return 'CPU';
      case gpu:
        return 'GPU';
      case npu:
        return 'NPU';
      case auto:
        return 'Auto';
      default:
        return 'Unknown';
    }
  }
}

// =============================================================================
// Log Levels (from rac_types.h)
// =============================================================================

/// Log level for logging callback (rac_log_level_t)
abstract class RacLogLevel {
  static const int trace = 0;
  static const int debug = 1;
  static const int info = 2;
  static const int warning = 3;
  static const int error = 4;
  static const int fatal = 5;
}

// =============================================================================
// Audio Format (from rac_stt_types.h)
// =============================================================================

/// Audio format enumeration (rac_audio_format_enum_t)
abstract class RacAudioFormat {
  static const int pcm = 0;
  static const int wav = 1;
  static const int mp3 = 2;
  static const int opus = 3;
  static const int aac = 4;
  static const int flac = 5;
}

// =============================================================================
// Speech Activity (from rac_vad_types.h)
// =============================================================================

/// Speech activity event type (rac_speech_activity_t)
abstract class RacSpeechActivity {
  static const int started = 0;
  static const int ended = 1;
  static const int ongoing = 2;
}

// =============================================================================
// Core API Function Signatures (from rac_core.h)
// =============================================================================

/// rac_result_t rac_init(const rac_config_t* config)
typedef RacInitNative = Int32 Function(Pointer<Void> config);
typedef RacInitDart = int Function(Pointer<Void> config);

/// void rac_shutdown(void)
typedef RacShutdownNative = Void Function();
typedef RacShutdownDart = void Function();

/// rac_bool_t rac_is_initialized(void)
typedef RacIsInitializedNative = Int32 Function();
typedef RacIsInitializedDart = int Function();

/// rac_result_t rac_configure_logging(rac_environment_t environment)
typedef RacConfigureLoggingNative = Int32 Function(Int32 environment);
typedef RacConfigureLoggingDart = int Function(int environment);

// =============================================================================
// Module Registration API (from rac_core.h)
// =============================================================================

/// rac_result_t rac_module_register(const rac_module_info_t* info)
typedef RacModuleRegisterNative = Int32 Function(Pointer<Void> info);
typedef RacModuleRegisterDart = int Function(Pointer<Void> info);

/// rac_result_t rac_module_unregister(const char* module_id)
typedef RacModuleUnregisterNative = Int32 Function(Pointer<Utf8> moduleId);
typedef RacModuleUnregisterDart = int Function(Pointer<Utf8> moduleId);

/// rac_result_t rac_module_list(const rac_module_info_t** out_modules, size_t* out_count)
typedef RacModuleListNative = Int32 Function(
  Pointer<Pointer<Void>> outModules,
  Pointer<IntPtr> outCount,
);
typedef RacModuleListDart = int Function(
  Pointer<Pointer<Void>> outModules,
  Pointer<IntPtr> outCount,
);

// =============================================================================
// Service Provider API (from rac_core.h)
// =============================================================================

/// rac_result_t rac_service_register_provider(const rac_service_provider_t* provider)
typedef RacServiceRegisterProviderNative = Int32 Function(
    Pointer<Void> provider);
typedef RacServiceRegisterProviderDart = int Function(Pointer<Void> provider);

/// rac_result_t rac_service_create(rac_capability_t capability, const rac_service_request_t* request, rac_handle_t* out_handle)
typedef RacServiceCreateNative = Int32 Function(
  Int32 capability,
  Pointer<Void> request,
  Pointer<RacHandle> outHandle,
);
typedef RacServiceCreateDart = int Function(
  int capability,
  Pointer<Void> request,
  Pointer<RacHandle> outHandle,
);

// =============================================================================
// LLM API Function Signatures (from rac_llm_llamacpp.h)
// =============================================================================

/// rac_result_t rac_backend_llamacpp_register(void)
typedef RacBackendLlamacppRegisterNative = Int32 Function();
typedef RacBackendLlamacppRegisterDart = int Function();

/// rac_result_t rac_backend_llamacpp_unregister(void)
typedef RacBackendLlamacppUnregisterNative = Int32 Function();
typedef RacBackendLlamacppUnregisterDart = int Function();

// =============================================================================
// LLM Component API Function Signatures (from rac_llm_component.h)
// =============================================================================

/// rac_result_t rac_llm_component_create(rac_handle_t* out_handle)
typedef RacLlmComponentCreateNative = Int32 Function(
  Pointer<RacHandle> outHandle,
);
typedef RacLlmComponentCreateDart = int Function(
  Pointer<RacHandle> outHandle,
);

/// rac_result_t rac_llm_component_load_model(rac_handle_t handle, const char* model_path, const char* model_id, const char* model_name)
typedef RacLlmComponentLoadModelNative = Int32 Function(
  RacHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> modelId,
  Pointer<Utf8> modelName,
);
typedef RacLlmComponentLoadModelDart = int Function(
  RacHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> modelId,
  Pointer<Utf8> modelName,
);

/// rac_bool_t rac_llm_component_is_loaded(rac_handle_t handle)
typedef RacLlmComponentIsLoadedNative = Int32 Function(RacHandle handle);
typedef RacLlmComponentIsLoadedDart = int Function(RacHandle handle);

/// const char* rac_llm_component_get_model_id(rac_handle_t handle)
typedef RacLlmComponentGetModelIdNative = Pointer<Utf8> Function(
    RacHandle handle);
typedef RacLlmComponentGetModelIdDart = Pointer<Utf8> Function(RacHandle handle);

/// rac_result_t rac_llm_component_generate(rac_handle_t handle, const char* prompt, const rac_llm_options_t* options, rac_llm_result_t* out_result)
typedef RacLlmComponentGenerateNative = Int32 Function(
  RacHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Void> options,
  Pointer<Void> outResult,
);
typedef RacLlmComponentGenerateDart = int Function(
  RacHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Void> options,
  Pointer<Void> outResult,
);

/// LLM streaming token callback signature
/// rac_bool_t (*rac_llm_component_token_callback_fn)(const char* token, void* user_data)
typedef RacLlmComponentTokenCallbackNative = Int32 Function(
  Pointer<Utf8> token,
  Pointer<Void> userData,
);

/// LLM streaming complete callback signature
typedef RacLlmComponentCompleteCallbackNative = Void Function(
  Pointer<Void> result,
  Pointer<Void> userData,
);

/// LLM streaming error callback signature
typedef RacLlmComponentErrorCallbackNative = Void Function(
  Int32 errorCode,
  Pointer<Utf8> errorMessage,
  Pointer<Void> userData,
);

/// rac_result_t rac_llm_component_generate_stream(...)
typedef RacLlmComponentGenerateStreamNative = Int32 Function(
  RacHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Void> options,
  Pointer<NativeFunction<RacLlmComponentTokenCallbackNative>> tokenCallback,
  Pointer<NativeFunction<RacLlmComponentCompleteCallbackNative>>
      completeCallback,
  Pointer<NativeFunction<RacLlmComponentErrorCallbackNative>> errorCallback,
  Pointer<Void> userData,
);
typedef RacLlmComponentGenerateStreamDart = int Function(
  RacHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Void> options,
  Pointer<NativeFunction<RacLlmComponentTokenCallbackNative>> tokenCallback,
  Pointer<NativeFunction<RacLlmComponentCompleteCallbackNative>>
      completeCallback,
  Pointer<NativeFunction<RacLlmComponentErrorCallbackNative>> errorCallback,
  Pointer<Void> userData,
);

/// rac_result_t rac_llm_component_cancel(rac_handle_t handle)
typedef RacLlmComponentCancelNative = Int32 Function(RacHandle handle);
typedef RacLlmComponentCancelDart = int Function(RacHandle handle);

/// rac_result_t rac_llm_component_unload(rac_handle_t handle)
typedef RacLlmComponentUnloadNative = Int32 Function(RacHandle handle);
typedef RacLlmComponentUnloadDart = int Function(RacHandle handle);

/// rac_result_t rac_llm_component_cleanup(rac_handle_t handle)
typedef RacLlmComponentCleanupNative = Int32 Function(RacHandle handle);
typedef RacLlmComponentCleanupDart = int Function(RacHandle handle);

/// void rac_llm_component_destroy(rac_handle_t handle)
typedef RacLlmComponentDestroyNative = Void Function(RacHandle handle);
typedef RacLlmComponentDestroyDart = void Function(RacHandle handle);

// Legacy aliases for backward compatibility (unused - remove after migration)
typedef RacLlmStreamCallbackNative = RacLlmComponentTokenCallbackNative;

// =============================================================================
// STT ONNX API Function Signatures (from rac_stt_onnx.h)
// =============================================================================

/// rac_result_t rac_stt_onnx_create(const char* model_path, const rac_stt_onnx_config_t* config, rac_handle_t* out_handle)
typedef RacSttOnnxCreateNative = Int32 Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);
typedef RacSttOnnxCreateDart = int Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);

/// rac_result_t rac_stt_onnx_transcribe(rac_handle_t handle, const float* audio_samples, size_t num_samples, const rac_stt_options_t* options, rac_stt_result_t* out_result)
typedef RacSttOnnxTranscribeNative = Int32 Function(
  RacHandle handle,
  Pointer<Float> audioSamples,
  IntPtr numSamples,
  Pointer<Void> options,
  Pointer<Void> outResult,
);
typedef RacSttOnnxTranscribeDart = int Function(
  RacHandle handle,
  Pointer<Float> audioSamples,
  int numSamples,
  Pointer<Void> options,
  Pointer<Void> outResult,
);

/// rac_bool_t rac_stt_onnx_supports_streaming(rac_handle_t handle)
typedef RacSttOnnxSupportsStreamingNative = Int32 Function(RacHandle handle);
typedef RacSttOnnxSupportsStreamingDart = int Function(RacHandle handle);

/// rac_result_t rac_stt_onnx_create_stream(rac_handle_t handle, rac_handle_t* out_stream)
typedef RacSttOnnxCreateStreamNative = Int32 Function(
  RacHandle handle,
  Pointer<RacHandle> outStream,
);
typedef RacSttOnnxCreateStreamDart = int Function(
  RacHandle handle,
  Pointer<RacHandle> outStream,
);

/// rac_result_t rac_stt_onnx_feed_audio(rac_handle_t handle, rac_handle_t stream, const float* audio_samples, size_t num_samples)
typedef RacSttOnnxFeedAudioNative = Int32 Function(
  RacHandle handle,
  RacHandle stream,
  Pointer<Float> audioSamples,
  IntPtr numSamples,
);
typedef RacSttOnnxFeedAudioDart = int Function(
  RacHandle handle,
  RacHandle stream,
  Pointer<Float> audioSamples,
  int numSamples,
);

/// rac_bool_t rac_stt_onnx_stream_is_ready(rac_handle_t handle, rac_handle_t stream)
typedef RacSttOnnxStreamIsReadyNative = Int32 Function(
  RacHandle handle,
  RacHandle stream,
);
typedef RacSttOnnxStreamIsReadyDart = int Function(
  RacHandle handle,
  RacHandle stream,
);

/// rac_result_t rac_stt_onnx_decode_stream(rac_handle_t handle, rac_handle_t stream, char** out_text)
typedef RacSttOnnxDecodeStreamNative = Int32 Function(
  RacHandle handle,
  RacHandle stream,
  Pointer<Pointer<Utf8>> outText,
);
typedef RacSttOnnxDecodeStreamDart = int Function(
  RacHandle handle,
  RacHandle stream,
  Pointer<Pointer<Utf8>> outText,
);

/// void rac_stt_onnx_input_finished(rac_handle_t handle, rac_handle_t stream)
typedef RacSttOnnxInputFinishedNative = Void Function(
  RacHandle handle,
  RacHandle stream,
);
typedef RacSttOnnxInputFinishedDart = void Function(
  RacHandle handle,
  RacHandle stream,
);

/// rac_bool_t rac_stt_onnx_is_endpoint(rac_handle_t handle, rac_handle_t stream)
typedef RacSttOnnxIsEndpointNative = Int32 Function(
  RacHandle handle,
  RacHandle stream,
);
typedef RacSttOnnxIsEndpointDart = int Function(
  RacHandle handle,
  RacHandle stream,
);

/// void rac_stt_onnx_destroy_stream(rac_handle_t handle, rac_handle_t stream)
typedef RacSttOnnxDestroyStreamNative = Void Function(
  RacHandle handle,
  RacHandle stream,
);
typedef RacSttOnnxDestroyStreamDart = void Function(
  RacHandle handle,
  RacHandle stream,
);

/// void rac_stt_onnx_destroy(rac_handle_t handle)
typedef RacSttOnnxDestroyNative = Void Function(RacHandle handle);
typedef RacSttOnnxDestroyDart = void Function(RacHandle handle);

// =============================================================================
// TTS ONNX API Function Signatures (from rac_tts_onnx.h)
// =============================================================================

/// rac_result_t rac_tts_onnx_create(const char* model_path, const rac_tts_onnx_config_t* config, rac_handle_t* out_handle)
typedef RacTtsOnnxCreateNative = Int32 Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);
typedef RacTtsOnnxCreateDart = int Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);

/// rac_result_t rac_tts_onnx_synthesize(rac_handle_t handle, const char* text, const rac_tts_options_t* options, rac_tts_result_t* out_result)
typedef RacTtsOnnxSynthesizeNative = Int32 Function(
  RacHandle handle,
  Pointer<Utf8> text,
  Pointer<Void> options,
  Pointer<Void> outResult,
);
typedef RacTtsOnnxSynthesizeDart = int Function(
  RacHandle handle,
  Pointer<Utf8> text,
  Pointer<Void> options,
  Pointer<Void> outResult,
);

/// rac_result_t rac_tts_onnx_get_voices(rac_handle_t handle, char*** out_voices, size_t* out_count)
typedef RacTtsOnnxGetVoicesNative = Int32 Function(
  RacHandle handle,
  Pointer<Pointer<Pointer<Utf8>>> outVoices,
  Pointer<IntPtr> outCount,
);
typedef RacTtsOnnxGetVoicesDart = int Function(
  RacHandle handle,
  Pointer<Pointer<Pointer<Utf8>>> outVoices,
  Pointer<IntPtr> outCount,
);

/// void rac_tts_onnx_stop(rac_handle_t handle)
typedef RacTtsOnnxStopNative = Void Function(RacHandle handle);
typedef RacTtsOnnxStopDart = void Function(RacHandle handle);

/// void rac_tts_onnx_destroy(rac_handle_t handle)
typedef RacTtsOnnxDestroyNative = Void Function(RacHandle handle);
typedef RacTtsOnnxDestroyDart = void Function(RacHandle handle);

// =============================================================================
// VAD ONNX Functions (from rac_vad_onnx.h)
// =============================================================================

/// rac_result_t rac_vad_onnx_create(const char* model_path, const rac_vad_onnx_config_t* config, rac_handle_t* out_handle)
typedef RacVadOnnxCreateNative = Int32 Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);
typedef RacVadOnnxCreateDart = int Function(
  Pointer<Utf8> modelPath,
  Pointer<Void> config,
  Pointer<RacHandle> outHandle,
);

/// rac_result_t rac_vad_onnx_process(rac_handle_t handle, const float* samples, size_t num_samples, rac_vad_result_t* out_result)
typedef RacVadOnnxProcessNative = Int32 Function(
  RacHandle handle,
  Pointer<Float> samples,
  IntPtr numSamples,
  Pointer<Void> outResult,
);
typedef RacVadOnnxProcessDart = int Function(
  RacHandle handle,
  Pointer<Float> samples,
  int numSamples,
  Pointer<Void> outResult,
);

/// void rac_vad_onnx_destroy(rac_handle_t handle)
typedef RacVadOnnxDestroyNative = Void Function(RacHandle handle);
typedef RacVadOnnxDestroyDart = void Function(RacHandle handle);

// =============================================================================
// Memory Management (from rac_types.h)
// =============================================================================

/// void rac_free(void* ptr)
typedef RacFreeNative = Void Function(Pointer<Void> ptr);
typedef RacFreeDart = void Function(Pointer<Void> ptr);

/// void* rac_alloc(size_t size)
typedef RacAllocNative = Pointer<Void> Function(IntPtr size);
typedef RacAllocDart = Pointer<Void> Function(int size);

/// char* rac_strdup(const char* str)
typedef RacStrdupNative = Pointer<Utf8> Function(Pointer<Utf8> str);
typedef RacStrdupDart = Pointer<Utf8> Function(Pointer<Utf8> str);

// =============================================================================
// Error API (from rac_error.h)
// =============================================================================

/// const char* rac_error_message(rac_result_t error_code)
typedef RacErrorMessageNative = Pointer<Utf8> Function(Int32 errorCode);
typedef RacErrorMessageDart = Pointer<Utf8> Function(int errorCode);

/// const char* rac_error_get_details(void)
typedef RacErrorGetDetailsNative = Pointer<Utf8> Function();
typedef RacErrorGetDetailsDart = Pointer<Utf8> Function();

/// void rac_error_set_details(const char* details)
typedef RacErrorSetDetailsNative = Void Function(Pointer<Utf8> details);
typedef RacErrorSetDetailsDart = void Function(Pointer<Utf8> details);

/// void rac_error_clear_details(void)
typedef RacErrorClearDetailsNative = Void Function();
typedef RacErrorClearDetailsDart = void Function();

// =============================================================================
// Platform Adapter Callbacks (from rac_platform_adapter.h)
// =============================================================================

/// File exists callback: rac_bool_t (*file_exists)(const char* path, void* user_data)
typedef RacFileExistsCallbackNative = Int32 Function(
  Pointer<Utf8> path,
  Pointer<Void> userData,
);

/// File read callback: rac_result_t (*file_read)(const char* path, void** out_data, size_t* out_size, void* user_data)
typedef RacFileReadCallbackNative = Int32 Function(
  Pointer<Utf8> path,
  Pointer<Pointer<Void>> outData,
  Pointer<IntPtr> outSize,
  Pointer<Void> userData,
);

/// File write callback: rac_result_t (*file_write)(const char* path, const void* data, size_t size, void* user_data)
typedef RacFileWriteCallbackNative = Int32 Function(
  Pointer<Utf8> path,
  Pointer<Void> data,
  IntPtr size,
  Pointer<Void> userData,
);

/// File delete callback: rac_result_t (*file_delete)(const char* path, void* user_data)
typedef RacFileDeleteCallbackNative = Int32 Function(
  Pointer<Utf8> path,
  Pointer<Void> userData,
);

/// Secure get callback: rac_result_t (*secure_get)(const char* key, char** out_value, void* user_data)
typedef RacSecureGetCallbackNative = Int32 Function(
  Pointer<Utf8> key,
  Pointer<Pointer<Utf8>> outValue,
  Pointer<Void> userData,
);

/// Secure set callback: rac_result_t (*secure_set)(const char* key, const char* value, void* user_data)
typedef RacSecureSetCallbackNative = Int32 Function(
  Pointer<Utf8> key,
  Pointer<Utf8> value,
  Pointer<Void> userData,
);

/// Secure delete callback: rac_result_t (*secure_delete)(const char* key, void* user_data)
typedef RacSecureDeleteCallbackNative = Int32 Function(
  Pointer<Utf8> key,
  Pointer<Void> userData,
);

/// Log callback: void (*log)(rac_log_level_t level, const char* category, const char* message, void* user_data)
typedef RacLogCallbackNative = Void Function(
  Int32 level,
  Pointer<Utf8> category,
  Pointer<Utf8> message,
  Pointer<Void> userData,
);

/// Track error callback: void (*track_error)(const char* error_json, void* user_data)
typedef RacTrackErrorCallbackNative = Void Function(
  Pointer<Utf8> errorJson,
  Pointer<Void> userData,
);

/// Now ms callback: int64_t (*now_ms)(void* user_data)
typedef RacNowMsCallbackNative = Int64 Function(Pointer<Void> userData);

/// Get memory info callback: rac_result_t (*get_memory_info)(rac_memory_info_t* out_info, void* user_data)
typedef RacGetMemoryInfoCallbackNative = Int32 Function(
  Pointer<Void> outInfo,
  Pointer<Void> userData,
);

/// HTTP progress callback: void (*progress)(int64_t bytes_downloaded, int64_t total_bytes, void* callback_user_data)
typedef RacHttpProgressCallbackNative = Void Function(
  Int64 bytesDownloaded,
  Int64 totalBytes,
  Pointer<Void> callbackUserData,
);

/// HTTP complete callback: void (*complete)(rac_result_t result, const char* downloaded_path, void* callback_user_data)
typedef RacHttpCompleteCallbackNative = Void Function(
  Int32 result,
  Pointer<Utf8> downloadedPath,
  Pointer<Void> callbackUserData,
);

// =============================================================================
// Structs (using FFI Struct for native memory layout)
// =============================================================================

/// Platform adapter struct matching rac_platform_adapter_t
/// Note: This is a complex struct - for simplicity we use Pointer<Void> in FFI calls
/// and manage the struct manually in Dart
base class RacPlatformAdapterStruct extends Struct {
  external Pointer<NativeFunction<RacFileExistsCallbackNative>> fileExists;
  external Pointer<NativeFunction<RacFileReadCallbackNative>> fileRead;
  external Pointer<NativeFunction<RacFileWriteCallbackNative>> fileWrite;
  external Pointer<NativeFunction<RacFileDeleteCallbackNative>> fileDelete;
  external Pointer<NativeFunction<RacSecureGetCallbackNative>> secureGet;
  external Pointer<NativeFunction<RacSecureSetCallbackNative>> secureSet;
  external Pointer<NativeFunction<RacSecureDeleteCallbackNative>> secureDelete;
  external Pointer<NativeFunction<RacLogCallbackNative>> log;
  external Pointer<NativeFunction<RacTrackErrorCallbackNative>> trackError;
  external Pointer<NativeFunction<RacNowMsCallbackNative>> nowMs;
  external Pointer<NativeFunction<RacGetMemoryInfoCallbackNative>>
      getMemoryInfo;
  external Pointer<Void> httpDownload;
  external Pointer<Void> httpDownloadCancel;
  external Pointer<Void> extractArchive;
  external Pointer<Void> userData;
}

/// Memory info struct matching rac_memory_info_t
base class RacMemoryInfoStruct extends Struct {
  @Uint64()
  external int totalBytes;

  @Uint64()
  external int availableBytes;

  @Uint64()
  external int usedBytes;
}

/// Version info struct matching rac_version_t
base class RacVersionStruct extends Struct {
  @Uint16()
  external int major;

  @Uint16()
  external int minor;

  @Uint16()
  external int patch;

  external Pointer<Utf8> string;
}

/// LlamaCPP config struct matching rac_llm_llamacpp_config_t
base class RacLlmLlamacppConfigStruct extends Struct {
  @Int32()
  external int contextSize;

  @Int32()
  external int numThreads;

  @Int32()
  external int gpuLayers;

  @Int32()
  external int batchSize;
}

/// LLM options struct matching rac_llm_options_t
base class RacLlmOptionsStruct extends Struct {
  @Int32()
  external int maxTokens;

  @Float()
  external double temperature;

  @Float()
  external double topP;

  external Pointer<Pointer<Utf8>> stopSequences;

  @IntPtr()
  external int numStopSequences;

  @Int32()
  external int streamingEnabled;

  external Pointer<Utf8> systemPrompt;
}

/// LLM result struct matching rac_llm_result_t
base class RacLlmResultStruct extends Struct {
  external Pointer<Utf8> text;

  @Int32()
  external int promptTokens;

  @Int32()
  external int completionTokens;

  @Int32()
  external int totalTokens;

  @Int64()
  external int timeToFirstTokenMs;

  @Int64()
  external int totalTimeMs;

  @Float()
  external double tokensPerSecond;
}

/// STT ONNX config struct matching rac_stt_onnx_config_t
base class RacSttOnnxConfigStruct extends Struct {
  @Int32()
  external int modelType;

  @Int32()
  external int numThreads;

  @Int32()
  external int useCoreml;
}

/// TTS ONNX config struct matching rac_tts_onnx_config_t
base class RacTtsOnnxConfigStruct extends Struct {
  @Int32()
  external int numThreads;

  @Int32()
  external int useCoreml;

  @Int32()
  external int sampleRate;
}

/// STT ONNX result struct matching rac_stt_onnx_result_t
base class RacSttOnnxResultStruct extends Struct {
  external Pointer<Utf8> text;

  @Float()
  external double confidence;

  external Pointer<Utf8> language;

  @Int32()
  external int durationMs;
}

/// TTS ONNX result struct matching rac_tts_onnx_result_t
base class RacTtsOnnxResultStruct extends Struct {
  external Pointer<Float> audioSamples;

  @Int32()
  external int numSamples;

  @Int32()
  external int sampleRate;

  @Int32()
  external int durationMs;
}

/// VAD ONNX config struct matching rac_vad_onnx_config_t
base class RacVadOnnxConfigStruct extends Struct {
  @Int32()
  external int numThreads;

  @Int32()
  external int sampleRate;

  @Int32()
  external int windowSizeMs;

  @Float()
  external double threshold;
}

/// VAD ONNX result struct matching rac_vad_onnx_result_t
base class RacVadOnnxResultStruct extends Struct {
  @Int32()
  external int isSpeech;

  @Float()
  external double probability;
}

// =============================================================================
// Tool Calling FFI Types (from rac_tool_calling.h)
// =============================================================================

/// Parsed tool call from LLM output - matches rac_tool_call_t
base class RacToolCallStruct extends Struct {
  @Int32()
  external int hasToolCall;

  external Pointer<Utf8> toolName;

  external Pointer<Utf8> argumentsJson;

  external Pointer<Utf8> cleanText;

  @Int64()
  external int callId;
}

/// Tool calling options - matches rac_tool_calling_options_t
base class RacToolCallingOptionsStruct extends Struct {
  @Int32()
  external int maxToolCalls;

  @Int32()
  external int autoExecute;

  @Float()
  external double temperature;

  @Int32()
  external int maxTokens;

  external Pointer<Utf8> systemPrompt;

  @Int32()
  external int replaceSystemPrompt;

  @Int32()
  external int keepToolsAvailable;
}

/// Tool parameter type enum values - matches rac_tool_param_type_t
abstract class RacToolParamType {
  static const int string = 0;
  static const int number = 1;
  static const int boolean = 2;
  static const int object = 3;
  static const int array = 4;
}

// =============================================================================
// Backward Compatibility Aliases
// =============================================================================

/// Backward compatibility: old ra_* types map to new rac_* types
typedef RaBackendHandle = RacHandle;
typedef RaStreamHandle = RacHandle;

// =============================================================================
// Convenient Type Alias
// =============================================================================

/// Type alias for platform adapter struct
typedef RacPlatformAdapter = RacPlatformAdapterStruct;
