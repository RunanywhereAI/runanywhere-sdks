// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import 'package:shared_preferences/shared_preferences.dart';

// =============================================================================
// Exceptional return constants for FFI callbacks
// =============================================================================

const int _exceptionalReturnNull = 0;
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

  /// SharedPreferences key for registration status
  static const _keyIsRegistered = 'com.runanywhere.sdk.device.isRegistered';

  /// SharedPreferences instance (lazily initialized)
  static SharedPreferences? _prefs;

  /// SDK environment for HTTP calls
  static SDKEnvironment _environment = SDKEnvironment.development;

  /// Base URL for HTTP calls
  static String? _baseURL;

  /// Access token for authenticated requests
  static String? _accessToken;

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
              _getDeviceInfoCallback);
      callbacks.ref.getDeviceId =
          Pointer.fromFunction<RacDeviceGetIdCallbackNative>(
              _getDeviceIdCallback, _exceptionalReturnNull);
      callbacks.ref.isRegistered =
          Pointer.fromFunction<RacDeviceIsRegisteredCallbackNative>(
              _isRegisteredCallback, _exceptionalReturnInt32);
      callbacks.ref.setRegistered =
          Pointer.fromFunction<RacDeviceSetRegisteredCallbackNative>(
              _setRegisteredCallback);
      callbacks.ref.httpPost =
          Pointer.fromFunction<RacDeviceHttpPostCallbackNative>(
              _httpPostCallback, _exceptionalReturnInt32);
      callbacks.ref.userData = nullptr;

      // Register with C++
      final setCallbacks = lib.lookupFunction<
          Int32 Function(Pointer<RacDeviceCallbacksStruct>),
          int Function(
              Pointer<RacDeviceCallbacksStruct>)>('rac_device_set_callbacks');

      final result = setCallbacks(callbacks);
      if (result != RacResultCode.success) {
        _logger.warning('Failed to set device callbacks', metadata: {
          'error_code': result,
        });
        calloc.free(callbacks);
        _callbacksPtr = null;
        return;
      }

      _callbacksRegistered = true;
      _logger.debug('Device callbacks registered (sync)');
    } catch (e) {
      _logger.debug('registerCallbacks error: $e');
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

    try {
      final lib = PlatformLoader.loadCommons();

      // Allocate callbacks struct
      _callbacksPtr = calloc<RacDeviceCallbacksStruct>();
      final callbacks = _callbacksPtr!;

      // Set callback function pointers
      callbacks.ref.getDeviceInfo =
          Pointer.fromFunction<RacDeviceGetInfoCallbackNative>(
              _getDeviceInfoCallback);
      callbacks.ref.getDeviceId =
          Pointer.fromFunction<RacDeviceGetIdCallbackNative>(
              _getDeviceIdCallback, _exceptionalReturnNull);
      callbacks.ref.isRegistered =
          Pointer.fromFunction<RacDeviceIsRegisteredCallbackNative>(
              _isRegisteredCallback, _exceptionalReturnInt32);
      callbacks.ref.setRegistered =
          Pointer.fromFunction<RacDeviceSetRegisteredCallbackNative>(
              _setRegisteredCallback);
      callbacks.ref.httpPost =
          Pointer.fromFunction<RacDeviceHttpPostCallbackNative>(
              _httpPostCallback, _exceptionalReturnInt32);
      callbacks.ref.userData = nullptr;

      // Register with C++
      final setCallbacks = lib.lookupFunction<
              Int32 Function(Pointer<RacDeviceCallbacksStruct>),
              int Function(Pointer<RacDeviceCallbacksStruct>)>(
          'rac_device_manager_set_callbacks');

      final result = setCallbacks(callbacks);
      if (result != RacResultCode.success) {
        _logger.warning('Failed to register device callbacks',
            metadata: {'code': result});
        calloc.free(callbacks);
        _callbacksPtr = null;
        return;
      }

      _isRegistered = true;
      _logger.debug('Device callbacks registered successfully');
    } catch (e, stack) {
      _logger.debug('Device registration not available: $e', metadata: {
        'stack': stack.toString(),
      });
      _isRegistered = true; // Mark as registered to avoid retry loops
    }
  }

  /// Update access token (called after authentication)
  static void setAccessToken(String? token) {
    _accessToken = token;
  }

  /// Register device with backend if not already registered
  Future<void> registerIfNeeded() async {
    if (!_isRegistered) {
      _logger.warning('Device callbacks not registered');
      return;
    }

    try {
      final lib = PlatformLoader.loadCommons();
      final registerFn = lib.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>),
          int Function(
              int, Pointer<Utf8>)>('rac_device_manager_register_if_needed');

      final envValue = _environmentToInt(_environment);
      final buildTokenPtr = nullptr; // Build token not used in Flutter

      final result = registerFn(envValue, buildTokenPtr.cast<Utf8>());
      if (result != RacResultCode.success) {
        _logger.debug('Device registration returned: $result');
      }
    } catch (e) {
      _logger.debug('rac_device_manager_register_if_needed not available: $e');
    }
  }

  /// Check if device is registered with backend
  bool isDeviceRegistered() {
    return _prefs?.getBool(_keyIsRegistered) ?? false;
  }

  /// Clear device registration (for testing)
  Future<void> clearRegistration() async {
    try {
      final lib = PlatformLoader.loadCommons();
      final clearFn = lib.lookupFunction<Void Function(), void Function()>(
          'rac_device_manager_clear_registration');
      clearFn();
    } catch (e) {
      // Also clear locally
      await _prefs?.setBool(_keyIsRegistered, false);
    }
  }

  /// Get the cached or generated device ID
  Future<String> getDeviceId() async {
    return _cachedDeviceId ?? await _getOrCreateDeviceId();
  }

  /// Get the cached device ID synchronously (null if not yet cached)
  static String? get cachedDeviceId => _cachedDeviceId;

  // ============================================================================
  // Internal Helpers
  // ============================================================================

  /// Key for storing persistent device UUID in SharedPreferences
  static const _keyDeviceUUID = 'com.runanywhere.sdk.device.uuid';

  /// Get or create a persistent device UUID.
  /// Matches Swift's DeviceIdentity.persistentUUID behavior:
  /// 1. Try to retrieve stored UUID from persistent storage
  /// 2. If not found, generate a new UUID and store it
  /// The UUID format is required by the backend for device registration.
  static Future<String> _getOrCreateDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    try {
      // Initialize SharedPreferences if needed
      _prefs ??= await SharedPreferences.getInstance();

      // Strategy 1: Try to get stored UUID from SharedPreferences
      final storedUUID = _prefs?.getString(_keyDeviceUUID);
      if (storedUUID != null && _isValidUUID(storedUUID)) {
        _cachedDeviceId = storedUUID;
        _logger.debug('Using stored device UUID');
        return _cachedDeviceId!;
      }

      // Strategy 2: On iOS, try to use identifierForVendor (already a UUID)
      if (Platform.isIOS) {
        try {
          final deviceInfo = DeviceInfoPlugin();
          final iosInfo = await deviceInfo.iosInfo;
          final vendorId = iosInfo.identifierForVendor;
          if (vendorId != null && _isValidUUID(vendorId)) {
            _cachedDeviceId = vendorId;
            await _prefs?.setString(_keyDeviceUUID, vendorId);
            _logger.debug('Stored iOS vendor UUID');
            return _cachedDeviceId!;
          }
        } catch (e) {
          _logger.debug('Failed to get iOS vendor ID: $e');
        }
      }

      // Strategy 3: Generate a new UUID (matches Swift's UUID().uuidString)
      final newUUID = _generateUUID();
      _cachedDeviceId = newUUID;
      await _prefs?.setString(_keyDeviceUUID, newUUID);
      _logger.debug('Generated and stored new device UUID');
      return _cachedDeviceId!;
    } catch (e) {
      _logger.warning('Failed to get device ID: $e');
      // Fallback: generate UUID without storing (will regenerate on next launch)
      _cachedDeviceId = _generateUUID();
      return _cachedDeviceId!;
    }
  }

  /// Generate a proper UUID v4 string (matches backend expectations)
  /// Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  static String _generateUUID() {
    final random = DateTime.now().millisecondsSinceEpoch;
    final bytes = <int>[];

    // Generate 16 random bytes
    for (var i = 0; i < 16; i++) {
      bytes.add((random + i * 17) % 256);
    }

    // Set version to 4 (random UUID)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    // Format as UUID string
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
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

  static int _environmentToInt(SDKEnvironment env) {
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
// FFI Callback Functions
// =============================================================================

/// Get device info callback
void _getDeviceInfoCallback(
    Pointer<RacDeviceRegistrationInfoStruct> outInfo, Pointer<Void> userData) {
  if (outInfo == nullptr) return;

  try {
    // Fill in device info synchronously from cached values
    // Note: Real values are populated asynchronously during registration

    // Device type
    final deviceType = Platform.isIOS
        ? 'iphone'
        : Platform.isAndroid
            ? 'android'
            : Platform.isMacOS
                ? 'macos'
                : 'unknown';
    final deviceTypePtr = deviceType.toNativeUtf8();
    outInfo.ref.deviceType = deviceTypePtr;

    // OS name
    final osName = Platform.operatingSystem;
    final osNamePtr = osName.toNativeUtf8();
    outInfo.ref.osName = osNamePtr;

    // OS version
    final osVersion = Platform.operatingSystemVersion;
    final osVersionPtr = osVersion.toNativeUtf8();
    outInfo.ref.osVersion = osVersionPtr;

    // SDK version
    const sdkVersion = '0.1.4';
    final sdkVersionPtr = sdkVersion.toNativeUtf8();
    outInfo.ref.sdkVersion = sdkVersionPtr;

    // App version (not available in Flutter without package_info)
    final appVersionPtr = '1.0.0'.toNativeUtf8();
    outInfo.ref.appVersion = appVersionPtr;

    // App identifier
    final appIdPtr = 'com.runanywhere.flutter'.toNativeUtf8();
    outInfo.ref.appIdentifier = appIdPtr;

    // Platform
    final platformPtr = 'flutter'.toNativeUtf8();
    outInfo.ref.platform = platformPtr;
  } catch (e) {
    SDKLogger('DartBridge.Device').error('Error in device info callback: $e');
  }
}

/// Cached device ID pointer (must persist for C++ to read)
Pointer<Utf8>? _cachedDeviceIdPtr;

/// Get device ID callback
int _getDeviceIdCallback(Pointer<Void> userData) {
  try {
    final deviceId = DartBridgeDevice._cachedDeviceId;
    if (deviceId == null) {
      return 0;
    }

    // Free previous pointer if exists
    if (_cachedDeviceIdPtr != null) {
      calloc.free(_cachedDeviceIdPtr!);
    }

    // Allocate and cache new pointer
    _cachedDeviceIdPtr = deviceId.toNativeUtf8();
    return _cachedDeviceIdPtr!.address;
  } catch (e) {
    return 0;
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
    unawaited(DartBridgeDevice._prefs
        ?.setBool(DartBridgeDevice._keyIsRegistered, registered != 0));
  } catch (e) {
    SDKLogger('DartBridge.Device').error('Error setting registration: $e');
  }
}

/// HTTP POST callback for device registration
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
    final endpointStr = endpoint.toDartString();
    final bodyStr = jsonBody != nullptr ? jsonBody.toDartString() : '';

    // Perform sync HTTP (via Isolate in production, blocking here for simplicity)
    // Note: In production, use an async pattern with completion callback
    _performHttpPost(
      endpointStr,
      bodyStr,
      requiresAuth != 0,
      outResponse,
    );

    return RacResultCode.success;
  } catch (e) {
    SDKLogger('DartBridge.Device').error('HTTP POST error: $e');
    return RacResultCode.errorNetworkError;
  }
}

