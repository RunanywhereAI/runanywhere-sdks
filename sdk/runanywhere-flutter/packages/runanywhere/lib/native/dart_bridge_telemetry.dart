// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffi/ffi.dart';

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_environment.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

// =============================================================================
// Telemetry Manager Bridge
// =============================================================================

/// Telemetry bridge for C++ telemetry operations.
/// Matches Swift's `CppBridge+Telemetry.swift`.
///
/// C++ handles all telemetry logic:
/// - Convert analytics events to telemetry payloads
/// - Queue and batch events
/// - Group by modality for production
/// - Serialize to JSON (environment-aware)
/// - Callback to Dart for HTTP calls
///
/// Dart provides:
/// - Device info
/// - HTTP transport for sending telemetry
class DartBridgeTelemetry {
  DartBridgeTelemetry._();

  static final _logger = SDKLogger('DartBridge.Telemetry');
  static final DartBridgeTelemetry instance = DartBridgeTelemetry._();

  static bool _isInitialized = false;
  // ignore: unused_field
  static SDKEnvironment? _environment;
  static String? _baseURL;
  static String? _accessToken;
  static Pointer<Void>? _managerPtr;
  static Pointer<NativeFunction<RacTelemetryHttpCallbackNative>>?
      _httpCallbackPtr;

  // ============================================================================
  // Lifecycle
  // ============================================================================

  /// Synchronous initialization - just stores environment.
  /// Matches Swift's Telemetry.initialize() in Phase 1 (minimal setup).
  /// Full initialization with device info happens in Phase 2 via initialize().
  static void initializeSync({required SDKEnvironment environment}) {
    _environment = environment;
    _logger.debug('Telemetry sync init for ${environment.name}');
  }

  /// Flush any queued telemetry events.
  /// Static method that delegates to instance if initialized.
  /// Matches Swift: CppBridge.Telemetry.flush()
  static void flush() {
    if (_isInitialized && _managerPtr != null) {
      try {
        final lib = PlatformLoader.loadCommons();
        final flushFn = lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('rac_telemetry_manager_flush');
        flushFn(_managerPtr!);
        _logger.debug('Telemetry flushed');
      } catch (e) {
        _logger.debug('flush error: $e');
      }
    }
  }

  /// Initialize telemetry manager with device info (full async init)
  static Future<void> initialize({
    required SDKEnvironment environment,
    required String deviceId,
    String? baseURL,
    String? accessToken,
  }) async {
    if (_isInitialized) {
      _logger.debug('Telemetry already initialized');
      return;
    }

    // Bail out if the example app forwarded an unfilled
    // .env / dart-define placeholder. We don't want to POST telemetry
    // to a literal "YOUR_SUPABASE_PROJECT_URL" string.
    if (!DartBridgeDevConfig.isUsableCredential(baseURL) ||
        !DartBridgeDevConfig.isUsableCredential(accessToken)) {
      _logger.warning(
        'Telemetry skipped — baseURL/accessToken looks like a placeholder. '
        'Set real values via dart-define or runtime config.',
      );
      _isInitialized = true; // Suppress retry.
      return;
    }

    _environment = environment;
    _baseURL = baseURL;
    _accessToken = accessToken;

    try {
      final lib = PlatformLoader.loadCommons();

      // Get device info
      final deviceModel = await _getDeviceModel();
      final osVersion = Platform.operatingSystemVersion;
      const sdkVersion = '0.19.13';
      const platform = 'flutter';

      // Create telemetry manager
      final createManager = lib.lookupFunction<
          Pointer<Void> Function(
              Int32, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          Pointer<Void> Function(int, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_telemetry_manager_create');

      final envValue = _environmentToInt(environment);
      final deviceIdPtr = deviceId.toNativeUtf8();
      final platformPtr = platform.toNativeUtf8();
      final sdkVersionPtr = sdkVersion.toNativeUtf8();

      try {
        _managerPtr =
            createManager(envValue, deviceIdPtr, platformPtr, sdkVersionPtr);

        if (_managerPtr == nullptr ||
            _managerPtr == Pointer<Void>.fromAddress(0)) {
          _logger.warning('Failed to create telemetry manager');
          return;
        }

        // Set device info
        final setDeviceInfo = lib.lookupFunction<
            Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
            void Function(Pointer<Void>, Pointer<Utf8>,
                Pointer<Utf8>)>('rac_telemetry_manager_set_device_info');

        final deviceModelPtr = deviceModel.toNativeUtf8();
        final osVersionPtr = osVersion.toNativeUtf8();

        setDeviceInfo(_managerPtr!, deviceModelPtr, osVersionPtr);

        calloc.free(deviceModelPtr);
        calloc.free(osVersionPtr);

        // Register HTTP callback
        _registerHttpCallback();

        // Attach this manager as the C++ event router's telemetry sink. The
        // router (`rac::events::route`) forwards every event whose destination
        // carries the TELEMETRY bit into the manager via
        // `rac_telemetry_manager_track_proto` and does the per-event translation
        // internally — Dart no longer forwards per-event analytics. Mirrors
        // Swift's `rac_events_set_telemetry_sink(mgr.ptr)`.
        _setTelemetrySink(_managerPtr!);

        _isInitialized = true;
        _logger.debug('Telemetry manager initialized');
      } finally {
        calloc.free(deviceIdPtr);
        calloc.free(platformPtr);
        calloc.free(sdkVersionPtr);
      }
    } catch (e, stack) {
      _logger.debug('Telemetry initialization error: $e', metadata: {
        'stack': stack.toString(),
      });
      _isInitialized = true; // Avoid retry loops
    }
  }

  /// Shutdown telemetry manager
  static void shutdown() {
    if (!_isInitialized || _managerPtr == null) return;

    try {
      final lib = PlatformLoader.loadCommons();

      // Detach the telemetry sink first so the C++ router stops feeding events
      // into a manager we are about to destroy.
      _setTelemetrySink(nullptr);

      final destroy = lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_telemetry_manager_destroy');

      destroy(_managerPtr!);
      _managerPtr = null;
      _isInitialized = false;
      _logger.debug('Telemetry manager shutdown');
    } catch (e) {
      _logger.debug('Telemetry shutdown error: $e');
    }
  }

  /// Attach (or detach with [nullptr]) the telemetry manager as the C++ event
  /// router's telemetry sink. Matches how the other one-shot C functions are
  /// looked up in this file. The C signature is
  /// `void rac_events_set_telemetry_sink(void* telemetry_manager)`.
  static void _setTelemetrySink(Pointer<Void> manager) {
    try {
      final lib = PlatformLoader.loadCommons();
      final setSink = lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_events_set_telemetry_sink');
      setSink(manager);
      _logger.debug('Telemetry sink ${manager == nullptr ? "detached" : "attached"}');
    } catch (e) {
      _logger.debug('Failed to set telemetry sink: $e');
    }
  }

  /// Update access token
  static void setAccessToken(String? token) {
    _accessToken = token;
  }

  // ============================================================================
  // HTTP Callback Registration
  // ============================================================================

  static void _registerHttpCallback() {
    if (_managerPtr == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final setCallback = lib.lookupFunction<
          Void Function(
              Pointer<Void>,
              Pointer<NativeFunction<RacTelemetryHttpCallbackNative>>,
              Pointer<Void>),
          void Function(
              Pointer<Void>,
              Pointer<NativeFunction<RacTelemetryHttpCallbackNative>>,
              Pointer<Void>)>('rac_telemetry_manager_set_http_callback');

      _httpCallbackPtr = Pointer.fromFunction<RacTelemetryHttpCallbackNative>(
          _telemetryHttpCallback);

      setCallback(_managerPtr!, _httpCallbackPtr!, nullptr);
      _logger.debug('Telemetry HTTP callback registered');
    } catch (e) {
      _logger.debug('Failed to register HTTP callback: $e');
    }
  }

  // ============================================================================
  // Internal Helpers
  // ============================================================================

  static Future<String> _getDeviceModel() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.model;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        return macInfo.model;
      }
      return 'unknown';
    } catch (e) {
      return 'unknown';
    }
  }

  static int _environmentToInt(SDKEnvironment env) {
    switch (env) {
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
        return 0;
      case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
        return 1;
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        return 2;
      default:
        return 0;
    }
  }
}

