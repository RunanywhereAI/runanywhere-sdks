// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/constants/sdk_constants.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/native/dart_bridge_secure_storage.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// =============================================================================
// Exceptional return constants for FFI callbacks
// =============================================================================

const int _exceptionalReturnInt32 = -1;

// =============================================================================
// Device Manager Bridge
// =============================================================================

/// Device bridge for C++ device manager operations.
/// Matches Swift's `CppBridge+Device.swift`.
///
/// Provides callbacks for:
/// - Device info gathering (via device_info_plus)
/// - Device ID retrieval (via shared_preferences + unique ID)
/// - Registration persistence (via shared_preferences)
/// - HTTP transport (via http package)
class DartBridgeDevice {
  DartBridgeDevice._();

  static final _logger = SDKLogger('DartBridge.Device');
  static final DartBridgeDevice instance = DartBridgeDevice._();

  static bool _isRegistered = false;
  static String? _cachedDeviceId;
  static Pointer<RacDeviceCallbacksStruct>? _callbacksPtr;
  static _DeviceRegistrationInfoSnapshot _cachedRegistrationInfo =
      _DeviceRegistrationInfoSnapshot.defaults();

  /// SharedPreferences key for registration status
  static const _keyIsRegistered = 'com.runanywhere.sdk.device.isRegistered';

  /// SharedPreferences instance (lazily initialized)
  static SharedPreferences? _prefs;

  /// SDK environment for HTTP calls
  static SDKEnvironment _environment =
      SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;

  /// Base URL for HTTP calls
  static String? _baseURL;

  /// Access token for authenticated requests
  static String? _accessToken;

  // ============================================================================
  // Captured HTTP Request (for deferred async execution)
  // ============================================================================
  //
  // Dart FFI callbacks cannot block for async work (no semaphore equivalent).
  // Swift uses DispatchSemaphore, Kotlin uses blocking HttpURLConnection —
  // neither is available in Dart.
  //
  // Solution: the C++ http_post callback captures the request and returns
  // immediate success. DartBridge.initializeServices() drains the captured
  // request after commons Phase 2 returns. On failure, registration is rolled
  // back so it retries on next launch.

  static String? _pendingEndpoint;
  static String? _pendingBody;
  static bool _pendingRequiresAuth = false;

  // ============================================================================
  // Public API
  // ============================================================================

  /// Register device callbacks synchronously (Phase 1).
  /// Matches Swift: Device.register() in CppBridge.initialize()
  /// This registers the C++ callbacks without initializing SharedPreferences
  /// or caching device ID (those happen in Phase 2).
  static void registerCallbacks() {
    if (_callbacksRegistered) {
      _logger.debug('Device callbacks already registered');
      return;
    }

    try {
      final lib = PlatformLoader.loadCommons();

      // Allocate callbacks struct
      _callbacksPtr = calloc<RacDeviceCallbacksStruct>();
      final callbacks = _callbacksPtr!;

      // Set callback function pointers
      callbacks.ref.getDeviceInfo =
          Pointer.fromFunction<RacDeviceGetInfoCallbackNative>(
            _getDeviceInfoCallback,
          );
      callbacks.ref.getDeviceId =
          Pointer.fromFunction<RacDeviceGetIdCallbackNative>(
            _getDeviceIdCallback,
          );
      callbacks.ref.isRegistered =
          Pointer.fromFunction<RacDeviceIsRegisteredCallbackNative>(
            _isRegisteredCallback,
            _exceptionalReturnInt32,
          );
      callbacks.ref.setRegistered =
          Pointer.fromFunction<RacDeviceSetRegisteredCallbackNative>(
            _setRegisteredCallback,
          );
      callbacks.ref.httpPost =
          Pointer.fromFunction<RacDeviceHttpPostCallbackNative>(
            _httpPostCallback,
            _exceptionalReturnInt32,
          );
      callbacks.ref.userData = nullptr;

      // Register with C++
      final setCallbacks = lib
          .lookupFunction<
            Int32 Function(Pointer<RacDeviceCallbacksStruct>),
            int Function(Pointer<RacDeviceCallbacksStruct>)
          >('rac_device_manager_set_callbacks');

      final result = setCallbacks(callbacks);
      if (result != RacResultCode.success) {
        _logger.warning(
          'Failed to set device callbacks',
          metadata: {'error_code': result},
        );
        calloc.free(callbacks);
        _callbacksPtr = null;
        return;
      }

      _callbacksRegistered = true;
      _logger.debug('Device callbacks registered (sync)');
    } catch (_) {
      // librac_commons.so may not export rac_device_manager_set_callbacks in some
      // configurations (B-FL-1-002). Log at warning so it's visible in
      // non-debug builds; SDK falls back to no device callbacks.
      _logger.warning('Device callbacks are unavailable');
    }
  }

  static bool _callbacksRegistered = false;

