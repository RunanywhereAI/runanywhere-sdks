// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/native/dart_bridge_model_format.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

// =============================================================================
// Exception Return Constants
// =============================================================================

const int _exceptionalReturnInt32 = -1;
const int _exceptionalReturnFalse = 0;

// =============================================================================
// Model Registry Bridge
// =============================================================================

/// Model registry bridge for C++ model registry operations.
/// Matches Swift's `CppBridge+ModelRegistry.swift`.
///
/// Provides:
/// - Model metadata storage (save, get, remove)
/// - Model queries (by framework, downloaded only)
/// - Model discovery (scan filesystem for models)
class DartBridgeModelRegistry {
  DartBridgeModelRegistry._();

  static final _logger = SDKLogger('DartBridge.ModelRegistry');
  static final DartBridgeModelRegistry instance = DartBridgeModelRegistry._();

  /// Registry handle
  static Pointer<Void>? _registryHandle;
  static bool _isInitialized = false;

  /// Native global registry handle for other proto-byte bridge surfaces.
  Pointer<Void>? get nativeHandle => _registryHandle;

  /// Discovery callbacks pointer
  static Pointer<RacDiscoveryCallbacksStruct>? _discoveryCallbacksPtr;

  // ============================================================================
  // Lifecycle
  // ============================================================================

  /// Initialize the model registry
  ///
  /// IMPORTANT: Uses the GLOBAL C++ model registry via rac_get_model_registry(),
  /// NOT rac_model_registry_create() which would create a separate instance.
  /// This matches Swift's CppBridge+ModelRegistry.swift behavior.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final lib = PlatformLoader.loadCommons();

      // Use the GLOBAL C++ model registry - same as Swift does
      // This is critical: C++ code (rac_get_model, rac_llm_component_load_model)
      // looks up models in the GLOBAL registry, not a separate instance
      final getGlobalRegistryFn = lib.lookupFunction<Pointer<Void> Function(),
          Pointer<Void> Function()>('rac_get_model_registry');

      final globalRegistry = getGlobalRegistryFn();

