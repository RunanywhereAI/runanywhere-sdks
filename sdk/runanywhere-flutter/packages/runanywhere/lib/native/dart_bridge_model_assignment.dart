// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

// =============================================================================
// Exception Return Constants
// =============================================================================

const int _exceptionalReturnInt32 = -1;

// =============================================================================
// Model Assignment Bridge
// =============================================================================

/// Model assignment bridge for C++ model assignment operations.
/// Matches Swift's `CppBridge+ModelAssignment.swift`.
///
/// Fetches model assignments from backend API and caches them.
/// Provides filtering by framework and category.
class DartBridgeModelAssignment {
  DartBridgeModelAssignment._();

  static final _logger = SDKLogger('DartBridge.ModelAssignment');
  static final DartBridgeModelAssignment instance =
      DartBridgeModelAssignment._();

  static bool _isRegistered = false;
  static Pointer<RacAssignmentCallbacksStruct>? _callbacksPtr;
  static String? _baseURL;
  static String? _accessToken;
  // ignore: unused_field
  static SDKEnvironment _environment = SDKEnvironment.development;

  // ============================================================================
  // Registration
  // ============================================================================

  /// Register model assignment callbacks with C++
  ///
  /// [autoFetch] Whether to auto-fetch models after registration.
  ///             Should be false for development mode, true for staging/production.
  static Future<void> register({
    required SDKEnvironment environment,
    bool autoFetch = false,
    String? baseURL,
    String? accessToken,
  }) async {
    if (_isRegistered) return;

    _environment = environment;
    _baseURL = baseURL;
    _accessToken = accessToken;

    try {
      final lib = PlatformLoader.loadCommons();

      // Allocate callbacks struct
      _callbacksPtr = calloc<RacAssignmentCallbacksStruct>();
      _callbacksPtr!.ref.httpGet =
          Pointer.fromFunction<RacAssignmentHttpGetCallbackNative>(
              _httpGetCallback, _exceptionalReturnInt32);
      _callbacksPtr!.ref.userData = nullptr;
      // Only auto-fetch in staging/production, not development
      _callbacksPtr!.ref.autoFetch = autoFetch ? 1 : 0;

      // Register with C++
      final setCallbacks = lib.lookupFunction<
              Int32 Function(Pointer<RacAssignmentCallbacksStruct>),
              int Function(Pointer<RacAssignmentCallbacksStruct>)>(
          'rac_model_assignment_set_callbacks');

      final result = setCallbacks(_callbacksPtr!);
      if (result != RacResultCode.success) {
        _logger.warning('Failed to register assignment callbacks',
            metadata: {'code': result});
        calloc.free(_callbacksPtr!);
        _callbacksPtr = null;
        return;
      }

      _isRegistered = true;
      _logger.debug(
          'Model assignment callbacks registered (autoFetch: $autoFetch)');
    } catch (e) {
      _logger.debug('Model assignment registration error: $e');
      _isRegistered = true; // Avoid retry loops
    }
  }

  /// Update access token
  static void setAccessToken(String? token) {
    _accessToken = token;
  }

  // ============================================================================
  // Fetch Operations
  // ============================================================================

