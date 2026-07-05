// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';

import 'package:runanywhere/generated/errors.pbenum.dart' as errors;

/// =============================================================================
/// RunAnywhere Commons FFI Type Definitions
///
/// Dart FFI types matching the C API defined in rac_*.h headers
/// from runanywhere-commons library.
/// =============================================================================

// Basic Types (from rac_types.h)

/// Opaque handle for internal objects (rac_handle_t)
typedef RacHandle = Pointer<Void>;

/// Result type for all RAC functions (rac_result_t)
/// 0 = success, negative = error
typedef RacResult = Int32;

/// RAC boolean values
const int RAC_TRUE = 1;
const int RAC_FALSE = 0;

/// RAC success value
const int RAC_SUCCESS = 0;

// Result Codes (from rac_error.h)
//
// C ABI returns negative rac_result_t values; the canonical error vocabulary is
// generated from idl/errors.proto as positive ErrorCode values. Keep this class
// only as the ABI sign-convention boundary for FFI callback return values.

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
  static const int errorHttpRequestFailed = -160;
  static const int errorHttpNotSupported = -161;

  // Storage errors (-180 to -219)
  static const int errorInsufficientStorage = -180;
  static const int errorStorageFull = -181;
  static const int errorStorageError = -182;
  static const int errorFileNotFound = -183;
  static const int errorFileReadFailed = -184;
  static const int errorFileWriteFailed = -185;
  static const int errorPermissionDenied = -186;
  static const int errorDeleteFailed = -187;
  // RAC_ERROR_FILE_DELETE_FAILED is an alias of -187 in the C header.
  static const int errorFileDeleteFailed = -187;
  static const int errorMoveFailed = -188;
  static const int errorDirectoryCreationFailed = -189;
  static const int errorDirectoryNotFound = -190;
  static const int errorInvalidPath = -191;
  static const int errorInvalidFileName = -192;
  static const int errorTempFileCreationFailed = -193;

  // Hardware errors (-220 to -229)
  static const int errorHardwareUnsupported = -220;
  static const int errorInsufficientMemory = -221;
  // RAC_ERROR_OUT_OF_MEMORY is an alias of -221 in the C header.
  static const int errorOutOfMemory = -221;

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
  static const int errorTextTooLong = -254;
  static const int errorInvalidSsml = -255;
  static const int errorInvalidSpeakingRate = -256;
  static const int errorInvalidPitch = -257;
  static const int errorInvalidVolume = -258;
  static const int errorInvalidArgument = -259;
  static const int errorNullPointer = -260;
  static const int errorBufferTooSmall = -261;

  // Audio errors (-280 to -299)
  static const int errorAudioFormatNotSupported = -280;
  static const int errorAudioSessionFailed = -281;
  static const int errorMicrophonePermissionDenied = -282;
  static const int errorInsufficientAudioData = -283;
  static const int errorEmptyAudioBuffer = -284;
  static const int errorAudioSessionActivationFailed = -285;

  // Language/voice errors (-300 to -319)
  static const int errorLanguageNotSupported = -300;
  static const int errorVoiceNotAvailable = -301;
  static const int errorStreamingNotSupported = -302;
  static const int errorStreamCancelled = -303;

  // Authentication errors (-320 to -329)
  static const int errorAuthenticationFailed = -320;
  static const int errorUnauthorized = -321;
  static const int errorForbidden = -322;

  // Security errors (-330 to -349)
  static const int errorKeychainError = -330;
  static const int errorEncodingError = -331;
  static const int errorDecodingError = -332;
  static const int errorSecureStorageFailed = -333;

  // Extraction errors (-350 to -369)
  static const int errorExtractionFailed = -350;
  static const int errorChecksumMismatch = -351;
  static const int errorUnsupportedArchive = -352;

  // Calibration errors (-370 to -379)
  static const int errorCalibrationFailed = -370;
  static const int errorCalibrationTimeout = -371;

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
  static const int errorRuntimeUnavailable = -605;
  static const int errorInvalidHandle = -610;

  // Event errors (-700 to -799)
  static const int errorEventInvalidCategory = -700;
  static const int errorEventSubscriptionFailed = -701;
  static const int errorEventPublishFailed = -702;

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
  static const int errorPluginLoadFailed = -820;
  static const int errorPluginBusy = -821;

  /// Convert a C ABI result code into the generated proto error enum.
  static errors.ErrorCode? toProtoErrorCode(int code) {
    if (code == success) return null;
    return errors.ErrorCode.valueOf(code.abs()) ??
        errors.ErrorCode.ERROR_CODE_UNKNOWN;
  }

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
        final protoCode = toProtoErrorCode(code);
        if (protoCode != null &&
            protoCode != errors.ErrorCode.ERROR_CODE_UNKNOWN) {
          return _humanizeProtoError(protoCode.name);
        }
        return 'Error (code: $code)';
    }
  }

  static String _humanizeProtoError(String name) {
    final words = name
        .replaceFirst('ERROR_CODE_', '')
        .split('_')
        .where((word) => word.isNotEmpty)
        .map((word) => word.toLowerCase())
        .toList(growable: false);
    if (words.isEmpty) return 'Error';
    final first = '${words.first[0].toUpperCase()}${words.first.substring(1)}';
    return <String>[first, ...words.skip(1)].join(' ');
  }
}

// Log Levels (from rac_types.h)

/// Log level for the logging callback (rac_log_level_t), as the raw C-ABI
/// integers the native layer expects.
///
/// These mirror the generated `LogLevel` proto enum value-for-value
/// (`LOG_LEVEL_TRACE = 0 … LOG_LEVEL_FATAL = 5`, see `generated/logging.pbenum
/// .dart`), which is itself aligned with `enum rac_log_level` in
/// `include/rac/core/rac_types.h`. They are kept as `const int` literals (not
/// `LogLevel.*.value`) because FFI call sites use them as `switch` `case`
/// labels, which Dart requires to be compile-time constants.
abstract class RacLogLevel {
  static const int trace = 0;
  static const int debug = 1;
  static const int info = 2;
  static const int warning = 3;
  static const int error = 4;
  static const int fatal = 5;
}
