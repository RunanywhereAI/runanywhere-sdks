// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;

import '../public/configuration/sdk_environment.dart';
import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

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

  /// Initialize telemetry manager with device info
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

    _environment = environment;
    _baseURL = baseURL;
    _accessToken = accessToken;

    try {
      final lib = PlatformLoader.loadCommons();

      // Get device info
      final deviceModel = await _getDeviceModel();
      final osVersion = Platform.operatingSystemVersion;
      const sdkVersion = '0.1.4';
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

  /// Update access token
  static void setAccessToken(String? token) {
    _accessToken = token;
  }

  // ============================================================================
  // Event Tracking
  // ============================================================================

  /// Track a telemetry event (via analytics event type)
  Future<void> trackEvent({
    required int eventType,
    Map<String, dynamic>? data,
  }) async {
    if (!_isInitialized || _managerPtr == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final trackAnalytics = lib.lookupFunction<
              Int32 Function(
                  Pointer<Void>, Int32, Pointer<RacAnalyticsEventDataStruct>),
              int Function(
                  Pointer<Void>, int, Pointer<RacAnalyticsEventDataStruct>)>(
          'rac_telemetry_manager_track_analytics');

      // Build event data struct
      final eventData = calloc<RacAnalyticsEventDataStruct>();
      _populateEventData(eventData, data);

      try {
        final result = trackAnalytics(_managerPtr!, eventType, eventData);
        if (result != RacResultCode.success) {
          _logger.debug('Track event failed', metadata: {'code': result});
        }
      } finally {
        _freeEventData(eventData);
        calloc.free(eventData);
      }
    } catch (e) {
      _logger.debug('trackEvent error: $e');
    }
  }

  /// Track a raw telemetry payload
  Future<void> trackPayload(Map<String, dynamic> payload) async {
    if (!_isInitialized || _managerPtr == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final trackFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>),
          int Function(Pointer<Void>,
              Pointer<Utf8>)>('rac_telemetry_manager_track_json');

      final jsonStr = jsonEncode(payload);
      final jsonPtr = jsonStr.toNativeUtf8();

      try {
        trackFn(_managerPtr!, jsonPtr);
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      _logger.debug('trackPayload error: $e');
    }
  }

  /// Flush pending telemetry
  Future<void> flush() async {
    if (!_isInitialized || _managerPtr == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final flushFn = lib.lookupFunction<Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)>('rac_telemetry_manager_flush');

      flushFn(_managerPtr!);
    } catch (e) {
      _logger.debug('flush error: $e');
    }
  }

  // ============================================================================
  // Event Helpers (like Swift's emitDownloadStarted, etc.)
  // ============================================================================

  /// Emit download started event
  Future<void> emitDownloadStarted({
    required String modelId,
    required String modelName,
    required int modelSize,
    required String framework,
  }) async {
    await trackEvent(
      eventType: RacEventType.downloadStarted,
      data: {
        'modelId': modelId,
        'modelName': modelName,
        'modelSize': modelSize,
        'framework': framework,
      },
    );
  }

  /// Emit download completed event
  Future<void> emitDownloadCompleted({
    required String modelId,
    required String modelName,
    required int modelSize,
    required String framework,
    required int durationMs,
  }) async {
    await trackEvent(
      eventType: RacEventType.downloadCompleted,
      data: {
        'modelId': modelId,
        'modelName': modelName,
        'modelSize': modelSize,
        'framework': framework,
        'durationMs': durationMs,
      },
    );
  }

  /// Emit download failed event
  Future<void> emitDownloadFailed({
    required String modelId,
    required String modelName,
    required String error,
    required String framework,
  }) async {
    await trackEvent(
      eventType: RacEventType.downloadFailed,
      data: {
        'modelId': modelId,
        'modelName': modelName,
        'error': error,
        'framework': framework,
      },
    );
  }

  /// Emit extraction started event
  Future<void> emitExtractionStarted({
    required String modelId,
    required String modelName,
    required String framework,
  }) async {
    await trackEvent(
      eventType: RacEventType.extractionStarted,
      data: {
        'modelId': modelId,
        'modelName': modelName,
        'framework': framework,
      },
    );
  }

  /// Emit extraction completed event
  Future<void> emitExtractionCompleted({
    required String modelId,
    required String modelName,
    required String framework,
    required int durationMs,
  }) async {
    await trackEvent(
      eventType: RacEventType.extractionCompleted,
      data: {
        'modelId': modelId,
        'modelName': modelName,
        'framework': framework,
        'durationMs': durationMs,
      },
    );
  }

  /// Emit SDK initialized event
  Future<void> emitSDKInitialized({
    required int durationMs,
    required String environment,
  }) async {
    await trackEvent(
      eventType: RacEventType.sdkInitialized,
      data: {
        'durationMs': durationMs,
        'environment': environment,
      },
    );
  }

  /// Emit model loaded event
  Future<void> emitModelLoaded({
    required String modelId,
    required String modelName,
    required String framework,
    required int durationMs,
  }) async {
    await trackEvent(
      eventType: RacEventType.modelLoaded,
      data: {
        'modelId': modelId,
        'modelName': modelName,
        'framework': framework,
        'durationMs': durationMs,
      },
    );
  }

  /// Emit inference completed event
  Future<void> emitInferenceCompleted({
    required String modelId,
    required String modelName,
    required String modality,
    required int durationMs,
    int? tokensGenerated,
    double? tokensPerSecond,
  }) async {
    await trackEvent(
      eventType: RacEventType.inferenceCompleted,
      data: {
        'modelId': modelId,
        'modelName': modelName,
        'modality': modality,
        'durationMs': durationMs,
        if (tokensGenerated != null) 'tokensGenerated': tokensGenerated,
        if (tokensPerSecond != null) 'tokensPerSecond': tokensPerSecond,
      },
    );
  }

  // ============================================================================
  // Storage Events (matches Swift CppBridge.Events)
  // ============================================================================

  /// Emit storage cache cleared event
  Future<void> emitStorageCacheCleared({required int freedBytes}) async {
    await trackEvent(
      eventType: RacEventType.storageCacheCleared,
      data: {'freedBytes': freedBytes},
    );
  }

  /// Emit storage cache clear failed event
  Future<void> emitStorageCacheClearFailed({required String error}) async {
    await trackEvent(
      eventType: RacEventType.storageCacheClearFailed,
      data: {'error': error},
    );
  }

  /// Emit storage temp cleaned event
  Future<void> emitStorageTempCleaned({required int freedBytes}) async {
    await trackEvent(
      eventType: RacEventType.storageTempCleaned,
      data: {'freedBytes': freedBytes},
    );
  }

  // ============================================================================
  // Voice Agent Events (matches Swift CppBridge.Events)
  // ============================================================================

  /// Emit voice agent turn started event
  Future<void> emitVoiceAgentTurnStarted() async {
    await trackEvent(
      eventType: RacEventType.voiceAgentTurnStarted,
      data: {},
    );
  }

  /// Emit voice agent turn completed event
  Future<void> emitVoiceAgentTurnCompleted({required int durationMs}) async {
    await trackEvent(
      eventType: RacEventType.voiceAgentTurnCompleted,
      data: {'durationMs': durationMs},
    );
  }

  /// Emit voice agent turn failed event
  Future<void> emitVoiceAgentTurnFailed({required String error}) async {
    await trackEvent(
      eventType: RacEventType.voiceAgentTurnFailed,
      data: {'error': error},
    );
  }

  /// Emit voice agent STT state changed event
  Future<void> emitVoiceAgentSttStateChanged({required String state}) async {
    await trackEvent(
      eventType: RacEventType.voiceAgentSttStateChanged,
      data: {'state': state},
    );
  }

  /// Emit voice agent LLM state changed event
  Future<void> emitVoiceAgentLlmStateChanged({required String state}) async {
    await trackEvent(
      eventType: RacEventType.voiceAgentLlmStateChanged,
      data: {'state': state},
    );
  }

  /// Emit voice agent TTS state changed event
  Future<void> emitVoiceAgentTtsStateChanged({required String state}) async {
    await trackEvent(
      eventType: RacEventType.voiceAgentTtsStateChanged,
      data: {'state': state},
    );
  }

  /// Emit voice agent all ready event
  Future<void> emitVoiceAgentAllReady() async {
    await trackEvent(
      eventType: RacEventType.voiceAgentAllReady,
      data: {},
    );
  }

  // ============================================================================
  // Device Events (matches Swift CppBridge.Events)
  // ============================================================================

  /// Emit device registered event
  Future<void> emitDeviceRegistered({required String deviceId}) async {
    await trackEvent(
      eventType: RacEventType.deviceRegistered,
      data: {'deviceId': deviceId},
    );
  }

  /// Emit device registration failed event
  Future<void> emitDeviceRegistrationFailed({required String error}) async {
    await trackEvent(
      eventType: RacEventType.deviceRegistrationFailed,
      data: {'error': error},
    );
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
      case SDKEnvironment.development:
        return 0;
      case SDKEnvironment.staging:
        return 1;
      case SDKEnvironment.production:
        return 2;
    }
  }

  static void _populateEventData(
      Pointer<RacAnalyticsEventDataStruct> data, Map<String, dynamic>? params) {
    // Initialize with zeros/nulls
    data.ref.modelId = nullptr;
    data.ref.modelName = nullptr;
    data.ref.modelSize = 0;
    data.ref.framework = nullptr;
    data.ref.durationMs = 0;
    data.ref.error = nullptr;

    if (params == null) return;

    if (params['modelId'] != null) {
      data.ref.modelId = (params['modelId'] as String).toNativeUtf8();
    }
    if (params['modelName'] != null) {
      data.ref.modelName = (params['modelName'] as String).toNativeUtf8();
    }
    if (params['modelSize'] != null) {
      data.ref.modelSize = params['modelSize'] as int;
    }
    if (params['framework'] != null) {
      data.ref.framework = (params['framework'] as String).toNativeUtf8();
    }
    if (params['durationMs'] != null) {
      data.ref.durationMs = params['durationMs'] as int;
    }
    if (params['error'] != null) {
      data.ref.error = (params['error'] as String).toNativeUtf8();
    }
  }

  static void _freeEventData(Pointer<RacAnalyticsEventDataStruct> data) {
    if (data.ref.modelId != nullptr) calloc.free(data.ref.modelId);
    if (data.ref.modelName != nullptr) calloc.free(data.ref.modelName);
    if (data.ref.framework != nullptr) calloc.free(data.ref.framework);
    if (data.ref.error != nullptr) calloc.free(data.ref.error);
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
    _sendTelemetryHttp(endpointStr, bodyStr, needsAuth);
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
    final url = Uri.parse('$baseURL$endpoint');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (requiresAuth && DartBridgeTelemetry._accessToken != null) {
      headers['Authorization'] = 'Bearer ${DartBridgeTelemetry._accessToken}';
    }

    final response = await http.post(url, headers: headers, body: body);

    // Notify C++ of completion (optional - for retry logic)
    _notifyHttpComplete(
      response.statusCode >= 200 && response.statusCode < 300,
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

/// Analytics event data struct
base class RacAnalyticsEventDataStruct extends Struct {
  external Pointer<Utf8> modelId;
  external Pointer<Utf8> modelName;

  @Int64()
  external int modelSize;

  external Pointer<Utf8> framework;

  @Int64()
  external int durationMs;

  external Pointer<Utf8> error;
}

/// Event type constants (match rac_event_type_t from rac_analytics_events.h)
abstract class RacEventType {
  // SDK lifecycle (1-9)
  static const int sdkInitialized = 1;
  static const int sdkShutdown = 2;

  // Download events (10-19)
  static const int downloadStarted = 10;
  static const int downloadProgress = 11;
  static const int downloadCompleted = 12;
  static const int downloadFailed = 13;
  static const int downloadCancelled = 14;

  // Extraction events (20-29)
  static const int extractionStarted = 20;
  static const int extractionProgress = 21;
  static const int extractionCompleted = 22;
  static const int extractionFailed = 23;

  // Model events (30-39)
  static const int modelLoaded = 30;
  static const int modelUnloaded = 31;
  static const int modelLoadFailed = 32;

  // Inference events (40-49)
  static const int inferenceStarted = 40;
  static const int inferenceCompleted = 41;
  static const int inferenceFailed = 42;
  static const int inferenceCancelled = 43;

  // Voice Agent events (500-519)
  static const int voiceAgentTurnStarted = 500;
  static const int voiceAgentTurnCompleted = 501;
  static const int voiceAgentTurnFailed = 502;
  static const int voiceAgentSttStateChanged = 510;
  static const int voiceAgentLlmStateChanged = 511;
  static const int voiceAgentTtsStateChanged = 512;
  static const int voiceAgentAllReady = 513;

  // Storage events (800-809)
  static const int storageCacheCleared = 800;
  static const int storageCacheClearFailed = 801;
  static const int storageTempCleaned = 802;

  // Device events (900-909)
  static const int deviceRegistered = 900;
  static const int deviceRegistrationFailed = 901;
}