  /// Fetch model assignments from backend
  Future<List<ModelInfo>> fetchAssignments({bool forceRefresh = false}) async {
    try {
      final lib = PlatformLoader.loadCommons();
      final fetchFn = lib.lookupFunction<
          Int32 Function(Int32, Pointer<Pointer<Pointer<RacModelInfoStruct>>>,
              Pointer<IntPtr>),
          int Function(int, Pointer<Pointer<Pointer<RacModelInfoStruct>>>,
              Pointer<IntPtr>)>('rac_model_assignment_fetch');

      final outModelsPtr = calloc<Pointer<Pointer<RacModelInfoStruct>>>();
      final outCountPtr = calloc<IntPtr>();

      try {
        final result = fetchFn(forceRefresh ? 1 : 0, outModelsPtr, outCountPtr);
        if (result != RacResultCode.success) {
          _logger
              .warning('Fetch assignments failed', metadata: {'code': result});
          return [];
        }

        final count = outCountPtr.value;
        if (count == 0) return [];

        final models = <ModelInfo>[];
        final modelsArray = outModelsPtr.value;

        for (var i = 0; i < count; i++) {
          final modelPtr = modelsArray[i];
          if (modelPtr != nullptr) {
            models.add(_structToModelInfo(modelPtr));
          }
        }

        // Free the array
        final freeFn = lib.lookupFunction<
            Void Function(Pointer<Pointer<RacModelInfoStruct>>, IntPtr),
            void Function(Pointer<Pointer<RacModelInfoStruct>>,
                int)>('rac_model_info_array_free');
        freeFn(modelsArray, count);

        return models;
      } finally {
        calloc.free(outModelsPtr);
        calloc.free(outCountPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_assignment_fetch error: $e');
      return [];
    }
  }

  /// Get assignments by framework
  Future<List<ModelInfo>> getByFramework(int framework) async {
    try {
      final lib = PlatformLoader.loadCommons();
      final getByFn = lib.lookupFunction<
          Int32 Function(Int32, Pointer<Pointer<Pointer<RacModelInfoStruct>>>,
              Pointer<IntPtr>),
          int Function(int, Pointer<Pointer<Pointer<RacModelInfoStruct>>>,
              Pointer<IntPtr>)>('rac_model_assignment_get_by_framework');

      final outModelsPtr = calloc<Pointer<Pointer<RacModelInfoStruct>>>();
      final outCountPtr = calloc<IntPtr>();

      try {
        final result = getByFn(framework, outModelsPtr, outCountPtr);
        if (result != RacResultCode.success) return [];

        final count = outCountPtr.value;
        if (count == 0) return [];

        final models = <ModelInfo>[];
        final modelsArray = outModelsPtr.value;

        for (var i = 0; i < count; i++) {
          final modelPtr = modelsArray[i];
          if (modelPtr != nullptr) {
            models.add(_structToModelInfo(modelPtr));
          }
        }

        return models;
      } finally {
        calloc.free(outModelsPtr);
        calloc.free(outCountPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_assignment_get_by_framework error: $e');
      return [];
    }
  }

  /// Get assignments by category
  Future<List<ModelInfo>> getByCategory(int category) async {
    try {
      final lib = PlatformLoader.loadCommons();
      final getByFn = lib.lookupFunction<
          Int32 Function(Int32, Pointer<Pointer<Pointer<RacModelInfoStruct>>>,
              Pointer<IntPtr>),
          int Function(int, Pointer<Pointer<Pointer<RacModelInfoStruct>>>,
              Pointer<IntPtr>)>('rac_model_assignment_get_by_category');

      final outModelsPtr = calloc<Pointer<Pointer<RacModelInfoStruct>>>();
      final outCountPtr = calloc<IntPtr>();

      try {
        final result = getByFn(category, outModelsPtr, outCountPtr);
        if (result != RacResultCode.success) return [];

        final count = outCountPtr.value;
        if (count == 0) return [];

        final models = <ModelInfo>[];
        final modelsArray = outModelsPtr.value;

        for (var i = 0; i < count; i++) {
          final modelPtr = modelsArray[i];
          if (modelPtr != nullptr) {
            models.add(_structToModelInfo(modelPtr));
          }
        }

        return models;
      } finally {
        calloc.free(outModelsPtr);
        calloc.free(outCountPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_assignment_get_by_category error: $e');
      return [];
    }
  }

  // ============================================================================
  // Helpers
  // ============================================================================

  ModelInfo _structToModelInfo(Pointer<RacModelInfoStruct> struct) {
    return ModelInfo(
      id: struct.ref.id.toDartString(),
      name: struct.ref.name.toDartString(),
      category: struct.ref.category,
      format: struct.ref.format,
      framework: struct.ref.framework,
      source: struct.ref.source,
      sizeBytes: struct.ref.sizeBytes,
      downloadURL: struct.ref.downloadURL != nullptr
          ? struct.ref.downloadURL.toDartString()
          : null,
      localPath: struct.ref.localPath != nullptr
          ? struct.ref.localPath.toDartString()
          : null,
      version: struct.ref.version != nullptr
          ? struct.ref.version.toDartString()
          : null,
    );
  }
}

// =============================================================================
// HTTP Callback
// =============================================================================

int _httpGetCallback(
  Pointer<Utf8> endpoint,
  int requiresAuth,
  Pointer<RacAssignmentHttpResponseStruct> outResponse,
  Pointer<Void> userData,
) {
  if (endpoint == nullptr || outResponse == nullptr) {
    return RacResultCode.errorInvalidParameter;
  }

  try {
    final endpointStr = endpoint.toDartString();

    // Schedule async HTTP call
    _performHttpGet(endpointStr, requiresAuth != 0, outResponse);

    return RacResultCode.success;
  } catch (e) {
    return RacResultCode.errorNetworkError;
  }
}

/// Perform HTTP GET (simplified)
void _performHttpGet(
  String endpoint,
  bool requiresAuth,
  Pointer<RacAssignmentHttpResponseStruct> outResponse,
) {
  final baseURL =
      DartBridgeModelAssignment._baseURL ?? 'https://api.runanywhere.ai';
  final url = Uri.parse('$baseURL$endpoint');

  final headers = <String, String>{
    'Accept': 'application/json',
  };

  if (requiresAuth && DartBridgeModelAssignment._accessToken != null) {
    headers['Authorization'] =
        'Bearer ${DartBridgeModelAssignment._accessToken}';
  }

  unawaited(Future.microtask(() async {
    try {
      final response = await http.get(url, headers: headers);

      outResponse.ref.result =
          response.statusCode >= 200 && response.statusCode < 300
              ? RacResultCode.success
              : RacResultCode.errorNetworkError;
      outResponse.ref.statusCode = response.statusCode;

      if (response.body.isNotEmpty) {
        final bodyPtr = response.body.toNativeUtf8();
        outResponse.ref.responseBody = bodyPtr;
        outResponse.ref.responseLength = response.body.length;
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

/// HTTP GET callback
typedef RacAssignmentHttpGetCallbackNative = Int32 Function(Pointer<Utf8>,
    Int32, Pointer<RacAssignmentHttpResponseStruct>, Pointer<Void>);

/// Callbacks struct
base class RacAssignmentCallbacksStruct extends Struct {
  external Pointer<NativeFunction<RacAssignmentHttpGetCallbackNative>> httpGet;
  external Pointer<Void> userData;
  @Int32()
  external int autoFetch; // If non-zero, auto-fetch models after registration
}

/// HTTP response struct
base class RacAssignmentHttpResponseStruct extends Struct {
  @Int32()
  external int result;

  @Int32()
  external int statusCode;

  external Pointer<Utf8> responseBody;

  @IntPtr()
  external int responseLength;

  external Pointer<Utf8> errorMessage;
}
