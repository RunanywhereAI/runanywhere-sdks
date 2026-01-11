// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

// =============================================================================
// Environment Bridge
// =============================================================================

/// Environment bridge for C++ environment validation and configuration.
/// Matches Swift's `CppBridge+Environment.swift`.
///
/// C++ provides:
/// - Environment validation (API key, URL)
/// - Environment-specific settings (log level, telemetry)
/// - Configuration validation
class DartBridgeEnvironment {
  DartBridgeEnvironment._();

  // ignore: unused_field
  static final _logger = SDKLogger('DartBridge.Environment');
  static final DartBridgeEnvironment instance = DartBridgeEnvironment._();

  // ============================================================================
  // Environment Queries
  // ============================================================================

  /// Check if environment requires API authentication
  bool requiresAuth(SDKEnvironment environment) {
    try {
      final lib = PlatformLoader.loadCommons();
      final requiresAuthFn = lib.lookupFunction<Int32 Function(Int32),
          int Function(int)>('rac_env_requires_auth');

      return requiresAuthFn(_environmentToInt(environment)) != 0;
    } catch (e) {
      // Fallback: dev doesn't require auth
      return environment != SDKEnvironment.development;
    }
  }

  /// Check if environment requires a backend URL
  bool requiresBackendURL(SDKEnvironment environment) {
    try {
      final lib = PlatformLoader.loadCommons();
      final requiresUrlFn = lib.lookupFunction<Int32 Function(Int32),
          int Function(int)>('rac_env_requires_backend_url');

      return requiresUrlFn(_environmentToInt(environment)) != 0;
    } catch (e) {
      // Fallback: dev doesn't require URL
      return environment != SDKEnvironment.development;
    }
  }

  /// Check if environment is production
  bool isProduction(SDKEnvironment environment) {
    try {
      final lib = PlatformLoader.loadCommons();
      final isProdFn = lib.lookupFunction<Int32 Function(Int32),
          int Function(int)>('rac_env_is_production');

      return isProdFn(_environmentToInt(environment)) != 0;
    } catch (e) {
      return environment == SDKEnvironment.production;
    }
  }

  /// Check if environment is a testing environment
  bool isTesting(SDKEnvironment environment) {
    try {
      final lib = PlatformLoader.loadCommons();
      final isTestFn = lib.lookupFunction<Int32 Function(Int32),
          int Function(int)>('rac_env_is_testing');

      return isTestFn(_environmentToInt(environment)) != 0;
    } catch (e) {
      return environment != SDKEnvironment.production;
    }
  }

  /// Get default log level for environment
  int getDefaultLogLevel(SDKEnvironment environment) {
    try {
      final lib = PlatformLoader.loadCommons();
      final getLogLevelFn = lib.lookupFunction<Int32 Function(Int32),
          int Function(int)>('rac_env_default_log_level');

      return getLogLevelFn(_environmentToInt(environment));
    } catch (e) {
      // Fallback defaults
      switch (environment) {
        case SDKEnvironment.development:
          return RacLogLevel.debug;
        case SDKEnvironment.staging:
          return RacLogLevel.info;
        case SDKEnvironment.production:
          return RacLogLevel.warning;
      }
    }
  }

  /// Check if telemetry should be sent
  bool shouldSendTelemetry(SDKEnvironment environment) {
    try {
      final lib = PlatformLoader.loadCommons();
      final shouldSendFn = lib.lookupFunction<Int32 Function(Int32),
          int Function(int)>('rac_env_should_send_telemetry');

      return shouldSendFn(_environmentToInt(environment)) != 0;
    } catch (e) {
      // Only production sends telemetry
      return environment == SDKEnvironment.production;
    }
  }

  /// Check if should sync with backend
  bool shouldSyncWithBackend(SDKEnvironment environment) {
    try {
      final lib = PlatformLoader.loadCommons();
      final shouldSyncFn = lib.lookupFunction<Int32 Function(Int32),
          int Function(int)>('rac_env_should_sync_with_backend');

      return shouldSyncFn(_environmentToInt(environment)) != 0;
    } catch (e) {
      return environment != SDKEnvironment.development;
    }
  }

  /// Get environment description
  String getDescription(SDKEnvironment environment) {
    try {
      final lib = PlatformLoader.loadCommons();
      final getDescFn = lib.lookupFunction<Pointer<Utf8> Function(Int32),
          Pointer<Utf8> Function(int)>('rac_env_description');

      final result = getDescFn(_environmentToInt(environment));
      if (result == nullptr) return 'Unknown Environment';
      return result.toDartString();
    } catch (e) {
      switch (environment) {
        case SDKEnvironment.development:
          return 'Development Environment';
        case SDKEnvironment.staging:
          return 'Staging Environment';
        case SDKEnvironment.production:
          return 'Production Environment';
      }
    }
  }

  // ============================================================================
  // Validation
  // ============================================================================