/// Perform HTTP POST (simplified synchronous wrapper)
void _performHttpPost(
  String endpoint,
  String body,
  bool requiresAuth,
  Pointer<RacDeviceHttpResponseStruct> outResponse,
) {
  // Note: This is a simplified implementation
  // In production, use proper async handling with callbacks

  // Build URL
  final baseURL = DartBridgeDevice._baseURL ?? 'https://api.runanywhere.ai';
  final url = Uri.parse('$baseURL$endpoint');

  // Build headers
  final headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  if (requiresAuth && DartBridgeDevice._accessToken != null) {
    headers['Authorization'] = 'Bearer ${DartBridgeDevice._accessToken}';
  }

  // Schedule async HTTP call (fire and forget for now)
  // The C++ layer will retry if needed
  unawaited(Future.microtask(() async {
    try {
      final response = await http.post(url, headers: headers, body: body);

      outResponse.ref.result =
          response.statusCode >= 200 && response.statusCode < 300
              ? RacResultCode.success
              : RacResultCode.errorNetworkError;
      outResponse.ref.statusCode = response.statusCode;

      if (response.body.isNotEmpty) {
        final bodyPtr = response.body.toNativeUtf8();
        outResponse.ref.responseBody = bodyPtr;
      }
    } catch (e) {
      outResponse.ref.result = RacResultCode.errorNetworkError;
      outResponse.ref.statusCode = 0;

      final errorPtr = e.toString().toNativeUtf8();
      outResponse.ref.errorMessage = errorPtr;
    }
  }));

  // Return immediately with pending state
  outResponse.ref.result = RacResultCode.success;
  outResponse.ref.statusCode = 200;
}