  /// Register device callbacks with C++ (full async init, Phase 2)
  /// Must be called during SDK init after platform adapter
  static Future<void> register({
    required SDKEnvironment environment,
    String? baseURL,
    String? accessToken,
  }) async {
    _environment = environment;
    _baseURL = baseURL;
    _accessToken = accessToken;

    // Register callbacks if not already done in Phase 1
    if (!_callbacksRegistered) {
      registerCallbacks();
    }

    if (_isRegistered) {
      _logger.debug('Device already fully registered');
      return;
    }

    // Initialize SharedPreferences
    _prefs = await SharedPreferences.getInstance();

    // Pre-cache device ID
    await _getOrCreateDeviceId();
    await _configureClientInfo();
    await _refreshDeviceInfoSnapshot();

    // Callbacks are already registered (Phase 1 or the guard above).
    // Refresh the callback snapshot after the asynchronous device metadata
    // caches are ready. Reuse the existing pointer to avoid leaking the
    // Phase-1 allocation.
    try {
      final lib = PlatformLoader.loadCommons();

      final callbacks = _callbacksPtr;
      if (callbacks == null) {
        _logger.warning('No callbacks pointer available for Phase 2');
        return;
      }

      // Register with C++ device manager
      final setCallbacks = lib
          .lookupFunction<
            Int32 Function(Pointer<RacDeviceCallbacksStruct>),
            int Function(Pointer<RacDeviceCallbacksStruct>)
          >('rac_device_manager_set_callbacks');

      final result = setCallbacks(callbacks);
      if (result != RacResultCode.success) {
        _logger.warning(
          'Failed to register device callbacks',
          metadata: {'code': result},
        );
        return;
      }

      _isRegistered = true;
      _logger.debug('Device callbacks registered successfully');
    } catch (_) {
      _logger.debug('Device registration is unavailable');
      _isRegistered = true; // Mark as registered to avoid retry loops
    }
  }

  /// Update access token (called after authentication)
  static void setAccessToken(String? token) {
    _accessToken = token;
  }

  /// Execute the device-registration HTTP request captured by the C callback.
  /// Commons owns the `rac_device_manager_register_if_needed` call; Flutter
  /// only drains the request because Dart FFI callbacks cannot await network I/O.
  static Future<void> flushPendingRegistrationPost() async {
    await _executePendingHttpPost();
  }

  /// Clear process-local device state after native callbacks are quiescent.
  /// Durable identity and registration values remain in platform storage.
  static void shutdown() {
    if (_callbacksRegistered) {
      try {
        final clearCallbacks = PlatformLoader.loadCommons()
            .lookupFunction<Void Function(), void Function()>(
              'rac_device_manager_clear_callbacks',
            );
        clearCallbacks();
      } catch (_) {
        _logger.warning('Device callback teardown failed');
        // Keep every callback-owned allocation alive until a later reset can
        // prove native callback quiescence. DartBridge aggregates this failure
        // and remains fail closed in the meantime.
        rethrow;
      }
    }

    final callbacks = _callbacksPtr;
    if (callbacks != null) {
      calloc.free(callbacks);
      _callbacksPtr = null;
    }
    final cachedPointer = _cachedDeviceIdPtr;
    if (cachedPointer != null) {
      calloc.free(cachedPointer);
      _cachedDeviceIdPtr = null;
    }

    _callbacksRegistered = false;
    _isRegistered = false;
    _cachedDeviceId = null;
    _cachedRegistrationInfo = _DeviceRegistrationInfoSnapshot.defaults();
    _prefs = null;
    _environment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
    _baseURL = null;
    _accessToken = null;
    _pendingEndpoint = null;
    _pendingBody = null;
    _pendingRequiresAuth = false;
  }

