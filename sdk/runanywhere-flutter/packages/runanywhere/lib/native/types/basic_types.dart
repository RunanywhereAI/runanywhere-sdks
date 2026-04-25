// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';

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
  static const int errorBackendUnavailable = -604;
  static const int errorInvalidHandle = -610;

  // Other errors (-800 to -899)
  static const int errorNotImplemented = -800;
  static const int errorFeatureNotAvailable = -801;
  static const int errorFrameworkNotAvailable = -802;
  static const int errorUnsupportedModality = -803;
  static const int errorUnknown = -804;
  static const int errorInternal = -805;
  static const int errorAbiVersionMismatch = -810;
  static const int errorCapabilityUnsupported = -811;
  static const int errorPluginDuplicate = -812;

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
      case errorBackendUnavailable:
        return 'Backend unavailable';
      case errorInvalidHandle:
        return 'Invalid handle';
      case errorNotImplemented:
        return 'Not implemented';
      case errorUnknown:
        return 'Unknown error';
      case errorInternal:
        return 'Internal error';
      case errorAbiVersionMismatch:
        return 'Plugin ABI version mismatch';
      case errorCapabilityUnsupported:
        return 'Plugin capability unsupported';
      case errorPluginDuplicate:
        return 'Plugin duplicate';
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