// =============================================================================
// HTTP Callback Function
// =============================================================================

/// HTTP callback invoked by C++ when telemetry needs to be sent
void _telemetryHttpCallback(
  Pointer<Void> userData,
  Pointer<Utf8> endpoint,
  Pointer<Utf8> jsonBody,
  int jsonLength,
  int requiresAuth,
) {
  if (endpoint == nullptr || jsonBody == nullptr) return;

  try {
    final endpointStr = endpoint.toDartString();
    final bodyStr = jsonBody.toDartString();
    final needsAuth = requiresAuth != 0;

    // Fire and forget HTTP call
    unawaited(_sendTelemetryHttp(endpointStr, bodyStr, needsAuth));
  } catch (e) {
    SDKLogger('DartBridge.Telemetry').error('HTTP callback error: $e');
  }
}

/// Send telemetry via HTTP
Future<void> _sendTelemetryHttp(
    String endpoint, String body, bool requiresAuth) async {
  try {
    final baseURL =
        DartBridgeTelemetry._baseURL ?? 'https://api.runanywhere.ai';
    final url = '$baseURL$endpoint';

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (requiresAuth && DartBridgeTelemetry._accessToken != null) {
      headers['Authorization'] = 'Bearer ${DartBridgeTelemetry._accessToken}';
    }

    final response = await HTTPClientAdapter.shared.rawRequest(
      method: 'POST',
      url: url,
      headers: headers,
      body: Uint8List.fromList(utf8.encode(body)),
    );

    _notifyHttpComplete(
      response.isSuccess,
      response.body,
      null,
    );
  } catch (e) {
    _notifyHttpComplete(false, null, e.toString());
  }
}

/// Notify C++ of HTTP completion
void _notifyHttpComplete(bool success, String? responseJson, String? error) {
  if (DartBridgeTelemetry._managerPtr == null) return;

  try {
    final lib = PlatformLoader.loadCommons();
    final httpComplete = lib.lookupFunction<
        Void Function(Pointer<Void>, Int32, Pointer<Utf8>, Pointer<Utf8>),
        void Function(Pointer<Void>, int, Pointer<Utf8>,
            Pointer<Utf8>)>('rac_telemetry_manager_http_complete');

    final responsePtr = responseJson?.toNativeUtf8() ?? nullptr;
    final errorPtr = error?.toNativeUtf8() ?? nullptr;

    try {
      httpComplete(
        DartBridgeTelemetry._managerPtr!,
        success ? 1 : 0,
        responsePtr.cast<Utf8>(),
        errorPtr.cast<Utf8>(),
      );
    } finally {
      if (responsePtr != nullptr) calloc.free(responsePtr);
      if (errorPtr != nullptr) calloc.free(errorPtr);
    }
  } catch (e) {
    // Ignore - best effort notification
  }
}

// =============================================================================
// FFI Types
// =============================================================================

/// HTTP callback type: void (*callback)(void*, const char*, const char*, size_t, rac_bool_t)
typedef RacTelemetryHttpCallbackNative = Void Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, IntPtr, Int32);