  /// Execute the HTTP POST that was captured by the C++ callback.
  ///
  /// The C++ callback returned success immediately (Dart can't block for async).
  /// Now we do the real HTTP. On failure, we undo set_registered so the device
  /// will retry registration on next app launch.
  static Future<void> _executePendingHttpPost() async {
    final endpoint = _pendingEndpoint;
    final body = _pendingBody;
    final requiresAuth = _pendingRequiresAuth;

    // Clear captured state
    _pendingEndpoint = null;
    _pendingBody = null;
    _pendingRequiresAuth = false;

    // No HTTP request was captured — device was already registered
    if (endpoint == null || body == null) return;

    final logger = SDKLogger('DartBridge.Device.HTTP');

    // Build full URL: baseURL + endpoint path
    // Matches Kotlin: baseUrl.trimEnd('/') + finalEndpoint
    final baseURL = _baseURL ?? 'https://api.runanywhere.ai';
    final trimmedBase = baseURL.endsWith('/')
        ? baseURL.substring(0, baseURL.length - 1)
        : baseURL;

    // For dev mode (Supabase), add ?on_conflict=device_id for UPSERT
    // Matches Swift/Kotlin behavior
    final isDev = _environment == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
    final finalEndpoint = isDev
        ? (endpoint.contains('?')
              ? '$endpoint&on_conflict=device_id'
              : '$endpoint?on_conflict=device_id')
        : endpoint;
    final fullUrl = '$trimmedBase$finalEndpoint';

    // Build headers matching Kotlin/Swift
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (isDev) {
      headers['Prefer'] = 'resolution=merge-duplicates';
    }

    final accessToken =
        _accessToken ?? DartBridgeAuth.instance.getAccessToken();
    if (requiresAuth) {
      // Fall back to the SDK API key when no access token has been issued yet.
      // Device registration is the first authenticated call (before any JWT
      // exists), so without this fallback the Authorization header is omitted
      // and the backend returns 401 "Authorization header missing". Kotlin
      // parity: HTTPClientAdapter.resolveToken() resolves token -> apiKey.
      final token = (accessToken != null && accessToken.isNotEmpty)
          ? accessToken
          : HTTPClientAdapter.shared.apiKey;
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    logger.debug('Device registration POST started');

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.postUrl(Uri.parse(fullUrl));
      // Registration carries a bearer/API credential and a JSON body. Never
      // replay either to a redirect target.
      request.followRedirects = false;
      headers.forEach((key, value) => request.headers.set(key, value));
      request.write(body);

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );

      final statusCode = response.statusCode;
      final isSuccess =
          (statusCode >= 200 && statusCode < 300) || statusCode == 409;

      if (isSuccess) {
        logger.debug('Device registration successful (status=$statusCode)');
      } else {
        await response.drain<void>();
        logger.warning('Device registration failed (status=$statusCode)');
        // Roll back set_registered so it retries on next launch
        _rollBackRegistration(logger);
      }
    } catch (_) {
      logger.warning('Device registration HTTP request failed');
      // Roll back set_registered so it retries on next launch
      _rollBackRegistration(logger);
    } finally {
      client.close();
    }
  }

  /// Roll back device registration on HTTP failure.
  /// This ensures the device will retry on next app launch.
  static void _rollBackRegistration(SDKLogger logger) {
    logger.debug('Rolling back device registration for retry on next launch');
    final prefs = _prefs;
    if (prefs != null) {
      unawaited(prefs.setBool(_keyIsRegistered, false));
    }
  }

  /// Check if device is registered with backend
  bool isDeviceRegistered() {
    return _prefs?.getBool(_keyIsRegistered) ?? false;
  }

  /// Get the cached or generated device ID
  Future<String> getDeviceId() async {
    return _cachedDeviceId ?? await _getOrCreateDeviceId();
  }

  /// Get the cached device ID synchronously (null if not yet cached)
  static String? get cachedDeviceId => _cachedDeviceId;

  /// Device model from the canonical registration snapshot.
  static String get cachedDeviceModel => _cachedRegistrationInfo.deviceModel;

  /// OS version from the canonical registration snapshot (Android
  /// `Build.VERSION.RELEASE` / iOS `systemVersion`), not the kernel/build
  /// string that `Platform.operatingSystemVersion` returns.
  static String get cachedOsVersion => _cachedRegistrationInfo.osVersion;

  /// Populate the device-info snapshot if it is still the placeholder default.
  /// Lets callers that run before Phase 2 device registration (e.g. telemetry
  /// device-info setup) get the real model/OS instead of `unknown` + the build
  /// string. Idempotent: a no-op once a real snapshot has been collected.
  static Future<void> ensureDeviceInfoSnapshot() async {
    if (_cachedRegistrationInfo.deviceModel == 'unknown') {
      await _refreshDeviceInfoSnapshot();
    }
  }

  /// Register accurate app/client metadata with commons before Phase 2 device
  /// registration builds its JSON payload.
  static Future<void> _configureClientInfo() async {
    PackageInfo? packageInfo;
    try {
      packageInfo = await PackageInfo.fromPlatform();
    } catch (_) {
      _logger.debug('PackageInfo unavailable');
    }

    final timezone = await _currentTimezoneIdentifier();

    try {
      final lib = PlatformLoader.loadCommons();
      final setClientInfo = lib
          .lookupFunction<
            Void Function(Pointer<RacClientInfoStruct>),
            void Function(Pointer<RacClientInfoStruct>)
          >('rac_sdk_set_client_info');

      final allocatedStrings = <Pointer<Utf8>>[];
      Pointer<Utf8> nativeString(String? value) {
        final normalized = value?.trim();
        if (normalized == null || normalized.isEmpty) return nullptr;
        final ptr = normalized.toNativeUtf8();
        allocatedStrings.add(ptr);
        return ptr;
      }

      final infoPtr = calloc<RacClientInfoStruct>();
      try {
        infoPtr.ref.sdkBinding = nativeString('flutter');
        infoPtr.ref.appIdentifier = nativeString(packageInfo?.packageName);
        infoPtr.ref.appName = nativeString(packageInfo?.appName);
        infoPtr.ref.appVersion = nativeString(packageInfo?.version);
        infoPtr.ref.appBuild = nativeString(packageInfo?.buildNumber);
        infoPtr.ref.locale = nativeString(
          Platform.localeName.replaceAll('_', '-'),
        );
        infoPtr.ref.timezone = nativeString(timezone);
        setClientInfo(infoPtr);
      } finally {
        calloc.free(infoPtr);
        for (final ptr in allocatedStrings) {
          calloc.free(ptr);
        }
      }
    } catch (_) {
      _logger.debug('SDK client-info bridge unavailable');
    }
  }

  static Future<void> _refreshDeviceInfoSnapshot() async {
    try {
      _cachedRegistrationInfo = await _collectDeviceInfoSnapshot();
    } catch (_) {
      _logger.debug('Device info snapshot failed');
      _cachedRegistrationInfo = _DeviceRegistrationInfoSnapshot.defaults(
        deviceId: _cachedDeviceId,
      );
    }
  }

  // ============================================================================
  // Internal Helpers
  // ============================================================================

  /// Key for storing the persistent device UUID in platform secure storage.
  /// Matches Swift KeychainManager.KeychainKey.deviceUUID and React Native SecureStorageKeys.deviceUUID
  static const _keyDeviceUUID = 'com.runanywhere.sdk.device.uuid';

  /// Get or create a persistent device UUID.
  /// Matches Swift's DeviceIdentity.persistentUUID behavior:
  /// 1. Try to retrieve the stored UUID from platform secure storage
  /// 2. If not found, try iOS vendor ID
  /// 3. If still not found, generate new UUID
  /// The UUID format is required by the backend for device registration.
  static Future<String> _getOrCreateDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final nativeStorage = DartBridgeSecureStorage.instance;

    // Strategy 1: Read the synchronous platform store. A null value is the
    // only clean miss; authentication/IO failures propagate and abort init.
    final storedUUID = nativeStorage.retrieveIfExists(_keyDeviceUUID);
    if (storedUUID != null) {
      if (!_isValidUUID(storedUUID)) {
        throw StateError('Persisted device identifier is not a valid UUID');
      }
      _cachedDeviceId = storedUUID;
      _logger.debug('Using stored device UUID from secure storage');
      return storedUUID;
    }

    // Strategy 2: On iOS, prefer identifierForVendor when available.
    String? candidate;
    if (Platform.isIOS) {
      try {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        final vendorId = iosInfo.identifierForVendor;
        if (vendorId != null && _isValidUUID(vendorId)) {
          candidate = vendorId;
        }
      } catch (_) {
        _logger.debug('iOS vendor ID unavailable');
      }
    }

    // Strategy 3: Generate an RFC-4122 UUID, but never expose/cache it until
    // the synchronous platform store has committed it durably.
    candidate ??= _generateUUID();
    nativeStorage.store(_keyDeviceUUID, candidate);
    _cachedDeviceId = candidate;
    _logger.debug('Stored new device UUID in secure storage');
    return candidate;
  }

  /// Generate a proper UUID v4 string (matches backend expectations)
  /// Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  /// Uses cryptographically secure random bytes via the uuid package
  static String _generateUUID() {
    return const Uuid().v4();
  }

  /// Validate UUID format (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
  static bool _isValidUUID(String uuid) {
    if (uuid.length != 36) return false;
    if (!uuid.contains('-')) return false;
    final parts = uuid.split('-');
    if (parts.length != 5) return false;
    if (parts[0].length != 8 ||
        parts[1].length != 4 ||
        parts[2].length != 4 ||
        parts[3].length != 4 ||
        parts[4].length != 12) {
      return false;
    }
    return true;
  }
}

