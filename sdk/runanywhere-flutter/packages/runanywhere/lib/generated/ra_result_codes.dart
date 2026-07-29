// GENERATED FILE — DO NOT EDIT.
// Regenerate with: idl/codegen/generate_dart_result_codes.py
//
// The C ABI returns idl/errors.proto codes negated as rac_result_t. These are
// the negated values, emitted as `const` so they can be used as `switch` cases
// and as `Pointer.fromFunction(exceptionalReturn:)` arguments, neither of which
// accepts a value read from a ProtobufEnum at runtime.

/// Result codes matching rac_error.h, generated from idl/errors.proto.
abstract final class RacResultCodes {
  static const int success                           = 0;  // ERROR_CODE_UNSPECIFIED
  static const int errorNotInitialized               = -100;  // ERROR_CODE_NOT_INITIALIZED
  static const int errorAlreadyInitialized           = -101;  // ERROR_CODE_ALREADY_INITIALIZED
  static const int errorInitializationFailed         = -102;  // ERROR_CODE_INITIALIZATION_FAILED
  static const int errorInvalidConfiguration         = -103;  // ERROR_CODE_INVALID_CONFIGURATION
  static const int errorInvalidApiKey                = -104;  // ERROR_CODE_INVALID_API_KEY
  static const int errorEnvironmentMismatch          = -105;  // ERROR_CODE_ENVIRONMENT_MISMATCH
  static const int errorInvalidParameter             = -106;  // ERROR_CODE_INVALID_PARAMETER
  static const int errorModelNotFound                = -110;  // ERROR_CODE_MODEL_NOT_FOUND
  static const int errorModelLoadFailed              = -111;  // ERROR_CODE_MODEL_LOAD_FAILED
  static const int errorModelValidationFailed        = -112;  // ERROR_CODE_MODEL_VALIDATION_FAILED
  static const int errorModelIncompatible            = -113;  // ERROR_CODE_MODEL_INCOMPATIBLE
  static const int errorInvalidModelFormat           = -114;  // ERROR_CODE_INVALID_MODEL_FORMAT
  static const int errorModelStorageCorrupted        = -115;  // ERROR_CODE_MODEL_STORAGE_CORRUPTED
  static const int errorModelNotLoaded               = -116;  // ERROR_CODE_MODEL_NOT_LOADED
  static const int errorGenerationFailed             = -130;  // ERROR_CODE_GENERATION_FAILED
  static const int errorGenerationTimeout            = -131;  // ERROR_CODE_GENERATION_TIMEOUT
  static const int errorContextTooLong               = -132;  // ERROR_CODE_CONTEXT_TOO_LONG
  static const int errorTokenLimitExceeded           = -133;  // ERROR_CODE_TOKEN_LIMIT_EXCEEDED
  static const int errorCostLimitExceeded            = -134;  // ERROR_CODE_COST_LIMIT_EXCEEDED
  static const int errorInferenceFailed              = -135;  // ERROR_CODE_INFERENCE_FAILED
  static const int errorGenerationCancelled          = -136;  // ERROR_CODE_GENERATION_CANCELLED
  static const int errorNetworkUnavailable           = -150;  // ERROR_CODE_NETWORK_UNAVAILABLE
  static const int errorNetworkError                 = -151;  // ERROR_CODE_NETWORK_ERROR
  static const int errorRequestFailed                = -152;  // ERROR_CODE_REQUEST_FAILED
  static const int errorDownloadFailed               = -153;  // ERROR_CODE_DOWNLOAD_FAILED
  static const int errorServerError                  = -154;  // ERROR_CODE_SERVER_ERROR
  static const int errorTimeout                      = -155;  // ERROR_CODE_TIMEOUT
  static const int errorInvalidResponse              = -156;  // ERROR_CODE_INVALID_RESPONSE
  static const int errorHttpError                    = -157;  // ERROR_CODE_HTTP_ERROR
  static const int errorConnectionLost               = -158;  // ERROR_CODE_CONNECTION_LOST
  static const int errorPartialDownload              = -159;  // ERROR_CODE_PARTIAL_DOWNLOAD
  static const int errorHttpRequestFailed            = -160;  // ERROR_CODE_HTTP_REQUEST_FAILED
  static const int errorHttpNotSupported             = -161;  // ERROR_CODE_HTTP_NOT_SUPPORTED
  static const int errorInsufficientStorage          = -180;  // ERROR_CODE_INSUFFICIENT_STORAGE
  static const int errorStorageFull                  = -181;  // ERROR_CODE_STORAGE_FULL
  static const int errorStorageError                 = -182;  // ERROR_CODE_STORAGE_ERROR
  static const int errorFileNotFound                 = -183;  // ERROR_CODE_FILE_NOT_FOUND
  static const int errorFileReadFailed               = -184;  // ERROR_CODE_FILE_READ_FAILED
  static const int errorFileWriteFailed              = -185;  // ERROR_CODE_FILE_WRITE_FAILED
  static const int errorPermissionDenied             = -186;  // ERROR_CODE_PERMISSION_DENIED
  static const int errorDeleteFailed                 = -187;  // ERROR_CODE_DELETE_FAILED
  static const int errorMoveFailed                   = -188;  // ERROR_CODE_MOVE_FAILED
  static const int errorDirectoryCreationFailed      = -189;  // ERROR_CODE_DIRECTORY_CREATION_FAILED
  static const int errorDirectoryNotFound            = -190;  // ERROR_CODE_DIRECTORY_NOT_FOUND
  static const int errorInvalidPath                  = -191;  // ERROR_CODE_INVALID_PATH
  static const int errorInvalidFileName              = -192;  // ERROR_CODE_INVALID_FILE_NAME
  static const int errorTempFileCreationFailed       = -193;  // ERROR_CODE_TEMP_FILE_CREATION_FAILED
  static const int errorHardwareUnsupported          = -220;  // ERROR_CODE_HARDWARE_UNSUPPORTED
  static const int errorInsufficientMemory           = -221;  // ERROR_CODE_INSUFFICIENT_MEMORY
  static const int errorComponentNotReady            = -230;  // ERROR_CODE_COMPONENT_NOT_READY
  static const int errorInvalidState                 = -231;  // ERROR_CODE_INVALID_STATE
  static const int errorServiceNotAvailable          = -232;  // ERROR_CODE_SERVICE_NOT_AVAILABLE
  static const int errorServiceBusy                  = -233;  // ERROR_CODE_SERVICE_BUSY
  static const int errorProcessingFailed             = -234;  // ERROR_CODE_PROCESSING_FAILED
  static const int errorStartFailed                  = -235;  // ERROR_CODE_START_FAILED
  static const int errorNotSupported                 = -236;  // ERROR_CODE_NOT_SUPPORTED
  static const int errorValidationFailed             = -250;  // ERROR_CODE_VALIDATION_FAILED
  static const int errorInvalidInput                 = -251;  // ERROR_CODE_INVALID_INPUT
  static const int errorInvalidFormat                = -252;  // ERROR_CODE_INVALID_FORMAT
  static const int errorEmptyInput                   = -253;  // ERROR_CODE_EMPTY_INPUT
  static const int errorTextTooLong                  = -254;  // ERROR_CODE_TEXT_TOO_LONG
  static const int errorInvalidSsml                  = -255;  // ERROR_CODE_INVALID_SSML
  static const int errorInvalidSpeakingRate          = -256;  // ERROR_CODE_INVALID_SPEAKING_RATE
  static const int errorInvalidPitch                 = -257;  // ERROR_CODE_INVALID_PITCH
  static const int errorInvalidVolume                = -258;  // ERROR_CODE_INVALID_VOLUME
  static const int errorInvalidArgument              = -259;  // ERROR_CODE_INVALID_ARGUMENT
  static const int errorNullPointer                  = -260;  // ERROR_CODE_NULL_POINTER
  static const int errorBufferTooSmall               = -261;  // ERROR_CODE_BUFFER_TOO_SMALL
  static const int errorOutputTruncated              = -262;  // ERROR_CODE_OUTPUT_TRUNCATED
  static const int errorAudioFormatNotSupported      = -280;  // ERROR_CODE_AUDIO_FORMAT_NOT_SUPPORTED
  static const int errorAudioSessionFailed           = -281;  // ERROR_CODE_AUDIO_SESSION_FAILED
  static const int errorMicrophonePermissionDenied   = -282;  // ERROR_CODE_MICROPHONE_PERMISSION_DENIED
  static const int errorInsufficientAudioData        = -283;  // ERROR_CODE_INSUFFICIENT_AUDIO_DATA
  static const int errorEmptyAudioBuffer             = -284;  // ERROR_CODE_EMPTY_AUDIO_BUFFER
  static const int errorAudioSessionActivationFailed = -285;  // ERROR_CODE_AUDIO_SESSION_ACTIVATION_FAILED
  static const int errorLanguageNotSupported         = -300;  // ERROR_CODE_LANGUAGE_NOT_SUPPORTED
  static const int errorVoiceNotAvailable            = -301;  // ERROR_CODE_VOICE_NOT_AVAILABLE
  static const int errorStreamingNotSupported        = -302;  // ERROR_CODE_STREAMING_NOT_SUPPORTED
  static const int errorStreamCancelled              = -303;  // ERROR_CODE_STREAM_CANCELLED
  static const int errorAuthenticationFailed         = -320;  // ERROR_CODE_AUTHENTICATION_FAILED
  static const int errorUnauthorized                 = -321;  // ERROR_CODE_UNAUTHORIZED
  static const int errorForbidden                    = -322;  // ERROR_CODE_FORBIDDEN
  static const int errorFeatureNotEnabled            = -323;  // ERROR_CODE_FEATURE_NOT_ENABLED
  static const int errorQuotaExceeded                = -324;  // ERROR_CODE_QUOTA_EXCEEDED
  static const int errorKeychainError                = -330;  // ERROR_CODE_KEYCHAIN_ERROR
  static const int errorEncodingError                = -331;  // ERROR_CODE_ENCODING_ERROR
  static const int errorDecodingError                = -332;  // ERROR_CODE_DECODING_ERROR
  static const int errorSecureStorageFailed          = -333;  // ERROR_CODE_SECURE_STORAGE_FAILED
  static const int errorExtractionFailed             = -350;  // ERROR_CODE_EXTRACTION_FAILED
  static const int errorChecksumMismatch             = -351;  // ERROR_CODE_CHECKSUM_MISMATCH
  static const int errorUnsupportedArchive           = -352;  // ERROR_CODE_UNSUPPORTED_ARCHIVE
  static const int errorCalibrationFailed            = -370;  // ERROR_CODE_CALIBRATION_FAILED
  static const int errorCalibrationTimeout           = -371;  // ERROR_CODE_CALIBRATION_TIMEOUT
  static const int errorCancelled                    = -380;  // ERROR_CODE_CANCELLED
  static const int errorModuleNotFound               = -400;  // ERROR_CODE_MODULE_NOT_FOUND
  static const int errorModuleAlreadyRegistered      = -401;  // ERROR_CODE_MODULE_ALREADY_REGISTERED
  static const int errorModuleLoadFailed             = -402;  // ERROR_CODE_MODULE_LOAD_FAILED
  static const int errorServiceNotFound              = -410;  // ERROR_CODE_SERVICE_NOT_FOUND
  static const int errorServiceAlreadyRegistered     = -411;  // ERROR_CODE_SERVICE_ALREADY_REGISTERED
  static const int errorServiceCreateFailed          = -412;  // ERROR_CODE_SERVICE_CREATE_FAILED
  static const int errorCapabilityNotFound           = -420;  // ERROR_CODE_CAPABILITY_NOT_FOUND
  static const int errorProviderNotFound             = -421;  // ERROR_CODE_PROVIDER_NOT_FOUND
  static const int errorNoCapableProvider            = -422;  // ERROR_CODE_NO_CAPABLE_PROVIDER
  static const int errorNotFound                     = -423;  // ERROR_CODE_NOT_FOUND
  static const int errorAdapterNotSet                = -500;  // ERROR_CODE_ADAPTER_NOT_SET
  static const int errorBackendNotFound              = -600;  // ERROR_CODE_BACKEND_NOT_FOUND
  static const int errorBackendNotReady              = -601;  // ERROR_CODE_BACKEND_NOT_READY
  static const int errorBackendInitFailed            = -602;  // ERROR_CODE_BACKEND_INIT_FAILED
  static const int errorBackendBusy                  = -603;  // ERROR_CODE_BACKEND_BUSY
  static const int errorBackendUnavailable           = -604;  // ERROR_CODE_BACKEND_UNAVAILABLE
  static const int errorRuntimeUnavailable           = -605;  // ERROR_CODE_RUNTIME_UNAVAILABLE
  static const int errorBackendError                 = -606;  // ERROR_CODE_BACKEND_ERROR
  static const int errorInvalidHandle                = -610;  // ERROR_CODE_INVALID_HANDLE
  static const int errorEventInvalidCategory         = -700;  // ERROR_CODE_EVENT_INVALID_CATEGORY
  static const int errorEventSubscriptionFailed      = -701;  // ERROR_CODE_EVENT_SUBSCRIPTION_FAILED
  static const int errorEventPublishFailed           = -702;  // ERROR_CODE_EVENT_PUBLISH_FAILED
  static const int errorNotImplemented               = -800;  // ERROR_CODE_NOT_IMPLEMENTED
  static const int errorFeatureNotAvailable          = -801;  // ERROR_CODE_FEATURE_NOT_AVAILABLE
  static const int errorFrameworkNotAvailable        = -802;  // ERROR_CODE_FRAMEWORK_NOT_AVAILABLE
  static const int errorUnsupportedModality          = -803;  // ERROR_CODE_UNSUPPORTED_MODALITY
  static const int errorUnknown                      = -804;  // ERROR_CODE_UNKNOWN
  static const int errorInternal                     = -805;  // ERROR_CODE_INTERNAL
  static const int errorAbiVersionMismatch           = -810;  // ERROR_CODE_ABI_VERSION_MISMATCH
  static const int errorCapabilityUnsupported        = -811;  // ERROR_CODE_CAPABILITY_UNSUPPORTED
  static const int errorPluginDuplicate              = -812;  // ERROR_CODE_PLUGIN_DUPLICATE
  static const int errorPluginLoadFailed             = -820;  // ERROR_CODE_PLUGIN_LOAD_FAILED
  static const int errorPluginBusy                   = -821;  // ERROR_CODE_PLUGIN_BUSY
  static const int errorWasmLoadFailed               = -900;  // ERROR_CODE_WASM_LOAD_FAILED
  static const int errorWasmNotLoaded                = -901;  // ERROR_CODE_WASM_NOT_LOADED
  static const int errorWasmCallbackError            = -902;  // ERROR_CODE_WASM_CALLBACK_ERROR
  static const int errorWasmMemoryError              = -903;  // ERROR_CODE_WASM_MEMORY_ERROR