  /// Validate API key for environment
  ValidationResult validateApiKey(String? apiKey, SDKEnvironment environment) {
    try {
      final lib = PlatformLoader.loadCommons();
      final validateFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, int)>('rac_validate_api_key');

      final apiKeyPtr = apiKey?.toNativeUtf8() ?? nullptr;
      try {
        final result = validateFn(apiKeyPtr.cast<Utf8>(), _environmentToInt(environment));
        return ValidationResult.fromCode(result);
      } finally {
        if (apiKeyPtr != nullptr) calloc.free(apiKeyPtr);
      }
    } catch (e) {
      // Fallback validation
      if (environment == SDKEnvironment.development) {
        return ValidationResult.ok;
      }
      if (apiKey == null || apiKey.isEmpty) {
        return ValidationResult.apiKeyRequired;
      }
      if (apiKey.length < 10) {
        return ValidationResult.apiKeyTooShort;
      }
      return ValidationResult.ok;
    }
  }

  /// Validate base URL for environment
  ValidationResult validateBaseURL(String? url, SDKEnvironment environment) {
    try {
      final lib = PlatformLoader.loadCommons();
      final validateFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, int)>('rac_validate_base_url');

      final urlPtr = url?.toNativeUtf8() ?? nullptr;
      try {
        final result = validateFn(urlPtr.cast<Utf8>(), _environmentToInt(environment));
        return ValidationResult.fromCode(result);
      } finally {
        if (urlPtr != nullptr) calloc.free(urlPtr);
      }
    } catch (e) {
      // Fallback validation
      if (environment == SDKEnvironment.development) {
        return ValidationResult.ok;
      }
      if (url == null || url.isEmpty) {
        return ValidationResult.urlRequired;
      }
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        return ValidationResult.urlInvalidScheme;
      }
      if (environment == SDKEnvironment.production && !url.startsWith('https://')) {
        return ValidationResult.urlHttpsRequired;
      }
      return ValidationResult.ok;
    }
  }

  /// Validate complete configuration
  ValidationResult validateConfig({
    required SDKEnvironment environment,
    String? apiKey,
    String? baseURL,
  }) {
    try {
      final lib = PlatformLoader.loadCommons();
      final validateFn = lib.lookupFunction<
          Int32 Function(Pointer<RacSdkConfigStruct>),
          int Function(Pointer<RacSdkConfigStruct>)>('rac_validate_config');

      final config = calloc<RacSdkConfigStruct>();
      final apiKeyPtr = apiKey?.toNativeUtf8() ?? nullptr;
      final baseURLPtr = baseURL?.toNativeUtf8() ?? nullptr;

      try {
        config.ref.environment = _environmentToInt(environment);
        config.ref.apiKey = apiKeyPtr.cast<Utf8>();
        config.ref.baseURL = baseURLPtr.cast<Utf8>();

        final result = validateFn(config);
        return ValidationResult.fromCode(result);
      } finally {
        if (apiKeyPtr != nullptr) calloc.free(apiKeyPtr);
        if (baseURLPtr != nullptr) calloc.free(baseURLPtr);
        calloc.free(config);
      }
    } catch (e) {
      // Fallback: validate each part
      final apiKeyResult = validateApiKey(apiKey, environment);
      if (!apiKeyResult.isValid) return apiKeyResult;

      final urlResult = validateBaseURL(baseURL, environment);
      if (!urlResult.isValid) return urlResult;

      return ValidationResult.ok;
    }
  }

  /// Get error message for validation result
  String getValidationErrorMessage(ValidationResult result) {
    try {
      final lib = PlatformLoader.loadCommons();
      final getMsgFn = lib.lookupFunction<Pointer<Utf8> Function(Int32),
          Pointer<Utf8> Function(int)>('rac_validation_error_message');

      final msgResult = getMsgFn(result.code);
      if (msgResult == nullptr) return result.message;
      return msgResult.toDartString();
    } catch (e) {
      return result.message;
    }
  }

  // ============================================================================
  // Internal Helpers
  // ============================================================================

  int _environmentToInt(SDKEnvironment env) {
    switch (env) {
      case SDKEnvironment.development:
        return 0;
      case SDKEnvironment.staging:
        return 1;
      case SDKEnvironment.production:
        return 2;
    }
  }
}

// =============================================================================
// SDK Config Struct for FFI
// =============================================================================

/// SDK config struct for validation (simplified)
base class RacSdkConfigStruct extends Struct {
  @Int32()
  external int environment;

  external Pointer<Utf8> apiKey;
  external Pointer<Utf8> baseURL;
  external Pointer<Utf8> deviceId;
  external Pointer<Utf8> platform;
  external Pointer<Utf8> sdkVersion;
}

// =============================================================================
// Validation Result
// =============================================================================

/// Validation result enum matching rac_validation_result_t
class ValidationResult {
  final int code;
  final String message;

  const ValidationResult._(this.code, this.message);

  bool get isValid => code == 0;

  static const ok = ValidationResult._(0, 'Configuration is valid');
  static const apiKeyRequired =
      ValidationResult._(1, 'API key is required for this environment');
  static const apiKeyTooShort = ValidationResult._(2, 'API key is too short');
  static const urlRequired =
      ValidationResult._(3, 'Backend URL is required for this environment');
  static const urlInvalidScheme =
      ValidationResult._(4, 'URL must start with http:// or https://');
  static const urlHttpsRequired =
      ValidationResult._(5, 'HTTPS is required for production');
  static const urlInvalidHost = ValidationResult._(6, 'Invalid URL host');
  static const urlLocalhostNotAllowed =
      ValidationResult._(7, 'localhost is not allowed in production');
  static const productionDebugBuild =
      ValidationResult._(8, 'Debug builds not allowed in production');
  static const unknown = ValidationResult._(-1, 'Unknown validation error');

  factory ValidationResult.fromCode(int code) {
    switch (code) {
      case 0:
        return ok;
      case 1:
        return apiKeyRequired;
      case 2:
        return apiKeyTooShort;
      case 3:
        return urlRequired;
      case 4:
        return urlInvalidScheme;
      case 5:
        return urlHttpsRequired;
      case 6:
        return urlInvalidHost;
      case 7:
        return urlLocalhostNotAllowed;
      case 8:
        return productionDebugBuild;
      default:
        return unknown;
    }
  }
}