// =============================================================================
// FFI Callback Functions
// =============================================================================

/// Get device info callback
void _getDeviceInfoCallback(
  Pointer<RacDeviceRegistrationInfoStruct> outInfo,
  Pointer<Void> userData,
) {
  if (outInfo == nullptr) return;

  try {
    // Free previous native strings (allocated by prior callback invocations)
    for (final ptr in _cachedDeviceInfoPtrs) {
      calloc.free(ptr);
    }
    _cachedDeviceInfoPtrs = [];

    final snapshot = DartBridgeDevice._cachedRegistrationInfo.withDeviceId(
      DartBridgeDevice._cachedDeviceId,
    );

    Pointer<Utf8> cacheString(String? value) {
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) return nullptr;
      final ptr = normalized.toNativeUtf8();
      _cachedDeviceInfoPtrs.add(ptr);
      return ptr;
    }

    outInfo.ref.deviceId = cacheString(snapshot.deviceId);
    outInfo.ref.deviceModel = cacheString(snapshot.deviceModel);
    outInfo.ref.deviceName = cacheString(snapshot.deviceName);
    outInfo.ref.platform = cacheString(snapshot.platform);
    outInfo.ref.osVersion = cacheString(snapshot.osVersion);
    outInfo.ref.formFactor = cacheString(snapshot.formFactor);
    outInfo.ref.architecture = cacheString(snapshot.architecture);
    outInfo.ref.chipName = cacheString(snapshot.chipName);
    outInfo.ref.totalMemory = snapshot.totalMemory;
    outInfo.ref.availableMemory = snapshot.availableMemory;
    outInfo.ref.hasNeuralEngine = snapshot.hasNeuralEngine
        ? RAC_TRUE
        : RAC_FALSE;
    outInfo.ref.neuralEngineCores = snapshot.neuralEngineCores;
    outInfo.ref.gpuFamily = cacheString(snapshot.gpuFamily);
    outInfo.ref.batteryLevel = snapshot.batteryLevel;
    outInfo.ref.batteryState = cacheString(snapshot.batteryState);
    outInfo.ref.isLowPowerMode = snapshot.isLowPowerMode ? RAC_TRUE : RAC_FALSE;
    outInfo.ref.coreCount = snapshot.coreCount;
    outInfo.ref.performanceCores = snapshot.performanceCores;
    outInfo.ref.efficiencyCores = snapshot.efficiencyCores;
    outInfo.ref.deviceFingerprint = cacheString(snapshot.deviceFingerprint);
  } catch (_) {
    SDKLogger('DartBridge.Device').error('Device info callback failed');
  }
}