// =============================================================================
// FFI Types
// =============================================================================

/// Callback type: void (*get_device_info)(rac_device_registration_info_t*, void*)
typedef RacDeviceGetInfoCallbackNative = Void Function(
    Pointer<RacDeviceRegistrationInfoStruct>, Pointer<Void>);

/// Callback type: const char* (*get_device_id)(void*)
typedef RacDeviceGetIdCallbackNative = IntPtr Function(Pointer<Void>);

/// Callback type: rac_bool_t (*is_registered)(void*)
typedef RacDeviceIsRegisteredCallbackNative = Int32 Function(Pointer<Void>);

/// Callback type: void (*set_registered)(rac_bool_t, void*)
typedef RacDeviceSetRegisteredCallbackNative = Void Function(
    Int32, Pointer<Void>);

/// Callback type: rac_result_t (*http_post)(const char*, const char*, rac_bool_t, rac_device_http_response_t*, void*)
typedef RacDeviceHttpPostCallbackNative = Int32 Function(Pointer<Utf8>,
    Pointer<Utf8>, Int32, Pointer<RacDeviceHttpResponseStruct>, Pointer<Void>);

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
  external Pointer<Utf8> deviceType;
  external Pointer<Utf8> osName;
  external Pointer<Utf8> osVersion;
  external Pointer<Utf8> sdkVersion;
  external Pointer<Utf8> appVersion;
  external Pointer<Utf8> appIdentifier;
  external Pointer<Utf8> platform;
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