  /// Human-readable label for a rac_result_t.
  ///
  /// Strings are built at codegen time rather than from ProtobufEnum names,
  /// which a build can strip with --define=protobuf.omit_enum_names=true.
  static String message(int code) {
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
      case errorInvalidApiKey:
        return 'Invalid API key';
      case errorEnvironmentMismatch:
        return 'Environment mismatch';
      case errorInvalidParameter:
        return 'Invalid parameter';
      case errorModelNotFound:
        return 'Model not found';
      case errorModelLoadFailed:
        return 'Model load failed';
      case errorModelValidationFailed:
        return 'Model validation failed';
      case errorModelIncompatible:
        return 'Model incompatible';
      case errorInvalidModelFormat:
        return 'Invalid model format';
      case errorModelStorageCorrupted:
        return 'Model storage corrupted';
      case errorModelNotLoaded:
        return 'Model not loaded';
      case errorGenerationFailed:
        return 'Generation failed';
      case errorGenerationTimeout:
        return 'Generation timeout';
      case errorContextTooLong:
        return 'Context too long';
      case errorTokenLimitExceeded:
        return 'Token limit exceeded';
      case errorCostLimitExceeded:
        return 'Cost limit exceeded';
      case errorInferenceFailed:
        return 'Inference failed';
      case errorGenerationCancelled:
        return 'Generation cancelled';
      case errorNetworkUnavailable:
        return 'Network unavailable';
      case errorNetworkError:
        return 'Network error';
      case errorRequestFailed:
        return 'Request failed';
      case errorDownloadFailed:
        return 'Download failed';
      case errorServerError:
        return 'Server error';
      case errorTimeout:
        return 'Timeout';
      case errorInvalidResponse:
        return 'Invalid response';
      case errorHttpError:
        return 'HTTP error';
      case errorConnectionLost:
        return 'Connection lost';
      case errorPartialDownload:
        return 'Partial download';
      case errorHttpRequestFailed:
        return 'HTTP request failed';
      case errorHttpNotSupported:
        return 'HTTP not supported';
      case errorInsufficientStorage:
        return 'Insufficient storage';
      case errorStorageFull:
        return 'Storage full';
      case errorStorageError:
        return 'Storage error';
      case errorFileNotFound:
        return 'File not found';
      case errorFileReadFailed:
        return 'File read failed';
      case errorFileWriteFailed:
        return 'File write failed';
      case errorPermissionDenied:
        return 'Permission denied';
      case errorDeleteFailed:
        return 'Delete failed';
      case errorMoveFailed:
        return 'Move failed';
      case errorDirectoryCreationFailed:
        return 'Directory creation failed';
      case errorDirectoryNotFound:
        return 'Directory not found';
      case errorInvalidPath:
        return 'Invalid path';
      case errorInvalidFileName:
        return 'Invalid file name';
      case errorTempFileCreationFailed:
        return 'Temp file creation failed';
      case errorHardwareUnsupported:
        return 'Hardware unsupported';
      case errorInsufficientMemory:
        return 'Insufficient memory';
      case errorComponentNotReady:
        return 'Component not ready';
      case errorInvalidState:
        return 'Invalid state';
      case errorServiceNotAvailable:
        return 'Service not available';
      case errorServiceBusy:
        return 'Service busy';
      case errorProcessingFailed:
        return 'Processing failed';
      case errorStartFailed:
        return 'Start failed';
      case errorNotSupported:
        return 'Not supported';
      case errorValidationFailed:
        return 'Validation failed';
      case errorInvalidInput:
        return 'Invalid input';
      case errorInvalidFormat:
        return 'Invalid format';
      case errorEmptyInput:
        return 'Empty input';
      case errorTextTooLong:
        return 'Text too long';
      case errorInvalidSsml:
        return 'Invalid ssml';
      case errorInvalidSpeakingRate:
        return 'Invalid speaking rate';
      case errorInvalidPitch:
        return 'Invalid pitch';
      case errorInvalidVolume:
        return 'Invalid volume';
      case errorInvalidArgument:
        return 'Invalid argument';
      case errorNullPointer:
        return 'Null pointer';
      case errorBufferTooSmall:
        return 'Buffer too small';
      case errorOutputTruncated:
        return 'Output truncated';
      case errorAudioFormatNotSupported:
        return 'Audio format not supported';
      case errorAudioSessionFailed:
        return 'Audio session failed';
      case errorMicrophonePermissionDenied:
        return 'Microphone permission denied';
      case errorInsufficientAudioData:
        return 'Insufficient audio data';
      case errorEmptyAudioBuffer:
        return 'Empty audio buffer';
      case errorAudioSessionActivationFailed:
        return 'Audio session activation failed';
      case errorLanguageNotSupported:
        return 'Language not supported';
      case errorVoiceNotAvailable:
        return 'Voice not available';
      case errorStreamingNotSupported:
        return 'Streaming not supported';
      case errorStreamCancelled:
        return 'Stream cancelled';
      case errorAuthenticationFailed:
        return 'Authentication failed';
      case errorUnauthorized:
        return 'Unauthorized';
      case errorForbidden:
        return 'Forbidden';
      case errorFeatureNotEnabled:
        return 'Feature not enabled';
      case errorQuotaExceeded:
        return 'Quota exceeded';
      case errorKeychainError:
        return 'Keychain error';
      case errorEncodingError:
        return 'Encoding error';
      case errorDecodingError:
        return 'Decoding error';
      case errorSecureStorageFailed:
        return 'Secure storage failed';
      case errorExtractionFailed:
        return 'Extraction failed';
      case errorChecksumMismatch:
        return 'Checksum mismatch';
      case errorUnsupportedArchive:
        return 'Unsupported archive';
      case errorCalibrationFailed:
        return 'Calibration failed';
      case errorCalibrationTimeout:
        return 'Calibration timeout';
      case errorCancelled:
        return 'Cancelled';
      case errorModuleNotFound:
        return 'Module not found';
      case errorModuleAlreadyRegistered:
        return 'Module already registered';
      case errorModuleLoadFailed:
        return 'Module load failed';
      case errorServiceNotFound:
        return 'Service not found';
      case errorServiceAlreadyRegistered:
        return 'Service already registered';
      case errorServiceCreateFailed:
        return 'Service create failed';
      case errorCapabilityNotFound:
        return 'Capability not found';
      case errorProviderNotFound:
        return 'Provider not found';
      case errorNoCapableProvider:
        return 'No capable provider';
      case errorNotFound:
        return 'Not found';
      case errorAdapterNotSet:
        return 'Adapter not set';
      case errorBackendNotFound:
        return 'Backend not found';
      case errorBackendNotReady:
        return 'Backend not ready';
      case errorBackendInitFailed:
        return 'Backend init failed';
      case errorBackendBusy:
        return 'Backend busy';
      case errorBackendUnavailable:
        return 'Backend unavailable';
      case errorRuntimeUnavailable:
        return 'Runtime unavailable';
      case errorBackendError:
        return 'Backend error';
      case errorInvalidHandle:
        return 'Invalid handle';
      case errorEventInvalidCategory:
        return 'Event invalid category';
      case errorEventSubscriptionFailed:
        return 'Event subscription failed';
      case errorEventPublishFailed:
        return 'Event publish failed';
      case errorNotImplemented:
        return 'Not implemented';
      case errorFeatureNotAvailable:
        return 'Feature not available';
      case errorFrameworkNotAvailable:
        return 'Framework not available';
      case errorUnsupportedModality:
        return 'Unsupported modality';
      case errorUnknown:
        return 'Unknown';
      case errorInternal:
        return 'Internal';
      case errorAbiVersionMismatch:
        return 'ABI version mismatch';
      case errorCapabilityUnsupported:
        return 'Capability unsupported';
      case errorPluginDuplicate:
        return 'Plugin duplicate';
      case errorPluginLoadFailed:
        return 'Plugin load failed';
      case errorPluginBusy:
        return 'Plugin busy';
      case errorWasmLoadFailed:
        return 'WASM load failed';
      case errorWasmNotLoaded:
        return 'WASM not loaded';
      case errorWasmCallbackError:
        return 'WASM callback error';
      case errorWasmMemoryError:
        return 'WASM memory error';
      default:
        return 'Unknown error (code: $code)';
    }
  }
}
