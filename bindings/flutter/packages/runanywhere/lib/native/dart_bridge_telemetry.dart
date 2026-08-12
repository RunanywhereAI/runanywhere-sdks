// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/constants/sdk_constants.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
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
  static Pointer<Void>? _managerPtr;
  static NativeCallable<Void Function(Pointer<Void>)>? _httpWakeup;
  static final Set<Future<void>> _inFlightHttpRequests = {};
  static bool _acceptingHttpRequests = false;

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
        final flushFn = lib
            .lookupFunction<
              Int32 Function(Pointer<Void>),
              int Function(Pointer<Void>)
            >('rac_telemetry_manager_flush');
        flushFn(_managerPtr!);
        _logger.debug('Telemetry flushed');
      } catch (_) {
        _logger.debug('Telemetry flush failed');
      }
    }
  }

  /// Create the telemetry manager and attach it as the C++ event router's
  /// telemetry sink, in Phase 1 — BEFORE commons emits the
  /// INITIALIZATION_STAGE_STARTED/COMPLETED events from rac_sdk_init_phase1_proto.
  /// Without this the "system" modality never lands: those init events fire
  /// during Phase-1 core init, and if the sink is only attached in Phase 2 they
  /// hit a null sink and are dropped. The manager queues events immediately;
  /// the actual flush still waits for Phase 2 (HTTP layer configured). Device
  /// info (async model lookup) is filled in later by [initialize].
  static void attachSinkPhase1({
    required SDKEnvironment environment,
    required String deviceId,
  }) {
    if (_managerPtr != null) return;
    _environment = environment;
    try {
      _createManagerAndAttach(
        PlatformLoader.loadCommons(),
        environment,
        deviceId,
      );
      _logger.debug('Telemetry sink attached in Phase 1');
    } catch (_) {
      _logger.debug('Phase-1 telemetry attach failed');
    }
  }

  /// Create the manager (env/device/platform/sdk), register the HTTP wake-up,
  /// and attach the telemetry sink. Shared by [attachSinkPhase1] (Phase 1) and
  /// the [initialize] fallback (when Phase-1 attach didn't run). Does NOT set
  /// device info or mark initialized.
  static void _createManagerAndAttach(
    DynamicLibrary lib,
    SDKEnvironment environment,
    String deviceId,
  ) {
    final sdkVersion = SDKConstants.version;
    // platform is the OS family (matches iOS "ios"/"macos", Kotlin "android",
    // and the backend telemetry_events.platform contract), NOT the binding.
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
        ? 'ios'
        : Platform.isMacOS
        ? 'macos'
        : 'flutter';

    final createManager = lib
        .lookupFunction<
          Pointer<Void> Function(
            Int32,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
          ),
          Pointer<Void> Function(
            int,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
          )
        >('rac_telemetry_manager_create');

    final deviceIdPtr = deviceId.toNativeUtf8();
    final platformPtr = platform.toNativeUtf8();
    final sdkVersionPtr = sdkVersion.toNativeUtf8();
    try {
      final ptr = createManager(
        _environmentToInt(environment),
        deviceIdPtr,
        platformPtr,
        sdkVersionPtr,
      );
      if (ptr == nullptr) {
        _logger.warning('Failed to create telemetry manager');
        return;
      }
      _managerPtr = ptr;
      _acceptingHttpRequests = true;
      // Register the HTTP wake-up + attach the sink so the router feeds events
      // into the manager (queued until Phase-2 flush).
      _registerHttpCallback();
      _setTelemetrySink(ptr);
    } finally {
      calloc.free(deviceIdPtr);
      calloc.free(platformPtr);
      calloc.free(sdkVersionPtr);
    }
  }

  /// Complete telemetry init (Phase 2): fill in device info. Reuses the manager
  /// created in Phase 1 via [attachSinkPhase1]; only creates one here as a
  /// fallback (gated on a real baseURL) if Phase-1 attach never ran.
  static Future<void> initialize({
    required SDKEnvironment environment,
    required String deviceId,
    String? baseURL,
  }) async {
    if (_isInitialized) {
      _logger.debug('Telemetry already initialized');
      return;
    }
    _environment = environment;

    try {
      final lib = PlatformLoader.loadCommons();

      if (_managerPtr == null) {
        // Fallback: Phase-1 attach didn't run. The auth token isn't available
        // yet (applied at send time — Kotlin parity); only the baseURL must be
        // real, else creating a manager that can never flush is wasteful.
        if (!DartBridgeDevConfig.isUsableCredential(baseURL)) {
          _logger.warning(
            'Telemetry skipped — baseURL looks like a placeholder. '
            'Set a real base URL via dart-define or runtime config.',
          );
          _isInitialized = true; // Suppress retry.
          return;
        }
        _createManagerAndAttach(lib, environment, deviceId);
      }

      if (_managerPtr == null || _managerPtr == nullptr) {
        _isInitialized = true;
        return;
      }

      // Device info — the model/OS lookup is async (device_info_plus), so it
      // only happens here. Ensure the device snapshot is populated first; this
      // runs before Phase 2 device registration refreshes it, so without this
      // the manager would be stamped with the placeholder defaults (model
      // "unknown" + the Platform.operatingSystemVersion build string).
      await DartBridgeDevice.ensureDeviceInfoSnapshot();
      final deviceModel = await _getDeviceModel();
      final cachedOs = DartBridgeDevice.cachedOsVersion.trim();
      final osVersion = cachedOs.isNotEmpty
          ? cachedOs
          : Platform.operatingSystemVersion;
      final setDeviceInfo = lib
          .lookupFunction<
            Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
            void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
          >('rac_telemetry_manager_set_device_info');
      final deviceModelPtr = deviceModel.toNativeUtf8();
      final osVersionPtr = osVersion.toNativeUtf8();
      setDeviceInfo(_managerPtr!, deviceModelPtr, osVersionPtr);
      calloc.free(deviceModelPtr);
      calloc.free(osVersionPtr);

      _isInitialized = true;
      _logger.debug('Telemetry manager initialized');
    } catch (_) {
      _logger.debug('Telemetry initialization failed');
      _isInitialized = true; // Avoid retry loops
    }
  }

  /// Shutdown telemetry manager
  static Future<void> shutdown() async {
    final managerPtr = _managerPtr;
    if (managerPtr == null) {
      _isInitialized = false;
      _environment = null;
      _acceptingHttpRequests = false;
      return;
    }
    var managerDestroyed = false;
    try {
      final lib = PlatformLoader.loadCommons();

      // Detach the telemetry sink first so the C++ router stops feeding events
      // into a manager we are about to destroy. This is a strict ownership
      // boundary: on failure the pointer and wake-up callable stay alive so a
      // fail-closed reset retry can quiesce them safely.
      _setTelemetrySink(nullptr, requireSuccess: true);

      try {
        // Flush synchronously, then drain the manager-owned queue directly.
        // NativeCallable.listener wake-ups are asynchronous, so closing the
        // callable immediately after flush would otherwise drop the terminal
        // shutdown batch.
        final flush = lib
            .lookupFunction<
              Int32 Function(Pointer<Void>),
              int Function(Pointer<Void>)
            >('rac_telemetry_manager_flush');
        flush(managerPtr);
      } catch (_) {
        _logger.debug('Telemetry flush failed during shutdown');
      }
      drainHttpQueue();
      _acceptingHttpRequests = false;

      // No later SDK lifetime may reuse HTTP credentials while an older
      // telemetry request is still running. Requests swallow their own
      // transport errors, so this join is deterministic.
      while (_inFlightHttpRequests.isNotEmpty) {
        await Future.wait(List<Future<void>>.of(_inFlightHttpRequests));
      }

      final destroy = lib
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('rac_telemetry_manager_destroy');
      destroy(managerPtr);
      managerDestroyed = true;
      _logger.debug('Telemetry manager shutdown');
    } catch (_) {
      _logger.error('Telemetry shutdown failed');
      rethrow;
    } finally {
      if (managerDestroyed) {
        if (_managerPtr == managerPtr) _managerPtr = null;
        _isInitialized = false;
        _environment = null;
        _acceptingHttpRequests = false;
        _httpWakeup?.close();
        _httpWakeup = null;
      }
    }
  }

  /// Attach (or detach with [nullptr]) the telemetry manager as the C++ event
  /// router's telemetry sink. Matches how the other one-shot C functions are
  /// looked up in this file. The C signature is
  /// `void rac_events_set_telemetry_sink(void* telemetry_manager)`.
  static void _setTelemetrySink(
    Pointer<Void> manager, {
    bool requireSuccess = false,
  }) {
    try {
      final lib = PlatformLoader.loadCommons();
      final setSink = lib
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('rac_events_set_telemetry_sink');
      setSink(manager);
      _logger.debug(
        'Telemetry sink ${manager == nullptr ? "detached" : "attached"}',
      );
    } catch (_) {
      _logger.debug('Failed to update telemetry sink');
      if (requireSuccess) rethrow;
    }
  }

  // ============================================================================
  // HTTP Callback Registration
  // ============================================================================

  static void _registerHttpCallback() {
    if (_managerPtr == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final setWakeup = lib
          .lookupFunction<
            Void Function(
              Pointer<Void>,
              Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
              Pointer<Void>,
            ),
            void Function(
              Pointer<Void>,
              Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
              Pointer<Void>,
            )
          >('rac_telemetry_manager_set_http_wakeup');

      // NativeCallable.listener is cross-isolate-safe: commons may signal this
      // from the LLM worker isolate during a generation-completion flush, and
      // Dart dispatches it back to this (main) isolate. The wake-up carries no
      // request data, so it avoids the "native callback from a different
      // isolate" abort a data-carrying Pointer.fromFunction hit. On wake-up we
      // drain commons' owned request queue via rac_telemetry_manager_poll_*.
      final wakeup = NativeCallable<Void Function(Pointer<Void>)>.listener(
        _telemetryHttpWakeup,
      );
      _httpWakeup = wakeup;
      setWakeup(_managerPtr!, wakeup.nativeFunction, nullptr);
      _logger.debug('Telemetry HTTP wake-up registered');
    } catch (_) {
      _logger.debug('Failed to register telemetry HTTP wake-up');
    }
  }

  /// Drain commons' queued telemetry HTTP requests (signalled by the wake-up).
  /// Each request is an owned buffer framed as
  /// [u8 requiresAuth][u32 LE endpointLen][endpoint][json].
  static void drainHttpQueue() {
    final managerPtr = _managerPtr;
    if (managerPtr == null || !_acceptingHttpRequests) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final pollFn = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<RacProtoBuffer>),
            int Function(Pointer<Void>, Pointer<RacProtoBuffer>)
          >('rac_telemetry_manager_poll_http_request');
      final bindings = RacNative.bindings;

      // Bounded so a misbehaving producer can't spin forever; the loop also
      // exits as soon as poll reports an empty queue (rc != 0).
      for (var i = 0; i < 256; i++) {
        final out = calloc<RacProtoBuffer>();
        try {
          bindings.rac_proto_buffer_init(out);
          final code = pollFn(managerPtr, out);
          // RAC_SUCCESS == 0; anything else (e.g. RAC_ERROR_NOT_FOUND) = drained.
          if (code != 0 || out.ref.data == nullptr || out.ref.size < 5) {
            return;
          }
          final bytes = out.ref.data
              .asTypedList(out.ref.size)
              .toList(growable: false);
          final requiresAuth = bytes[0] != 0;
          final endpointLen =
              bytes[1] | (bytes[2] << 8) | (bytes[3] << 16) | (bytes[4] << 24);
          final endpoint = utf8.decode(bytes.sublist(5, 5 + endpointLen));
          final body = utf8.decode(bytes.sublist(5 + endpointLen));
          late final Future<void> request;
          request = _sendTelemetryHttp(
            endpoint,
            body,
            requiresAuth,
          ).whenComplete(() => _inFlightHttpRequests.remove(request));
          _inFlightHttpRequests.add(request);
        } finally {
          bindings.rac_proto_buffer_free(out);
          calloc.free(out);
        }
      }
    } catch (_) {
      _logger.debug('Telemetry HTTP queue drain failed');
    }
  }

  // ============================================================================
  // Internal Helpers
  // ============================================================================

  static Future<String> _getDeviceModel() async {
    final deviceModel = DartBridgeDevice.cachedDeviceModel.trim();
    return deviceModel.isEmpty ? 'unknown' : deviceModel;
  }

  static int _environmentToInt(SDKEnvironment env) {
    switch (env) {
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
        return 0;
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        return 2;
      default:
        return 0;
    }
  }
}