      if (globalRegistry != nullptr) {
        _registryHandle = globalRegistry;
        _isInitialized = true;
        _logger.debug('Using global C++ model registry');
      } else {
        _logger.error('Failed to get global model registry');
      }
    } catch (e) {
      _logger.debug('Model registry init error: $e');
      _isInitialized = true; // Avoid retry loops
    }
  }

  /// Shutdown the model registry bridge
  ///
  /// NOTE: Does NOT destroy the global registry since it's a C++ singleton.
  /// We just release our reference to it.
  void shutdown() {
    // Don't destroy the global registry - it's managed by C++
    // The handle is just a reference to the singleton
    _registryHandle = null;
    _isInitialized = false;
    _logger.debug('Model registry bridge shutdown (global registry preserved)');
  }

  // ============================================================================
  // Model CRUD Operations
  // ============================================================================

  /// Save a generated proto ModelInfo to the C++ registry.
  Future<bool> saveProtoModel(model_pb.ModelInfo model) async {
    if (_registryHandle == null) {
      _logger.debug('Registry not initialized, cannot save proto model');
      return false;
    }

    final protoResult = _writeProtoModel(
      model,
      RacNative.bindings.rac_model_registry_register_proto,
      'rac_model_registry_register_proto',
    );
    if (protoResult != null) {
      return protoResult;
    }

    _logger.debug('rac_model_registry_register_proto unavailable');
    return false;
  }

  /// Update an existing generated proto ModelInfo in the C++ registry.
  Future<bool> updateProtoModel(model_pb.ModelInfo model) async {
    if (_registryHandle == null) {
      _logger.debug('Registry not initialized, cannot update proto model');
      return false;
    }

    final protoResult = _writeProtoModel(
      model,
      RacNative.bindings.rac_model_registry_update_proto,
      'rac_model_registry_update_proto',
    );
    if (protoResult != null) {
      return protoResult;
    }

    return saveProtoModel(model);
  }

  /// Get all models from C++ registry as generated ModelInfo protos.
  Future<List<model_pb.ModelInfo>> getAllProtoModels() async {
    final protoModels = _listProtoModels();
    return protoModels ?? const [];
  }

  /// Get a single model from C++ registry as a generated ModelInfo proto.
  Future<model_pb.ModelInfo?> getProtoModel(String modelId) async {
    return _getProtoModel(modelId);
  }

  /// Query the C++ registry with a generated ModelQuery proto.
  Future<List<model_pb.ModelInfo>> queryProtoModels(
    model_pb.ModelQuery query,
  ) async {
    final protoModels = _queryProtoModels(query);
    if (protoModels != null) return protoModels;

    _logger.debug('rac_model_registry_query_proto unavailable');
    return const [];
  }

  /// List downloaded models via the registry proto-byte ABI.
  Future<List<model_pb.ModelInfo>> listDownloadedProtoModels() async {
    final protoModels = _listDownloadedProtoModels();
    if (protoModels != null) return protoModels;

    _logger.debug('rac_model_registry_list_downloaded_proto unavailable');
    return const [];
  }

  bool? _writeProtoModel(
    model_pb.ModelInfo model,
    int Function(Pointer<Void>, Pointer<Uint8>, int)? fn,
    String symbol,
  ) {
    if (_registryHandle == null || fn == null) return null;

    final bytes = model.writeToBuffer();
    final bytesPtr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      if (bytes.isNotEmpty) {
        bytesPtr.asTypedList(bytes.length).setAll(0, bytes);
      }

      final result = fn(_registryHandle!, bytesPtr, bytes.length);
      if (result == RacResultCode.errorFeatureNotAvailable) {
        return null;
      }
      if (result != RacResultCode.success) {
        _logger.debug('$symbol failed for ${model.id}: result=$result');
      }
      return result == RacResultCode.success;
    } catch (e) {
      _logger.debug('$symbol error: $e');
      return null;
    } finally {
      calloc.free(bytesPtr);
    }
  }

  model_pb.ModelInfo? _getProtoModel(String modelId) {
    if (_registryHandle == null) return null;

    final bindings = RacNative.bindings;
    final getFn = bindings.rac_model_registry_get_proto;
    final freeFn = bindings.rac_model_registry_proto_free;
    if (getFn == null || freeFn == null) return null;

    final modelIdPtr = modelId.toNativeUtf8();
    final outBytesPtr = calloc<Pointer<Uint8>>();
    final outSizePtr = calloc<Size>();

    try {
      final result =
          getFn(_registryHandle!, modelIdPtr, outBytesPtr, outSizePtr);
      if (result != RacResultCode.success || outBytesPtr.value == nullptr) {
        if (result != RacResultCode.errorNotFound) {
          _logger.debug(
              'rac_model_registry_get_proto failed for $modelId: result=$result');
        }
        return null;
      }

      final bytes = outBytesPtr.value
          .asTypedList(outSizePtr.value)
          .toList(growable: false);
      return DartBridgeModelFormat.shared
          .applyInferredArtifact(model_pb.ModelInfo.fromBuffer(bytes));
    } catch (e) {
      _logger.debug('rac_model_registry_get_proto error: $e');
      return null;
    } finally {
      if (outBytesPtr.value != nullptr) {
        freeFn(outBytesPtr.value);
      }
      calloc.free(modelIdPtr);
      calloc.free(outBytesPtr);
      calloc.free(outSizePtr);
    }
  }

  List<model_pb.ModelInfo>? _listProtoModels() {
    if (_registryHandle == null) return null;

    final bindings = RacNative.bindings;
    final listFn = bindings.rac_model_registry_list_proto;
    final freeFn = bindings.rac_model_registry_proto_free;
    if (listFn == null || freeFn == null) return null;

    final outBytesPtr = calloc<Pointer<Uint8>>();
    final outSizePtr = calloc<Size>();

    try {
      final result = listFn(_registryHandle!, outBytesPtr, outSizePtr);
      if (result != RacResultCode.success || outBytesPtr.value == nullptr) {
        _logger.debug('rac_model_registry_list_proto failed: result=$result');
        return null;
      }

      final bytes = outBytesPtr.value
          .asTypedList(outSizePtr.value)
          .toList(growable: false);
      final list = model_pb.ModelInfoList.fromBuffer(bytes);
      return list.models
          .map(DartBridgeModelFormat.shared.applyInferredArtifact)
          .toList(growable: false);
    } catch (e) {
      _logger.debug('rac_model_registry_list_proto error: $e');
      return null;
    } finally {
      if (outBytesPtr.value != nullptr) {
        freeFn(outBytesPtr.value);
      }
      calloc.free(outBytesPtr);
      calloc.free(outSizePtr);
    }
  }

  List<model_pb.ModelInfo>? _queryProtoModels(model_pb.ModelQuery query) {
    if (_registryHandle == null) return null;

    final bindings = RacNative.bindings;
    final queryFn = bindings.rac_model_registry_query_proto;
    final freeFn = bindings.rac_model_registry_proto_free;
    if (queryFn == null || freeFn == null) return null;

    final bytes = query.writeToBuffer();
    final bytesPtr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final outBytesPtr = calloc<Pointer<Uint8>>();
    final outSizePtr = calloc<Size>();

    try {
      if (bytes.isNotEmpty) {
        bytesPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      final result = queryFn(
        _registryHandle!,
        bytesPtr,
        bytes.length,
        outBytesPtr,
        outSizePtr,
      );
      if (result != RacResultCode.success || outBytesPtr.value == nullptr) {
        _logger.debug('rac_model_registry_query_proto failed: result=$result');
        return null;
      }

      final resultBytes = outBytesPtr.value
          .asTypedList(outSizePtr.value)
          .toList(growable: false);
      final list = model_pb.ModelInfoList.fromBuffer(resultBytes);
      return list.models
          .map(DartBridgeModelFormat.shared.applyInferredArtifact)
          .toList(growable: false);
    } catch (e) {
      _logger.debug('rac_model_registry_query_proto error: $e');
      return null;
    } finally {
      if (outBytesPtr.value != nullptr) {
        freeFn(outBytesPtr.value);
      }
      calloc.free(bytesPtr);
      calloc.free(outBytesPtr);
      calloc.free(outSizePtr);
    }
  }

  List<model_pb.ModelInfo>? _listDownloadedProtoModels() {
    if (_registryHandle == null) return null;

    final bindings = RacNative.bindings;
    final listFn = bindings.rac_model_registry_list_downloaded_proto;
    final freeFn = bindings.rac_model_registry_proto_free;
    if (listFn == null || freeFn == null) return null;

    final outBytesPtr = calloc<Pointer<Uint8>>();
    final outSizePtr = calloc<Size>();

    try {
      final result = listFn(_registryHandle!, outBytesPtr, outSizePtr);
      if (result != RacResultCode.success || outBytesPtr.value == nullptr) {
        _logger.debug(
            'rac_model_registry_list_downloaded_proto failed: result=$result');
        return null;
      }

      final bytes = outBytesPtr.value
          .asTypedList(outSizePtr.value)
          .toList(growable: false);
      final list = model_pb.ModelInfoList.fromBuffer(bytes);
      return list.models
          .map(DartBridgeModelFormat.shared.applyInferredArtifact)
          .toList(growable: false);
    } catch (e) {
      _logger.debug('rac_model_registry_list_downloaded_proto error: $e');
      return null;
    } finally {
      if (outBytesPtr.value != nullptr) {
        freeFn(outBytesPtr.value);
      }
      calloc.free(outBytesPtr);
      calloc.free(outSizePtr);
    }
  }

  /// Update download status for a model
  Future<bool> updateDownloadStatus(String modelId, String? localPath) async {
    if (_registryHandle == null) {
      _logger.error('updateDownloadStatus: registry handle is null!');
      return false;
    }

    final bindings = RacNative.bindings;
    if (bindings.rac_model_registry_get_proto != null &&
        bindings.rac_model_registry_update_proto != null &&
        bindings.rac_model_registry_proto_free != null) {
      final model = _getProtoModel(modelId);
      if (model != null) {
        final updated = model.deepCopy();
        if (localPath == null || localPath.isEmpty) {
          updated.clearLocalPath();
        } else {
          updated.localPath = localPath;
        }

        final protoResult = _writeProtoModel(
          updated,
          bindings.rac_model_registry_update_proto,
          'rac_model_registry_update_proto',
        );
        if (protoResult != null) {
          return protoResult;
        }
      }
    }

    _logger.debug('registry download-status proto update unavailable');
    return false;
  }

  /// Remove a model from registry
  Future<bool> removeModel(String modelId) async {
    if (_registryHandle == null) return false;

    final removeProtoFn = RacNative.bindings.rac_model_registry_remove_proto;
    if (removeProtoFn != null) {
      final modelIdPtr = modelId.toNativeUtf8();
      try {
        final result = removeProtoFn(_registryHandle!, modelIdPtr);
        if (result == RacResultCode.errorFeatureNotAvailable) {
          // Fall back to the legacy struct/string remove ABI below.
        } else {
          if (result != RacResultCode.success) {
            _logger.debug(
                'rac_model_registry_remove_proto failed for $modelId: result=$result');
          }
          return result == RacResultCode.success;
        }
      } catch (e) {
        _logger.debug('rac_model_registry_remove_proto error: $e');
      } finally {
        calloc.free(modelIdPtr);
      }
    }

    _logger.debug('rac_model_registry_remove_proto unavailable');
    return false;
  }

  /// Update last used timestamp
  Future<bool> updateLastUsed(String modelId) async {
    if (_registryHandle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final updateFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>),
          int Function(Pointer<Void>,
              Pointer<Utf8>)>('rac_model_registry_update_last_used');

      final modelIdPtr = modelId.toNativeUtf8();
      try {
        final result = updateFn(_registryHandle!, modelIdPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(modelIdPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_update_last_used error: $e');
      return false;
    }
  }

  // ============================================================================
  // Refresh (T4.9) — bridges rac_model_registry_refresh
  // ============================================================================

  /// Refresh the model registry via commons C ABI.
  ///
  /// Note: we deliberately pass `discoveryCallbacks = nullptr`. Local rescan
  /// / orphan pruning from the native layer requires the Dart-side discovery
  /// callbacks struct (see [discoverDownloadedModels]) which is not safe to
  /// hand off into an opaque pointer shared across C-ABI boundaries here.
  /// Callers that want those steps should use [discoverDownloadedModels]
  /// directly — the Models capability does exactly that.
  Future<bool> refresh({
    required bool includeRemoteCatalog,
    required bool pruneOrphans,
  }) async {
    if (_registryHandle == null) return false;
    final optsPtr = calloc<RacModelRegistryRefreshOpts>();
    try {
      optsPtr.ref
        ..includeRemoteCatalog = includeRemoteCatalog ? 1 : 0
        ..rescanLocal = 0
        ..pruneOrphans = pruneOrphans ? 1 : 0
        ..discoveryCallbacks = nullptr;
      final rc = RacNative.bindings
          .rac_model_registry_refresh(_registryHandle!, optsPtr.ref);
      if (rc != 0) {
        _logger.debug('rac_model_registry_refresh rc=$rc');
        return false;
      }
      return true;
    } catch (e) {
      _logger.debug('rac_model_registry_refresh error: $e');
      return false;
    } finally {
      calloc.free(optsPtr);
    }
  }

  // ============================================================================
  // Model Discovery
  // ============================================================================

  /// Discover downloaded models by scanning filesystem
  Future<model_pb.ModelDiscoveryResult> discoverDownloadedModels() async {
    if (_registryHandle == null) {
      return model_pb.ModelDiscoveryResult(success: false);
    }

    try {
      final lib = PlatformLoader.loadCommons();
      final discoverFn =
          lib.lookupFunction<
                  Int32 Function(
                      Pointer<Void>,
                      Pointer<RacDiscoveryCallbacksStruct>,
                      Pointer<RacDiscoveryResultStruct>),
                  int Function(
                      Pointer<Void>,
                      Pointer<RacDiscoveryCallbacksStruct>,
                      Pointer<RacDiscoveryResultStruct>)>(
              'rac_model_registry_discover_downloaded');

      // Set up callbacks
      _discoveryCallbacksPtr = calloc<RacDiscoveryCallbacksStruct>();
      _discoveryCallbacksPtr!.ref.listDirectory =
          Pointer.fromFunction<RacListDirectoryCallbackNative>(
              _listDirectoryCallback, _exceptionalReturnInt32);
      _discoveryCallbacksPtr!.ref.freeEntries =
          Pointer.fromFunction<RacFreeEntriesCallbackNative>(
              _freeEntriesCallback);
      _discoveryCallbacksPtr!.ref.isDirectory =
          Pointer.fromFunction<RacIsDirectoryCallbackNative>(
              _isDirectoryCallback, _exceptionalReturnFalse);
      _discoveryCallbacksPtr!.ref.pathExists =
          Pointer.fromFunction<RacPathExistsCallbackNative>(
              _pathExistsCallback, _exceptionalReturnFalse);
      _discoveryCallbacksPtr!.ref.isModelFile =
          Pointer.fromFunction<RacIsModelFileCallbackNative>(
              _isModelFileCallback, _exceptionalReturnFalse);
      _discoveryCallbacksPtr!.ref.userData = nullptr;

      final resultStruct = calloc<RacDiscoveryResultStruct>();

      try {
        final result =
            discoverFn(_registryHandle!, _discoveryCallbacksPtr!, resultStruct);

        if (result != RacResultCode.success) {
          return model_pb.ModelDiscoveryResult(
            success: false,
            errorMessage: RacResultCode.getMessage(result),
          );
        }

        // Parse result
        final discoveredModels = <model_pb.DiscoveredModel>[];
        final discoveredCount = resultStruct.ref.discoveredCount;

        for (var i = 0; i < discoveredCount; i++) {
          final modelPtr = resultStruct.ref.discoveredModels + i;
          discoveredModels.add(model_pb.DiscoveredModel(
            modelId: modelPtr.ref.modelId.toDartString(),
            localPath: modelPtr.ref.localPath.toDartString(),
          ));
        }

        final unregisteredCount = resultStruct.ref.unregisteredCount;

        // Free result
        final freeResultFn = lib.lookupFunction<
                Void Function(Pointer<RacDiscoveryResultStruct>),
                void Function(Pointer<RacDiscoveryResultStruct>)>(
            'rac_discovery_result_free');
        freeResultFn(resultStruct);

        return model_pb.ModelDiscoveryResult(
          success: true,
          discoveredModels: discoveredModels,
          scannedCount: discoveredCount,
          purgedCount: unregisteredCount,
        );
      } finally {
        calloc.free(_discoveryCallbacksPtr!);
        _discoveryCallbacksPtr = null;
        calloc.free(resultStruct);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_discover_downloaded error: $e');
      return model_pb.ModelDiscoveryResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }
}

// =============================================================================
// Discovery Callbacks
// =============================================================================

int _listDirectoryCallback(
    Pointer<Utf8> path,
    Pointer<Pointer<Pointer<Utf8>>> outEntries,
    Pointer<IntPtr> outCount,
    Pointer<Void> userData) {
  try {
    final pathStr = path.toDartString();
    final dir = Directory(pathStr);

    if (!dir.existsSync()) {
      outCount.value = 0;
      return RacResultCode.success;
    }

    final entries = dir.listSync().map((e) => e.path.split('/').last).toList();
    outCount.value = entries.length;

    if (entries.isEmpty) return RacResultCode.success;

    // Allocate array of string pointers
    final entriesPtr = calloc<Pointer<Utf8>>(entries.length);
    for (var i = 0; i < entries.length; i++) {
      entriesPtr[i] = entries[i].toNativeUtf8();
    }
    outEntries.value = entriesPtr;

    return RacResultCode.success;
  } catch (e) {
    return RacResultCode.errorFileReadFailed;
  }
}

void _freeEntriesCallback(
    Pointer<Pointer<Utf8>> entries, int count, Pointer<Void> userData) {
  for (var i = 0; i < count; i++) {
    if (entries[i] != nullptr) malloc.free(entries[i]);
  }
  malloc.free(entries);
}

int _isDirectoryCallback(Pointer<Utf8> path, Pointer<Void> userData) {
  try {
    return Directory(path.toDartString()).existsSync() ? RAC_TRUE : RAC_FALSE;
  } catch (e) {
    return RAC_FALSE;
  }
}

int _pathExistsCallback(Pointer<Utf8> path, Pointer<Void> userData) {
  try {
    final pathStr = path.toDartString();
    return (File(pathStr).existsSync() || Directory(pathStr).existsSync())
        ? RAC_TRUE
        : RAC_FALSE;
  } catch (e) {
    return RAC_FALSE;
  }
}

int _isModelFileCallback(
    Pointer<Utf8> path, int framework, Pointer<Void> userData) {
  try {
    final pathStr = path.toDartString();
    final ext = pathStr.split('.').last.toLowerCase();

    // Check extension based on framework
    // RAC_FRAMEWORK values: 0=ONNX, 1=LlamaCpp (matches Swift)
    switch (framework) {
      case 0: // RAC_FRAMEWORK_ONNX
        return (ext == 'onnx' || ext == 'ort') ? RAC_TRUE : RAC_FALSE;
      case 1: // RAC_FRAMEWORK_LLAMACPP
        return (ext == 'gguf' || ext == 'bin') ? RAC_TRUE : RAC_FALSE;
      case 2: // RAC_FRAMEWORK_FOUNDATION_MODELS
      case 3: // RAC_FRAMEWORK_SYSTEM_TTS
        return RAC_TRUE; // Built-in models don't need file check
      default:
        // Generic check for any model file
        return (ext == 'gguf' || ext == 'onnx' || ext == 'bin' || ext == 'ort')
            ? RAC_TRUE
            : RAC_FALSE;
    }
  } catch (e) {
    return RAC_FALSE;
  }
}

// =============================================================================
// FFI Structs
// =============================================================================

/// Artifact info struct matching C++ rac_model_artifact_info_t
/// Used as nested struct in RacModelInfoCStruct
base class RacArtifactInfoStruct extends Struct {
  @Int32()
  external int kind; // rac_artifact_type_kind_t

  @Int32()
  external int archiveType; // rac_archive_type_t

  @Int32()
  external int archiveStructure; // rac_archive_structure_t

  external Pointer<Void> expectedFiles; // rac_expected_model_files_t*

  external Pointer<Void> fileDescriptors; // rac_model_file_descriptor_t*

  @IntPtr()
  external int fileDescriptorCount; // size_t

  external Pointer<Utf8> strategyId; // const char*
}

/// Model info struct matching actual C++ rac_model_info_t layout.
///
/// IMPORTANT: Field order MUST match the C struct exactly!
/// This struct is allocated by rac_model_info_alloc() in C++ which uses
/// calloc to zero all fields, making unset fields safe.
base class RacModelInfoCStruct extends Struct {
  // char* id
  external Pointer<Utf8> id;

  // char* name
  external Pointer<Utf8> name;

  // rac_model_category_t (int32_t)
  @Int32()
  external int category;

  // rac_model_format_t (int32_t)
  @Int32()
  external int format;

  // rac_inference_framework_t (int32_t)
  @Int32()
  external int framework;

  // char* download_url
  external Pointer<Utf8> downloadUrl;

  // char* local_path
  external Pointer<Utf8> localPath;

  // rac_model_artifact_info_t artifact_info (nested struct, ~40 bytes)
  external RacArtifactInfoStruct artifactInfo;

  // int64_t download_size
  @Int64()
  external int downloadSize;

  // int64_t memory_required
  @Int64()
  external int memoryRequired;

  // int32_t context_length
  @Int32()
  external int contextLength;

  // rac_bool_t supports_thinking (int32_t)
  @Int32()
  external int supportsThinking;

  // rac_bool_t supports_lora (int32_t)
  @Int32()
  external int supportsLora;

  // char** tags
  external Pointer<Pointer<Utf8>> tags;

  // size_t tag_count
  @IntPtr()
  external int tagCount;

  // char* description
  external Pointer<Utf8> description;

  // rac_model_source_t (int32_t)
  @Int32()
  external int source;

  // int64_t created_at
  @Int64()
  external int createdAt;

  // int64_t updated_at
  @Int64()
  external int updatedAt;

  // int64_t last_used
  @Int64()
  external int lastUsed;

  // int32_t usage_count
  @Int32()
  external int usageCount;
}

/// Model info struct (simplified, for internal Dart use only)
/// NOT for direct FFI - use RacModelInfoCStruct with rac_model_info_alloc
base class RacModelInfoStruct extends Struct {
  external Pointer<Utf8> id;
  external Pointer<Utf8> name;

  @Int32()
  external int category;

  @Int32()
  external int format;

  @Int32()
  external int framework;

  @Int32()
  external int source;

  @Int64()
  external int sizeBytes;

  @Int32()
  external int contextLength;

  external Pointer<Utf8> downloadURL;
  external Pointer<Utf8> localPath;
  external Pointer<Utf8> version;
}

/// Discovery callbacks struct
typedef RacListDirectoryCallbackNative = Int32 Function(Pointer<Utf8>,
    Pointer<Pointer<Pointer<Utf8>>>, Pointer<IntPtr>, Pointer<Void>);
typedef RacFreeEntriesCallbackNative = Void Function(
    Pointer<Pointer<Utf8>>, IntPtr, Pointer<Void>);
typedef RacIsDirectoryCallbackNative = Int32 Function(
    Pointer<Utf8>, Pointer<Void>);
typedef RacPathExistsCallbackNative = Int32 Function(
    Pointer<Utf8>, Pointer<Void>);
typedef RacIsModelFileCallbackNative = Int32 Function(
    Pointer<Utf8>, Int32, Pointer<Void>);

base class RacDiscoveryCallbacksStruct extends Struct {
  external Pointer<NativeFunction<RacListDirectoryCallbackNative>>
      listDirectory;
  external Pointer<NativeFunction<RacFreeEntriesCallbackNative>> freeEntries;
  external Pointer<NativeFunction<RacIsDirectoryCallbackNative>> isDirectory;
  external Pointer<NativeFunction<RacPathExistsCallbackNative>> pathExists;
  external Pointer<NativeFunction<RacIsModelFileCallbackNative>> isModelFile;
  external Pointer<Void> userData;
}

/// Discovered model struct
base class RacDiscoveredModelStruct extends Struct {
  external Pointer<Utf8> modelId;
  external Pointer<Utf8> localPath;

  @Int32()
  external int framework;
}

/// Discovery result struct
base class RacDiscoveryResultStruct extends Struct {
  @IntPtr()
  external int discoveredCount;

  external Pointer<RacDiscoveredModelStruct> discoveredModels;

  @IntPtr()
  external int unregisteredCount;
}