/// Cached native string pointers from _getDeviceInfoCallback.
/// Must persist for C++ to read; freed and replaced on each call.
List<Pointer<Utf8>> _cachedDeviceInfoPtrs = [];

/// Cached device ID pointer (must persist for C++ to read)
Pointer<Utf8>? _cachedDeviceIdPtr;

/// Get device ID callback
Pointer<Utf8> _getDeviceIdCallback(Pointer<Void> userData) {
  try {
    final deviceId = DartBridgeDevice._cachedDeviceId;
    if (deviceId == null) {
      return nullptr;
    }

    // Free previous pointer if exists
    if (_cachedDeviceIdPtr != null) {
      calloc.free(_cachedDeviceIdPtr!);
    }

    // Allocate and cache new pointer
    _cachedDeviceIdPtr = deviceId.toNativeUtf8();
    return _cachedDeviceIdPtr!;
  } catch (e) {
    return nullptr;
  }
}

/// Check if device is registered callback
int _isRegisteredCallback(Pointer<Void> userData) {
  try {
    final isReg =
        DartBridgeDevice._prefs?.getBool(DartBridgeDevice._keyIsRegistered) ??
        false;
    return isReg ? RAC_TRUE : RAC_FALSE;
  } catch (e) {
    return RAC_FALSE;
  }
}

/// Set device registered status callback
void _setRegisteredCallback(int registered, Pointer<Void> userData) {
  try {
    unawaited(
      DartBridgeDevice._prefs?.setBool(
        DartBridgeDevice._keyIsRegistered,
        registered != 0,
      ),
    );
  } catch (_) {
    SDKLogger('DartBridge.Device').error('Registration state callback failed');
  }
}

/// HTTP POST callback for device registration.
///
/// Dart FFI callbacks cannot block for async work (unlike Swift's
/// DispatchSemaphore or Kotlin's blocking HttpURLConnection).
/// Instead, we capture the request and return immediate success.
/// The real HTTP POST is executed asynchronously by
/// DartBridgeDevice.flushPendingRegistrationPost() after commons Phase 2
/// returns.
int _httpPostCallback(
  Pointer<Utf8> endpoint,
  Pointer<Utf8> jsonBody,
  int requiresAuth,
  Pointer<RacDeviceHttpResponseStruct> outResponse,
  Pointer<Void> userData,
) {
  if (endpoint == nullptr || outResponse == nullptr) {
    return RacResultCode.errorInvalidParameter;
  }

  try {
    // Capture request for deferred async execution after commons Phase 2.
    // We must copy the strings now — C++ will free its buffers after we return
    DartBridgeDevice._pendingEndpoint = endpoint.toDartString();
    DartBridgeDevice._pendingBody = jsonBody != nullptr
        ? jsonBody.toDartString()
        : '';
    DartBridgeDevice._pendingRequiresAuth = requiresAuth != 0;

    // Return success so C++ proceeds with set_registered(true).
    // The post-Phase-2 drain rolls back if the real HTTP fails.
    outResponse.ref.result = RacResultCode.success;
    outResponse.ref.statusCode = 200;
    outResponse.ref.responseBody = nullptr;
    outResponse.ref.errorMessage = nullptr;

    return RacResultCode.success;
  } catch (_) {
    SDKLogger('DartBridge.Device').error('HTTP POST callback failed');
    return RacResultCode.errorNetworkError;
  }
}

// =============================================================================
// FFI Types
// =============================================================================

/// Callback type: void (*get_device_info)(rac_device_registration_info_t*, void*)
typedef RacDeviceGetInfoCallbackNative =
    Void Function(Pointer<RacDeviceRegistrationInfoStruct>, Pointer<Void>);

