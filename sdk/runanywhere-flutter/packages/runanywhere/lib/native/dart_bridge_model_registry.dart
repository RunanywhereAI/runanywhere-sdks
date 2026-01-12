// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/core/types/model_types.dart' as public_types;
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
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

  /// Save model info to registry using C allocation for safety.
  ///
  /// Uses rac_model_info_alloc() to allocate a properly sized struct in C++,
  /// then fills in the fields using strdup for strings (allocated by C).
  /// This avoids struct layout mismatches and memory allocation issues.
  ///
  /// Pattern matches Kotlin JNI: allocate in C++, fill fields, call save.
  Future<bool> saveModel(ModelInfo model) async {
    if (_registryHandle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();

      // Allocate struct in C++ with correct size (zeroed by calloc)
      final allocFn = lib.lookupFunction<
          Pointer<RacModelInfoCStruct> Function(),
          Pointer<RacModelInfoCStruct> Function()>('rac_model_info_alloc');

      // Use C's free function for the struct (rac_model_info_free frees strings
      // but we're using rac_strdup which uses C's malloc)
      final freeFn = lib.lookupFunction<
          Void Function(Pointer<RacModelInfoCStruct>),
          void Function(Pointer<RacModelInfoCStruct>)>('rac_model_info_free');

      // Use C's strdup to allocate strings - this matches what Kotlin JNI does
      final strdupFn = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('rac_strdup');

      final saveFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<RacModelInfoCStruct>),
          int Function(Pointer<Void>,
              Pointer<RacModelInfoCStruct>)>('rac_model_registry_save');

      final modelPtr = allocFn();
      if (modelPtr == nullptr) {
        _logger.debug('rac_model_info_alloc returned null');
        return false;
      }

      // Temporary Dart strings for conversion
      final idDart = model.id.toNativeUtf8();
      final nameDart = model.name.toNativeUtf8();
      final urlDart = model.downloadURL?.toNativeUtf8();
      final pathDart = model.localPath?.toNativeUtf8();

      try {
        // Use strdup to allocate strings in C heap (matches Kotlin JNI pattern)
        // This is critical - C's rac_model_info_free will call free() on these
        modelPtr.ref.id = strdupFn(idDart);
        modelPtr.ref.name = strdupFn(nameDart);
        modelPtr.ref.category = model.category;
        modelPtr.ref.format = model.format;
        modelPtr.ref.framework = model.framework;
        modelPtr.ref.downloadUrl =
            urlDart != null ? strdupFn(urlDart) : nullptr;
        modelPtr.ref.localPath =
            pathDart != null ? strdupFn(pathDart) : nullptr;
        modelPtr.ref.downloadSize = model.sizeBytes;
        modelPtr.ref.source = model.source;

        final result = saveFn(_registryHandle!, modelPtr);
        if (result != RacResultCode.success) {
          _logger.error('Failed to save model ${model.id}: result=$result');
        }
        return result == RacResultCode.success;
      } finally {
        // Free Dart-allocated temporary strings
        calloc.free(idDart);
        calloc.free(nameDart);
        if (urlDart != null) calloc.free(urlDart);
        if (pathDart != null) calloc.free(pathDart);

        // Free C-allocated struct and its strings
        freeFn(modelPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_save error: $e');
      return false;
    }
  }

  /// Save a public ModelInfo to the C++ registry.
  ///
  /// Converts the public ModelInfo (from model_types.dart) to the FFI format
  /// and saves it to the C++ registry for model discovery and loading.
  ///
  /// Matches Swift: `CppBridge.ModelRegistry.shared.save(modelInfo)`
  Future<bool> savePublicModel(public_types.ModelInfo model) async {
    if (_registryHandle == null) {
      _logger.debug('Registry not initialized, cannot save model');
      return false;
    }

    try {
      // Convert public ModelInfo to FFI ModelInfo
      final ffiModel = ModelInfo(
        id: model.id,
        name: model.name,
        category: _categoryToFfi(model.category),
        format: _formatToFfi(model.format),
        framework: _frameworkToFfi(model.framework),
        source: _sourceToFfi(model.source),
        sizeBytes: model.downloadSize ?? 0,
        downloadURL: model.downloadURL?.toString(),
        localPath: model.localPath?.toFilePath(),
        version: null,
      );

      final result = await saveModel(ffiModel);
      if (result) {
        _logger.debug('Saved public model to C++ registry: ${model.id}');
      }
      return result;
    } catch (e) {
      _logger.debug('savePublicModel error: $e');
      return false;
    }
  }

  // ===========================================================================
  // FFI Type Conversion Helpers
  // ===========================================================================

  /// Convert public ModelCategory to C++ RAC_MODEL_CATEGORY int
  static int _categoryToFfi(public_types.ModelCategory category) {
    switch (category) {
      case public_types.ModelCategory.language:
        return 0; // RAC_MODEL_CATEGORY_LANGUAGE
      case public_types.ModelCategory.speechRecognition:
        return 1; // RAC_MODEL_CATEGORY_SPEECH_RECOGNITION
      case public_types.ModelCategory.speechSynthesis:
        return 2; // RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS
      case public_types.ModelCategory.vision:
        return 3; // RAC_MODEL_CATEGORY_VISION
      case public_types.ModelCategory.imageGeneration:
        return 4; // RAC_MODEL_CATEGORY_IMAGE_GENERATION
      case public_types.ModelCategory.multimodal:
        return 5; // RAC_MODEL_CATEGORY_MULTIMODAL
      case public_types.ModelCategory.audio:
        return 6; // RAC_MODEL_CATEGORY_AUDIO
    }
  }

  /// Convert public ModelFormat to C++ RAC_MODEL_FORMAT int
  static int _formatToFfi(public_types.ModelFormat format) {
    switch (format) {
      case public_types.ModelFormat.onnx:
        return 0; // RAC_MODEL_FORMAT_ONNX
      case public_types.ModelFormat.ort:
        return 1; // RAC_MODEL_FORMAT_ORT
      case public_types.ModelFormat.gguf:
        return 2; // RAC_MODEL_FORMAT_GGUF
      case public_types.ModelFormat.bin:
        return 3; // RAC_MODEL_FORMAT_BIN
      case public_types.ModelFormat.unknown:
        return 99; // RAC_MODEL_FORMAT_UNKNOWN
    }
  }

  /// Convert public InferenceFramework to C++ RAC_FRAMEWORK int
  static int _frameworkToFfi(public_types.InferenceFramework framework) {
    switch (framework) {
      case public_types.InferenceFramework.onnx:
        return 0; // RAC_FRAMEWORK_ONNX
      case public_types.InferenceFramework.llamaCpp:
        return 1; // RAC_FRAMEWORK_LLAMACPP
      case public_types.InferenceFramework.foundationModels:
        return 2; // RAC_FRAMEWORK_FOUNDATION_MODELS
      case public_types.InferenceFramework.systemTTS:
        return 3; // RAC_FRAMEWORK_SYSTEM_TTS
      case public_types.InferenceFramework.fluidAudio:
        return 4; // RAC_FRAMEWORK_FLUID_AUDIO
      case public_types.InferenceFramework.builtIn:
        return 5; // RAC_FRAMEWORK_BUILTIN
      case public_types.InferenceFramework.none:
        return 6; // RAC_FRAMEWORK_NONE
      case public_types.InferenceFramework.unknown:
        return 99; // RAC_FRAMEWORK_UNKNOWN
    }
  }

  /// Convert public ModelSource to C++ RAC_MODEL_SOURCE int
  static int _sourceToFfi(public_types.ModelSource source) {
    switch (source) {
      case public_types.ModelSource.remote:
        return 1; // RAC_MODEL_SOURCE_REMOTE
      case public_types.ModelSource.local:
        return 2; // RAC_MODEL_SOURCE_LOCAL
    }
  }

  /// Get the FFI framework value (for external use)
  static int getFrameworkFfiValue(public_types.InferenceFramework framework) {
    return _frameworkToFfi(framework);
  }

  // ===========================================================================
  // Reverse FFI Type Conversion (C++ → Dart public types)
  // ===========================================================================

  /// Convert C++ RAC_MODEL_CATEGORY int to public ModelCategory
  static public_types.ModelCategory _categoryFromFfi(int category) {
    switch (category) {
      case 0:
        return public_types.ModelCategory.language;
      case 1:
        return public_types.ModelCategory.speechRecognition;
      case 2:
        return public_types.ModelCategory.speechSynthesis;
      case 3:
        return public_types.ModelCategory.vision;
      case 4:
        return public_types.ModelCategory.imageGeneration;
      case 5:
        return public_types.ModelCategory.multimodal;
      case 6:
        return public_types.ModelCategory.audio;
      default:
        return public_types.ModelCategory.language;
    }
  }

  /// Convert C++ RAC_MODEL_FORMAT int to public ModelFormat
  static public_types.ModelFormat _formatFromFfi(int format) {
    switch (format) {
      case 0:
        return public_types.ModelFormat.onnx;
      case 1:
        return public_types.ModelFormat.ort;
      case 2:
        return public_types.ModelFormat.gguf;
      case 3:
        return public_types.ModelFormat.bin;
      default:
        return public_types.ModelFormat.unknown;
    }
  }

  /// Convert C++ RAC_FRAMEWORK int to public InferenceFramework
  static public_types.InferenceFramework _frameworkFromFfi(int framework) {
    switch (framework) {
      case 0:
        return public_types.InferenceFramework.onnx;
      case 1:
        return public_types.InferenceFramework.llamaCpp;
      case 2:
        return public_types.InferenceFramework.foundationModels;
      case 3:
        return public_types.InferenceFramework.systemTTS;
      case 4:
        return public_types.InferenceFramework.fluidAudio;
      case 5:
        return public_types.InferenceFramework.builtIn;
      case 6:
        return public_types.InferenceFramework.none;
      default:
        return public_types.InferenceFramework.unknown;
    }
  }

  /// Convert C++ RAC_MODEL_SOURCE int to public ModelSource
  static public_types.ModelSource _sourceFromFfi(int source) {
    switch (source) {
      case 1:
        return public_types.ModelSource.remote;
      case 2:
        return public_types.ModelSource.local;
      default:
        return public_types.ModelSource.remote;
    }
  }

  /// Convert FFI ModelInfo to public ModelInfo
  static public_types.ModelInfo _ffiModelToPublic(ModelInfo ffiModel) {
    return public_types.ModelInfo(
      id: ffiModel.id,
      name: ffiModel.name,
      category: _categoryFromFfi(ffiModel.category),
      format: _formatFromFfi(ffiModel.format),
      framework: _frameworkFromFfi(ffiModel.framework),
      downloadURL: ffiModel.downloadURL != null
          ? Uri.tryParse(ffiModel.downloadURL!)
          : null,
      localPath: ffiModel.localPath != null && ffiModel.localPath!.isNotEmpty
          ? Uri.file(ffiModel.localPath!)
          : null,
      downloadSize: ffiModel.sizeBytes > 0 ? ffiModel.sizeBytes : null,
      source: _sourceFromFfi(ffiModel.source),
    );
  }

  // ===========================================================================
  // Public Model Query Methods (returns public_types.ModelInfo)
  // ===========================================================================

  /// Get all models from C++ registry as public ModelInfo objects.
  ///
  /// Matches Swift: `CppBridge.ModelRegistry.shared.getAll()`
  Future<List<public_types.ModelInfo>> getAllPublicModels() async {
    final ffiModels = await getAllModels();
    return ffiModels.map(_ffiModelToPublic).toList();
  }

  /// Get a single model from C++ registry as public ModelInfo.
  Future<public_types.ModelInfo?> getPublicModel(String modelId) async {
    final ffiModel = await getModel(modelId);
    if (ffiModel == null) return null;
    return _ffiModelToPublic(ffiModel);
  }

  /// Get model by ID
  Future<ModelInfo?> getModel(String modelId) async {
    if (_registryHandle == null) return null;

    try {
      final lib = PlatformLoader.loadCommons();
      final getFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>,
              Pointer<Pointer<RacModelInfoCStruct>>),
          int Function(Pointer<Void>, Pointer<Utf8>,
              Pointer<Pointer<RacModelInfoCStruct>>)>('rac_model_registry_get');

      final modelIdPtr = modelId.toNativeUtf8();
      final outModelPtr = calloc<Pointer<RacModelInfoCStruct>>();

      try {
        final result = getFn(_registryHandle!, modelIdPtr, outModelPtr);
        if (result == RacResultCode.success && outModelPtr.value != nullptr) {
          final model = _cStructToModelInfo(outModelPtr.value);

          // Free the model struct
          final freeFn = lib.lookupFunction<
              Void Function(Pointer<RacModelInfoCStruct>),
              void Function(
                  Pointer<RacModelInfoCStruct>)>('rac_model_info_free');
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
          Int32 Function(Pointer<Void>,
              Pointer<Pointer<Pointer<RacModelInfoCStruct>>>, Pointer<IntPtr>),
          int Function(
              Pointer<Void>,
              Pointer<Pointer<Pointer<RacModelInfoCStruct>>>,
              Pointer<IntPtr>)>('rac_model_registry_get_all');

      final outModelsPtr = calloc<Pointer<Pointer<RacModelInfoCStruct>>>();
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
            models.add(_cStructToModelInfo(modelPtr));
          }
        }

        // Free the array
        final freeFn = lib.lookupFunction<
            Void Function(Pointer<Pointer<RacModelInfoCStruct>>, IntPtr),
            void Function(Pointer<Pointer<RacModelInfoCStruct>>,
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
          Int32 Function(Pointer<Void>,
              Pointer<Pointer<Pointer<RacModelInfoCStruct>>>, Pointer<IntPtr>),
          int Function(
              Pointer<Void>,
              Pointer<Pointer<Pointer<RacModelInfoCStruct>>>,
              Pointer<IntPtr>)>('rac_model_registry_get_downloaded');

      final outModelsPtr = calloc<Pointer<Pointer<RacModelInfoCStruct>>>();
      final outCountPtr = calloc<IntPtr>();

      try {
        final result =
            getDownloadedFn(_registryHandle!, outModelsPtr, outCountPtr);
        if (result != RacResultCode.success) return [];

        final count = outCountPtr.value;
        if (count == 0) return [];

        final models = <ModelInfo>[];
        final modelsArray = outModelsPtr.value;

        for (var i = 0; i < count; i++) {
          final modelPtr = modelsArray[i];
          if (modelPtr != nullptr) {
            models.add(_cStructToModelInfo(modelPtr));
          }
        }

        // Free the array
        final freeFn = lib.lookupFunction<
            Void Function(Pointer<Pointer<RacModelInfoCStruct>>, IntPtr),
            void Function(Pointer<Pointer<RacModelInfoCStruct>>,
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
              Pointer<Pointer<Pointer<RacModelInfoCStruct>>>, Pointer<IntPtr>),
          int Function(
              Pointer<Void>,
              Pointer<Int32>,
              int,
              Pointer<Pointer<Pointer<RacModelInfoCStruct>>>,
              Pointer<IntPtr>)>('rac_model_registry_get_by_frameworks');

      final frameworksPtr = calloc<Int32>(frameworks.length);
      for (var i = 0; i < frameworks.length; i++) {
        frameworksPtr[i] = frameworks[i];
      }

      final outModelsPtr = calloc<Pointer<Pointer<RacModelInfoCStruct>>>();
      final outCountPtr = calloc<IntPtr>();

      try {
        final result = getByFrameworksFn(_registryHandle!, frameworksPtr,
            frameworks.length, outModelsPtr, outCountPtr);

        if (result != RacResultCode.success) return [];

        final count = outCountPtr.value;
        if (count == 0) return [];

        final models = <ModelInfo>[];
        final modelsArray = outModelsPtr.value;

        for (var i = 0; i < count; i++) {
          final modelPtr = modelsArray[i];
          if (modelPtr != nullptr) {
            models.add(_cStructToModelInfo(modelPtr));
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
    if (_registryHandle == null) {
      _logger.error('updateDownloadStatus: registry handle is null!');
      return false;
    }

    try {
      final lib = PlatformLoader.loadCommons();
      final updateFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_model_registry_update_download_status');

      final modelIdPtr = modelId.toNativeUtf8();
      final localPathPtr = localPath?.toNativeUtf8() ?? nullptr;

      try {
        final result =
            updateFn(_registryHandle!, modelIdPtr, localPathPtr.cast<Utf8>());
        if (result != RacResultCode.success) {
          _logger.warning(
              'updateDownloadStatus failed for $modelId: result=$result');
        }
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
      final removeFn = lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>),
          int Function(
              Pointer<Void>, Pointer<Utf8>)>('rac_model_registry_remove');

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
  // Model Discovery
  // ============================================================================

  /// Discover downloaded models by scanning filesystem
  Future<DiscoveryResult> discoverDownloadedModels() async {
    if (_registryHandle == null) {
      return const DiscoveryResult(discoveredModels: [], unregisteredCount: 0);
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
          return const DiscoveryResult(
              discoveredModels: [], unregisteredCount: 0);
        }

        // Parse result
        final discoveredModels = <DiscoveredModel>[];
        final discoveredCount = resultStruct.ref.discoveredCount;

        for (var i = 0; i < discoveredCount; i++) {
          final modelPtr = resultStruct.ref.discoveredModels + i;
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
                void Function(Pointer<RacDiscoveryResultStruct>)>(
            'rac_discovery_result_free');
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

  /// Convert C struct to Dart ModelInfo using correct struct layout.
  /// Uses RacModelInfoCStruct which matches the actual C rac_model_info_t.
  ModelInfo _cStructToModelInfo(Pointer<RacModelInfoCStruct> struct) {
    return ModelInfo(
      id: struct.ref.id.toDartString(),
      name: struct.ref.name.toDartString(),
      category: struct.ref.category,
      format: struct.ref.format,
      framework: struct.ref.framework,
      source: struct.ref.source,
      sizeBytes: struct.ref.downloadSize,
      downloadURL: struct.ref.downloadUrl != nullptr
          ? struct.ref.downloadUrl.toDartString()
          : null,
      localPath: struct.ref.localPath != nullptr
          ? struct.ref.localPath.toDartString()
          : null,
      version: null,
    );
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
