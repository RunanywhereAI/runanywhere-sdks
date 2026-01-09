// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

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

  /// Discovery callbacks pointer
  static Pointer<RacDiscoveryCallbacksStruct>? _discoveryCallbacksPtr;

  // ============================================================================
  // Lifecycle
  // ============================================================================

  /// Initialize the model registry
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final createFn = lib.lookupFunction<
          Int32 Function(Pointer<Pointer<Void>>),
          int Function(Pointer<Pointer<Void>>)>('rac_model_registry_create');

      final handlePtr = calloc<Pointer<Void>>();
      final result = createFn(handlePtr);

      if (result == RacResultCode.success) {
        _registryHandle = handlePtr.value;
        _isInitialized = true;
        _logger.debug('Model registry initialized');
      } else {
        _logger.warning('Failed to create model registry', metadata: {'code': result});
      }

      calloc.free(handlePtr);
    } catch (e) {
      _logger.debug('Model registry init error: $e');
      _isInitialized = true; // Avoid retry loops
    }
  }

  /// Destroy the model registry
  void shutdown() {
    if (_registryHandle != null) {
      try {
        final lib = PlatformLoader.loadCommons();
        final destroyFn = lib.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('rac_model_registry_destroy');
        destroyFn(_registryHandle!);
      } catch (e) {
        _logger.debug('Model registry destroy error: $e');
      }
      _registryHandle = null;
    }
    _isInitialized = false;
  }

  // ============================================================================
  // Model CRUD Operations
  // ============================================================================

  /// Save model info to registry
  Future<bool> saveModel(ModelInfo model) async {
    if (_registryHandle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final saveFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<RacModelInfoStruct>),
          int Function(Pointer<Void>,
              Pointer<RacModelInfoStruct>)>('rac_model_registry_save');

      final modelStruct = _modelInfoToStruct(model);
      try {
        final result = saveFn(_registryHandle!, modelStruct);
        return result == RacResultCode.success;
      } finally {
        _freeModelInfoStruct(modelStruct);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_save error: $e');
      return false;
    }
  }

  /// Get model by ID
  Future<ModelInfo?> getModel(String modelId) async {
    if (_registryHandle == null) return null;

    try {
      final lib = PlatformLoader.loadCommons();
      final getFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<RacModelInfoStruct>>),
          int Function(Pointer<Void>, Pointer<Utf8>,
              Pointer<Pointer<RacModelInfoStruct>>)>('rac_model_registry_get');

      final modelIdPtr = modelId.toNativeUtf8();
      final outModelPtr = calloc<Pointer<RacModelInfoStruct>>();

      try {
        final result = getFn(_registryHandle!, modelIdPtr, outModelPtr);
        if (result == RacResultCode.success && outModelPtr.value != nullptr) {
          final model = _structToModelInfo(outModelPtr.value);

          // Free the model struct
          final freeFn = lib.lookupFunction<Void Function(Pointer<RacModelInfoStruct>),
              void Function(Pointer<RacModelInfoStruct>)>('rac_model_info_free');
          freeFn(outModelPtr.value);

          return model;
        }
        return null;
      } finally {
        calloc.free(modelIdPtr);
        calloc.free(outModelPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_get error: $e');
      return null;
    }
  }

  /// Get all models
  Future<List<ModelInfo>> getAllModels() async {
    if (_registryHandle == null) return [];

    try {
      final lib = PlatformLoader.loadCommons();
      final getAllFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Pointer<Pointer<RacModelInfoStruct>>>,
              Pointer<IntPtr>),
          int Function(Pointer<Void>, Pointer<Pointer<Pointer<RacModelInfoStruct>>>,
              Pointer<IntPtr>)>('rac_model_registry_get_all');

      final outModelsPtr = calloc<Pointer<Pointer<RacModelInfoStruct>>>();
      final outCountPtr = calloc<IntPtr>();

      try {
        final result = getAllFn(_registryHandle!, outModelsPtr, outCountPtr);
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
      _logger.debug('rac_model_registry_get_all error: $e');
      return [];
    }
  }

  /// Get downloaded models only
  Future<List<ModelInfo>> getDownloadedModels() async {
    if (_registryHandle == null) return [];

    try {
      final lib = PlatformLoader.loadCommons();
      final getDownloadedFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Pointer<Pointer<RacModelInfoStruct>>>,
              Pointer<IntPtr>),
          int Function(Pointer<Void>, Pointer<Pointer<Pointer<RacModelInfoStruct>>>,
              Pointer<IntPtr>)>('rac_model_registry_get_downloaded');

      final outModelsPtr = calloc<Pointer<Pointer<RacModelInfoStruct>>>();
      final outCountPtr = calloc<IntPtr>();

      try {
        final result = getDownloadedFn(_registryHandle!, outModelsPtr, outCountPtr);
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
      _logger.debug('rac_model_registry_get_downloaded error: $e');
      return [];
    }
  }

  /// Get models by frameworks
  Future<List<ModelInfo>> getModelsByFrameworks(List<int> frameworks) async {
    if (_registryHandle == null || frameworks.isEmpty) return [];

    try {
      final lib = PlatformLoader.loadCommons();
      final getByFrameworksFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Int32>, IntPtr,
              Pointer<Pointer<Pointer<RacModelInfoStruct>>>, Pointer<IntPtr>),
          int Function(Pointer<Void>, Pointer<Int32>, int,
              Pointer<Pointer<Pointer<RacModelInfoStruct>>>,
              Pointer<IntPtr>)>('rac_model_registry_get_by_frameworks');

      final frameworksPtr = calloc<Int32>(frameworks.length);
      for (var i = 0; i < frameworks.length; i++) {
        frameworksPtr[i] = frameworks[i];
      }

      final outModelsPtr = calloc<Pointer<Pointer<RacModelInfoStruct>>>();
      final outCountPtr = calloc<IntPtr>();

      try {
        final result = getByFrameworksFn(
            _registryHandle!, frameworksPtr, frameworks.length, outModelsPtr, outCountPtr);

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
        calloc.free(frameworksPtr);
        calloc.free(outModelsPtr);
        calloc.free(outCountPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_get_by_frameworks error: $e');
      return [];
    }
  }

  /// Update download status for a model
  Future<bool> updateDownloadStatus(String modelId, String? localPath) async {
    if (_registryHandle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final updateFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_model_registry_update_download_status');

      final modelIdPtr = modelId.toNativeUtf8();
      final localPathPtr = localPath?.toNativeUtf8() ?? nullptr;

      try {
        final result = updateFn(_registryHandle!, modelIdPtr, localPathPtr.cast<Utf8>());
        return result == RacResultCode.success;
      } finally {
        calloc.free(modelIdPtr);
        if (localPathPtr != nullptr) calloc.free(localPathPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_update_download_status error: $e');
      return false;
    }
  }

  /// Remove a model from registry
  Future<bool> removeModel(String modelId) async {
    if (_registryHandle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final removeFn = lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>)>('rac_model_registry_remove');

      final modelIdPtr = modelId.toNativeUtf8();
      try {
        final result = removeFn(_registryHandle!, modelIdPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(modelIdPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_remove error: $e');
      return false;
    }
  }

  /// Update last used timestamp
  Future<bool> updateLastUsed(String modelId) async {
    if (_registryHandle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final updateFn = lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>)>('rac_model_registry_update_last_used');

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
  // Model Discovery
  // ============================================================================

  /// Discover downloaded models by scanning filesystem
  Future<DiscoveryResult> discoverDownloadedModels() async {
    if (_registryHandle == null) {
      return const DiscoveryResult(discoveredModels: [], unregisteredCount: 0);
    }

    try {
      final lib = PlatformLoader.loadCommons();
      final discoverFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<RacDiscoveryCallbacksStruct>,
              Pointer<RacDiscoveryResultStruct>),
          int Function(Pointer<Void>, Pointer<RacDiscoveryCallbacksStruct>,
              Pointer<RacDiscoveryResultStruct>)>('rac_model_registry_discover_downloaded');

      // Set up callbacks
      _discoveryCallbacksPtr = calloc<RacDiscoveryCallbacksStruct>();
      _discoveryCallbacksPtr!.ref.listDirectory =
          Pointer.fromFunction<RacListDirectoryCallbackNative>(
              _listDirectoryCallback, _exceptionalReturnInt32);
      _discoveryCallbacksPtr!.ref.freeEntries =
          Pointer.fromFunction<RacFreeEntriesCallbackNative>(_freeEntriesCallback);
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
        final result = discoverFn(_registryHandle!, _discoveryCallbacksPtr!, resultStruct);

        if (result != RacResultCode.success) {
          return const DiscoveryResult(discoveredModels: [], unregisteredCount: 0);
        }

        // Parse result
        final discoveredModels = <DiscoveredModel>[];
        final discoveredCount = resultStruct.ref.discoveredCount;

        for (var i = 0; i < discoveredCount; i++) {
          final modelPtr = resultStruct.ref.discoveredModels.elementAt(i);
          discoveredModels.add(DiscoveredModel(
            modelId: modelPtr.ref.modelId.toDartString(),
            localPath: modelPtr.ref.localPath.toDartString(),
            framework: modelPtr.ref.framework,
          ));
        }

        final unregisteredCount = resultStruct.ref.unregisteredCount;

        // Free result
        final freeResultFn = lib.lookupFunction<
            Void Function(Pointer<RacDiscoveryResultStruct>),
            void Function(Pointer<RacDiscoveryResultStruct>)>('rac_discovery_result_free');
        freeResultFn(resultStruct);

        return DiscoveryResult(
          discoveredModels: discoveredModels,
          unregisteredCount: unregisteredCount,
        );
      } finally {
        calloc.free(_discoveryCallbacksPtr!);
        _discoveryCallbacksPtr = null;
        calloc.free(resultStruct);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_discover_downloaded error: $e');
      return const DiscoveryResult(discoveredModels: [], unregisteredCount: 0);
    }
  }

  // ============================================================================
  // Struct Conversion Helpers
  // ============================================================================

  Pointer<RacModelInfoStruct> _modelInfoToStruct(ModelInfo model) {
    final struct = calloc<RacModelInfoStruct>();

    struct.ref.id = model.id.toNativeUtf8();
    struct.ref.name = model.name.toNativeUtf8();
    struct.ref.category = model.category;
    struct.ref.format = model.format;
    struct.ref.framework = model.framework;
    struct.ref.source = model.source;
    struct.ref.sizeBytes = model.sizeBytes;
    struct.ref.downloadURL = model.downloadURL?.toNativeUtf8() ?? nullptr;
    struct.ref.localPath = model.localPath?.toNativeUtf8() ?? nullptr;
    struct.ref.version = model.version?.toNativeUtf8() ?? nullptr;

    return struct;
  }

  void _freeModelInfoStruct(Pointer<RacModelInfoStruct> struct) {
    if (struct.ref.id != nullptr) calloc.free(struct.ref.id);
    if (struct.ref.name != nullptr) calloc.free(struct.ref.name);
    if (struct.ref.downloadURL != nullptr) calloc.free(struct.ref.downloadURL);
    if (struct.ref.localPath != nullptr) calloc.free(struct.ref.localPath);
    if (struct.ref.version != nullptr) calloc.free(struct.ref.version);
    calloc.free(struct);
  }

  ModelInfo _structToModelInfo(Pointer<RacModelInfoStruct> struct) {
    return ModelInfo(
      id: struct.ref.id.toDartString(),
      name: struct.ref.name.toDartString(),
      category: struct.ref.category,
      format: struct.ref.format,
      framework: struct.ref.framework,
      source: struct.ref.source,
      sizeBytes: struct.ref.sizeBytes,
      downloadURL: struct.ref.downloadURL != nullptr ? struct.ref.downloadURL.toDartString() : null,
      localPath: struct.ref.localPath != nullptr ? struct.ref.localPath.toDartString() : null,
      version: struct.ref.version != nullptr ? struct.ref.version.toDartString() : null,
    );
  }
}

// =============================================================================
// Discovery Callbacks
// =============================================================================

int _listDirectoryCallback(
    Pointer<Utf8> path, Pointer<Pointer<Pointer<Utf8>>> outEntries,
    Pointer<IntPtr> outCount, Pointer<Void> userData) {
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
    if (entries[i] != nullptr) calloc.free(entries[i]);
  }
  calloc.free(entries);
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
    switch (framework) {
      case 0: // LlamaCpp
        return (ext == 'gguf' || ext == 'ggml') ? RAC_TRUE : RAC_FALSE;
      case 1: // ONNX
        return ext == 'onnx' ? RAC_TRUE : RAC_FALSE;
      default:
        return RAC_FALSE;
    }
  } catch (e) {
    return RAC_FALSE;
  }
}

// =============================================================================
// FFI Structs
// =============================================================================

/// Model info struct (simplified)
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

  external Pointer<Utf8> downloadURL;
  external Pointer<Utf8> localPath;
  external Pointer<Utf8> version;
}

/// Discovery callbacks struct
typedef RacListDirectoryCallbackNative = Int32 Function(
    Pointer<Utf8>, Pointer<Pointer<Pointer<Utf8>>>, Pointer<IntPtr>, Pointer<Void>);
typedef RacFreeEntriesCallbackNative = Void Function(
    Pointer<Pointer<Utf8>>, IntPtr, Pointer<Void>);
typedef RacIsDirectoryCallbackNative = Int32 Function(Pointer<Utf8>, Pointer<Void>);
typedef RacPathExistsCallbackNative = Int32 Function(Pointer<Utf8>, Pointer<Void>);
typedef RacIsModelFileCallbackNative = Int32 Function(Pointer<Utf8>, Int32, Pointer<Void>);

base class RacDiscoveryCallbacksStruct extends Struct {
  external Pointer<NativeFunction<RacListDirectoryCallbackNative>> listDirectory;
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

// =============================================================================
// Data Classes
// =============================================================================

/// Model info data class
class ModelInfo {
  final String id;
  final String name;
  final int category;
  final int format;
  final int framework;
  final int source;
  final int sizeBytes;
  final String? downloadURL;
  final String? localPath;
  final String? version;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.format,
    required this.framework,
    required this.source,
    required this.sizeBytes,
    this.downloadURL,
    this.localPath,
    this.version,
  });

  bool get isDownloaded => localPath != null && localPath!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'format': format,
        'framework': framework,
        'source': source,
        'sizeBytes': sizeBytes,
        if (downloadURL != null) 'downloadURL': downloadURL,
        if (localPath != null) 'localPath': localPath,
        if (version != null) 'version': version,
      };
}

/// Discovered model
class DiscoveredModel {
  final String modelId;
  final String localPath;
  final int framework;

  const DiscoveredModel({
    required this.modelId,
    required this.localPath,
    required this.framework,
  });
}

/// Discovery result
class DiscoveryResult {
  final List<DiscoveredModel> discoveredModels;
  final int unregisteredCount;

  const DiscoveryResult({
    required this.discoveredModels,
    required this.unregisteredCount,
  });
}