/// Callback type: const char* (*get_device_id)(void*)
typedef RacDeviceGetIdCallbackNative = Pointer<Utf8> Function(Pointer<Void>);

/// Callback type: rac_bool_t (*is_registered)(void*)
typedef RacDeviceIsRegisteredCallbackNative = Int32 Function(Pointer<Void>);

/// Callback type: void (*set_registered)(rac_bool_t, void*)
typedef RacDeviceSetRegisteredCallbackNative =
    Void Function(Int32, Pointer<Void>);

/// Callback type: rac_result_t (*http_post)(const char*, const char*, rac_bool_t, rac_device_http_response_t*, void*)
typedef RacDeviceHttpPostCallbackNative =
    Int32 Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
      Pointer<RacDeviceHttpResponseStruct>,
      Pointer<Void>,
    );

/// Device callbacks struct matching rac_device_callbacks_t
base class RacDeviceCallbacksStruct extends Struct {
  external Pointer<NativeFunction<RacDeviceGetInfoCallbackNative>>
  getDeviceInfo;
  external Pointer<NativeFunction<RacDeviceGetIdCallbackNative>> getDeviceId;
  external Pointer<NativeFunction<RacDeviceIsRegisteredCallbackNative>>
  isRegistered;
  external Pointer<NativeFunction<RacDeviceSetRegisteredCallbackNative>>
  setRegistered;
  external Pointer<NativeFunction<RacDeviceHttpPostCallbackNative>> httpPost;
  external Pointer<Void> userData;
}

/// Device registration info struct matching rac_device_registration_info_t
base class RacDeviceRegistrationInfoStruct extends Struct {
  external Pointer<Utf8> deviceId;
  external Pointer<Utf8> deviceModel;
  external Pointer<Utf8> deviceName;
  external Pointer<Utf8> platform;
  external Pointer<Utf8> osVersion;
  external Pointer<Utf8> formFactor;
  external Pointer<Utf8> architecture;
  external Pointer<Utf8> chipName;

  @Int64()
  external int totalMemory;

  @Int64()
  external int availableMemory;

  @Int32()
  external int hasNeuralEngine;

  @Int32()
  external int neuralEngineCores;

  external Pointer<Utf8> gpuFamily;

  @Double()
  external double batteryLevel;

  external Pointer<Utf8> batteryState;

  @Int32()
  external int isLowPowerMode;

  @Int32()
  external int coreCount;

  @Int32()
  external int performanceCores;

  @Int32()
  external int efficiencyCores;

  external Pointer<Utf8> deviceFingerprint;
}

/// Client/app metadata matching rac_client_info_t.
base class RacClientInfoStruct extends Struct {
  external Pointer<Utf8> sdkBinding;
  external Pointer<Utf8> appIdentifier;
  external Pointer<Utf8> appName;
  external Pointer<Utf8> appVersion;
  external Pointer<Utf8> appBuild;
  external Pointer<Utf8> locale;
  external Pointer<Utf8> timezone;
}

/// HTTP response struct matching rac_device_http_response_t
base class RacDeviceHttpResponseStruct extends Struct {
  @Int32()
  external int result;

  @Int32()
  external int statusCode;

  external Pointer<Utf8> responseBody;
  external Pointer<Utf8> errorMessage;
}

class _DeviceRegistrationInfoSnapshot {
  const _DeviceRegistrationInfoSnapshot({
    required this.deviceId,
    required this.deviceModel,
    required this.deviceName,
    required this.platform,
    required this.osVersion,
    required this.formFactor,
    required this.architecture,
    required this.chipName,
    required this.totalMemory,
    required this.availableMemory,
    required this.hasNeuralEngine,
    required this.neuralEngineCores,
    required this.gpuFamily,
    required this.batteryLevel,
    required this.batteryState,
    required this.isLowPowerMode,
    required this.coreCount,
    required this.performanceCores,
    required this.efficiencyCores,
    required this.deviceFingerprint,
  });

  factory _DeviceRegistrationInfoSnapshot.defaults({String? deviceId}) {
    final coreCount = Platform.numberOfProcessors;
    final coreSplit = _coreDistribution(coreCount, '');
    return _DeviceRegistrationInfoSnapshot(
      deviceId: deviceId ?? '',
      deviceModel: 'unknown',
      deviceName: 'unknown',
      platform: SDKConstants.platform,
      osVersion: Platform.operatingSystemVersion,
      formFactor: _defaultFormFactor(),
      architecture: 'unknown',
      chipName: 'unknown',
      totalMemory: 0,
      availableMemory: 0,
      hasNeuralEngine: false,
      neuralEngineCores: 0,
      gpuFamily: 'unknown',
      batteryLevel: -1,
      batteryState: '',
      isLowPowerMode: false,
      coreCount: coreCount,
      performanceCores: coreSplit.$1,
      efficiencyCores: coreSplit.$2,
      deviceFingerprint: deviceId ?? '',
    );
  }