// =============================================================================
// HTTP Wake-up Function
// =============================================================================

/// Wake-up from commons (may be signalled from any isolate, e.g. the LLM
/// streaming worker isolate). Registered as a `NativeCallable.listener` so the
/// drain runs on this (main) isolate regardless of the caller. No request data
/// is passed here — it is pulled from commons' owned queue in [drainHttpQueue].
void _telemetryHttpWakeup(Pointer<Void> userData) {
  DartBridgeTelemetry.drainHttpQueue();
}

/// Send telemetry via HTTP.
///
/// Routes through the adapter's authenticated [HTTPClientAdapter.send] so the
/// request carries the resolved SDK access token (with 401-refresh) and the
/// canonical SDK headers. The backend telemetry endpoints require a valid
/// bearer token (`validate_sdk_bearer_token`); the previous `rawRequest` path
/// only attached `_accessToken`, which is never populated here, so every
/// telemetry POST was unauthenticated. Kotlin parity: telemetry goes through
/// the token-managed adapter, not a hand-built request.
Future<void> _sendTelemetryHttp(
  String endpoint,
  String body,
  bool requiresAuth,
) async {
  try {
    final response = await HTTPClientAdapter.shared.send(
      method: 'POST',
      path: endpoint,
      body: body,
      requiresAuth: requiresAuth,
    );

    if (response.isSuccess) {
      DartBridgeTelemetry._logger.info(
        'Telemetry POST succeeded with status ${response.statusCode}',
      );
    } else {
      DartBridgeTelemetry._logger.warning(
        'Telemetry POST failed with status ${response.statusCode}',
      );
    }

    _notifyHttpComplete(
      response.isSuccess,
      response.body,
      response.isSuccess ? null : 'HTTP ${response.statusCode}',
    );
  } catch (_) {
    _notifyHttpComplete(false, null, 'Telemetry transport failed');
  }
}

/// Notify C++ of HTTP completion
void _notifyHttpComplete(bool success, String? responseJson, String? error) {
  if (DartBridgeTelemetry._managerPtr == null) return;

  try {
    final lib = PlatformLoader.loadCommons();
    final httpComplete = lib
        .lookupFunction<
          Void Function(Pointer<Void>, Int32, Pointer<Utf8>, Pointer<Utf8>),
          void Function(Pointer<Void>, int, Pointer<Utf8>, Pointer<Utf8>)
        >('rac_telemetry_manager_http_complete');

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