  final String deviceId;
  final String deviceModel;
  final String deviceName;
  final String platform;
  final String osVersion;
  final String formFactor;
  final String architecture;
  final String chipName;
  final int totalMemory;
  final int availableMemory;
  final bool hasNeuralEngine;
  final int neuralEngineCores;
  final String gpuFamily;
  final double batteryLevel;
  final String batteryState;
  final bool isLowPowerMode;
  final int coreCount;
  final int performanceCores;
  final int efficiencyCores;
  final String deviceFingerprint;

  _DeviceRegistrationInfoSnapshot withDeviceId(String? overrideDeviceId) {
    final resolved = overrideDeviceId ?? deviceId;
    if (resolved == deviceId) return this;
    return _DeviceRegistrationInfoSnapshot(
      deviceId: resolved,
      deviceModel: deviceModel,
      deviceName: deviceName,
      platform: platform,
      osVersion: osVersion,
      formFactor: formFactor,
      architecture: architecture,
      chipName: chipName,
      totalMemory: totalMemory,
      availableMemory: availableMemory,
      hasNeuralEngine: hasNeuralEngine,
      neuralEngineCores: neuralEngineCores,
      gpuFamily: gpuFamily,
      batteryLevel: batteryLevel,
      batteryState: batteryState,
      isLowPowerMode: isLowPowerMode,
      coreCount: coreCount,
      performanceCores: performanceCores,
      efficiencyCores: efficiencyCores,
      deviceFingerprint: deviceFingerprint.isEmpty
          ? resolved
          : deviceFingerprint,
    );
  }
}

Future<_DeviceRegistrationInfoSnapshot> _collectDeviceInfoSnapshot() async {
  final deviceId = DartBridgeDevice._cachedDeviceId ?? '';
  final plugin = DeviceInfoPlugin();

  if (Platform.isAndroid) {
    final info = await plugin.androidInfo;
    final model = _joinDistinct([info.manufacturer, info.model]);
    final coreCount = Platform.numberOfProcessors;
    final coreSplit = _coreDistribution(coreCount, model);
    final chipName = _nonEmpty(info.hardware) ?? 'unknown';
    return _DeviceRegistrationInfoSnapshot(
      deviceId: deviceId,
      deviceModel: model,
      deviceName: _nonEmpty(info.name) ?? model,
      platform: 'android',
      osVersion:
          _nonEmpty(info.version.release) ?? Platform.operatingSystemVersion,
      formFactor: _androidFormFactor(info.systemFeatures),
      architecture: info.supportedAbis.isNotEmpty
          ? info.supportedAbis.first
          : 'unknown',
      chipName: chipName,
      totalMemory: _memoryMegabytesToBytes(info.physicalRamSize),
      availableMemory: _memoryMegabytesToBytes(info.availableRamSize),
      hasNeuralEngine: false,
      neuralEngineCores: 0,
      gpuFamily: _inferAndroidGpuFamily(chipName, info.manufacturer),
      batteryLevel: -1,
      batteryState: '',
      isLowPowerMode: false,
      coreCount: coreCount,
      performanceCores: coreSplit.$1,
      efficiencyCores: coreSplit.$2,
      deviceFingerprint: _nonEmpty(info.fingerprint) ?? deviceId,
    );
  }

  if (Platform.isIOS) {
    final info = await plugin.iosInfo;
    final model = _nonEmpty(info.modelName) ?? info.model;
    final coreCount = Platform.numberOfProcessors;
    final coreSplit = _coreDistribution(coreCount, model);
    final machine = _nonEmpty(info.utsname.machine) ?? 'unknown';
    final hasNeuralEngine =
        info.isPhysicalDevice &&
        (machine.startsWith('iPhone') || machine.startsWith('iPad'));
    return _DeviceRegistrationInfoSnapshot(
      deviceId: deviceId,
      deviceModel: model,
      deviceName: _nonEmpty(info.name) ?? model,
      platform: 'ios',
      osVersion:
          _nonEmpty(info.systemVersion) ?? Platform.operatingSystemVersion,
      formFactor: model.toLowerCase().contains('ipad') ? 'tablet' : 'phone',
      architecture: _currentAbiArchitecture(),
      chipName: machine,
      totalMemory: _memoryMegabytesToBytes(info.physicalRamSize),
      availableMemory: _memoryMegabytesToBytes(info.availableRamSize),
      hasNeuralEngine: hasNeuralEngine,
      neuralEngineCores: hasNeuralEngine ? 16 : 0,
      gpuFamily: 'apple',
      batteryLevel: -1,
      batteryState: '',
      isLowPowerMode: false,
      coreCount: coreCount,
      performanceCores: coreSplit.$1,
      efficiencyCores: coreSplit.$2,
      deviceFingerprint: _nonEmpty(info.identifierForVendor) ?? deviceId,
    );
  }

  if (Platform.isMacOS) {
    final info = await plugin.macOsInfo;
    final model = _nonEmpty(info.modelName) ?? info.model;
    final coreSplit = _coreDistribution(info.activeCPUs, model);
    final hasNeuralEngine = info.arch == 'arm64';
    return _DeviceRegistrationInfoSnapshot(
      deviceId: deviceId,
      deviceModel: model,
      deviceName: _nonEmpty(info.computerName) ?? model,
      platform: 'macos',
      osVersion:
          '${info.majorVersion}.${info.minorVersion}.${info.patchVersion}',
      formFactor: 'desktop',
      architecture: _nonEmpty(info.arch) ?? 'unknown',
      chipName: _nonEmpty(info.model) ?? 'unknown',
      totalMemory: _memoryBytes(info.memorySize),
      availableMemory: 0,
      hasNeuralEngine: hasNeuralEngine,
      neuralEngineCores: hasNeuralEngine ? 16 : 0,
      gpuFamily: 'apple',
      batteryLevel: -1,
      batteryState: '',
      isLowPowerMode: false,
      coreCount: info.activeCPUs,
      performanceCores: coreSplit.$1,
      efficiencyCores: coreSplit.$2,
      deviceFingerprint: _nonEmpty(info.systemGUID) ?? deviceId,
    );
  }

  return _DeviceRegistrationInfoSnapshot.defaults(deviceId: deviceId);
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

String _joinDistinct(List<String?> parts) {
  final normalized = <String>[];
  for (final part in parts) {
    final value = _nonEmpty(part);
    if (value == null) continue;
    if (normalized.any((seen) => seen.toLowerCase() == value.toLowerCase())) {
      continue;
    }
    normalized.add(value);
  }
  return normalized.isEmpty ? 'unknown' : normalized.join(' ');
}

Future<String?> _currentTimezoneIdentifier() async {
  try {
    return _nonEmpty((await FlutterTimezone.getLocalTimezone()).identifier);
  } catch (_) {
    DartBridgeDevice._logger.debug('Timezone identifier unavailable');
    return null;
  }
}

String _currentAbiArchitecture() {
  final abi = Abi.current().toString();
  final normalized = abi.startsWith('Abi.') ? abi.substring(4) : abi;
  if (normalized.contains('_')) {
    return normalized.split('_').last;
  }
  if (normalized.endsWith('Arm64')) return 'arm64';
  if (normalized.endsWith('X64')) return 'x86_64';
  if (normalized.endsWith('IA32')) return 'x86';
  if (normalized.endsWith('Arm')) return 'arm';
  return normalized.isEmpty ? 'unknown' : normalized;
}

int _memoryMegabytesToBytes(int megabytes) {
  return megabytes > 0 ? megabytes * 1024 * 1024 : 0;
}

int _memoryBytes(int bytes) {
  return bytes > 0 ? bytes : 0;
}

(int, int) _coreDistribution(int coreCount, String model) {
  if (coreCount <= 0) return (0, 0);
  final lowerModel = model.toLowerCase();
  int performance;
  if (lowerModel.startsWith('iphone')) {
    performance = 2;
  } else if (lowerModel.startsWith('ipad') || lowerModel.startsWith('mac')) {
    performance = (coreCount * 2 ~/ 5).clamp(2, coreCount).toInt();
  } else {
    performance = (coreCount ~/ 3).clamp(1, coreCount).toInt();
  }
  performance = performance.clamp(0, coreCount).toInt();
  return (performance, coreCount - performance);
}

String _defaultFormFactor() {
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    return 'desktop';
  }
  return 'unknown';
}

String _androidFormFactor(List<String> systemFeatures) {
  final features = systemFeatures.toSet();
  if (features.contains('android.hardware.type.watch')) return 'watch';
  if (features.contains('android.hardware.type.television')) return 'tv';
  if (features.contains('android.hardware.type.automotive')) {
    return 'automotive';
  }
  if (!features.contains('android.hardware.telephony') &&
      features.contains('android.hardware.touchscreen')) {
    return 'tablet';
  }
  return 'phone';
}

String _inferAndroidGpuFamily(String chipName, String manufacturer) {
  final chip = chipName.toLowerCase();
  final maker = manufacturer.toLowerCase();
  if (chip.contains('snapdragon') ||
      chip.contains('qualcomm') ||
      chip.contains('sdm') ||
      chip.contains('sm8') ||
      chip.contains('sm7') ||
      chip.contains('sm6') ||
      chip.contains('msm') ||
      maker.contains('qualcomm')) {
    return 'adreno';
  }
  if (chip.contains('exynos') ||
      chip.contains('tensor') ||
      chip.contains('mediatek') ||
      chip.contains('dimensity') ||
      chip.contains('helio') ||
      chip.contains('kirin') ||
      maker.contains('google') ||
      maker.contains('samsung')) {
    return 'mali';
  }
  if (chip.contains('intel')) return 'intel';
  if (chip.contains('nvidia') || chip.contains('tegra')) return 'nvidia';
  return 'unknown';
}
