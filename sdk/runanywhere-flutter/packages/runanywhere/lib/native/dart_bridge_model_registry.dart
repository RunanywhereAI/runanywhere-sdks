// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

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

  /// Models registered before the global registry handle is wired (Phase 1 race).
  static final List<model_pb.ModelInfo> _pendingProtoModels = [];

  /// Native global registry handle for other proto-byte bridge surfaces.
  Pointer<Void>? get nativeHandle => _registryHandle;

  // ============================================================================
  // Lifecycle
  // ============================================================================

  /// Wire the global C++ model registry handle (sync, Phase 1 safe).
  ///
  /// IMPORTANT: Uses the GLOBAL C++ model registry via rac_get_model_registry(),
  /// NOT rac_model_registry_create() which would create a separate instance.
  /// This matches Swift's CppBridge+ModelRegistry.swift behavior.
  void ensureInitialized() {
    if (_registryHandle != null) {
      return;
    }

    try {
      final lib = PlatformLoader.loadCommons();

      // Use the GLOBAL C++ model registry - same as Swift does
      // This is critical: C++ code (rac_get_model, rac_llm_component_load_model)
      // looks up models in the GLOBAL registry, not a separate instance
      final getGlobalRegistryFn = lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'rac_get_model_registry',
          );

      final globalRegistry = getGlobalRegistryFn();

      if (globalRegistry != nullptr) {
        _registryHandle = globalRegistry;
        _logger.debug('Using global C++ model registry');
        _flushPendingProtoModels();
      } else {
        _logger.error('Failed to get global model registry');
      }
    } catch (e) {
      _logger.debug('Model registry init error: $e');
    }
  }

  /// Initialize the model registry (async alias for Phase 2).
  Future<void> initialize() async {
    ensureInitialized();
  }

  void _flushPendingProtoModels() {
    if (_pendingProtoModels.isEmpty || _registryHandle == null) return;

    final pending = List<model_pb.ModelInfo>.from(_pendingProtoModels);
    _pendingProtoModels.clear();
    for (final model in pending) {
      final saved = _writeProtoModel(
        model,
        RacNative.bindings.rac_model_registry_register_proto,
        'rac_model_registry_register_proto',
      );
      if (saved != true) {
        _logger.warning('Deferred model save failed: ${model.id}');
      }
    }
    if (pending.isNotEmpty) {
      _logger.debug('Flushed ${pending.length} deferred proto models');
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
    _logger.debug('Model registry bridge shutdown (global registry preserved)');
  }

  // ============================================================================
  // Model CRUD Operations
  // ============================================================================

  /// Save a generated proto ModelInfo to the C++ registry.
  Future<bool> saveProtoModel(model_pb.ModelInfo model) async {
    if (_registryHandle == null) {
      ensureInitialized();
    }
    if (_registryHandle == null) {
      _pendingProtoModels.add(model);
      _logger.debug(
        'Registry not ready; queued proto model ${model.id} '
        '(pending=${_pendingProtoModels.length})',
      );
      return false;
    }

    return _writeProtoModel(
      model,
      RacNative.bindings.rac_model_registry_register_proto,
      'rac_model_registry_register_proto',
    );
  }

  /// Update an existing generated proto ModelInfo in the C++ registry.
  Future<bool> updateProtoModel(model_pb.ModelInfo model) async {
    if (_registryHandle == null) {
      _logger.debug('Registry not initialized, cannot update proto model');
      return false;
    }

    return _writeProtoModel(
      model,
      RacNative.bindings.rac_model_registry_update_proto,
      'rac_model_registry_update_proto',
    );
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
    return _queryProtoModels(query) ?? const [];
  }

  /// List downloaded models via the registry proto-byte ABI.
  Future<List<model_pb.ModelInfo>> listDownloadedProtoModels() async {
    return _listDownloadedProtoModels() ?? const [];
  }

  bool _writeProtoModel(
    model_pb.ModelInfo model,
    int Function(Pointer<Void>, Pointer<Uint8>, int) fn,
    String symbol,
  ) {
    if (_registryHandle == null) return false;

    final bytes = model.writeToBuffer();
    final bytesPtr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      if (bytes.isNotEmpty) {
        bytesPtr.asTypedList(bytes.length).setAll(0, bytes);
      }

      final result = fn(_registryHandle!, bytesPtr, bytes.length);
      if (result != RacResultCode.success) {
        _logger.debug('$symbol failed for ${model.id}: result=$result');
      }
      return result == RacResultCode.success;
    } catch (e) {
      _logger.debug('$symbol error: $e');
      return false;
    } finally {
      calloc.free(bytesPtr);
    }
  }

  model_pb.ModelInfo? _getProtoModel(String modelId) {
    if (_registryHandle == null) return null;

    final bindings = RacNative.bindings;
    final getFn = bindings.rac_model_registry_get_proto;
    final freeFn = bindings.rac_model_registry_proto_free;

    final modelIdPtr = modelId.toNativeUtf8();
    final outBytesPtr = calloc<Pointer<Uint8>>();
    final outSizePtr = calloc<Size>();

    try {
      final result = getFn(
        _registryHandle!,
        modelIdPtr,
        outBytesPtr,
        outSizePtr,
      );
      if (result != RacResultCode.success || outBytesPtr.value == nullptr) {
        if (result != RacResultCode.errorNotFound) {
          _logger.debug(
            'rac_model_registry_get_proto failed for $modelId: result=$result',
          );
        }
        return null;
      }

      final bytes = outBytesPtr.value
          .asTypedList(outSizePtr.value)
          .toList(growable: false);
      return DartBridgeModelFormat.shared.applyInferredArtifact(
        model_pb.ModelInfo.fromBuffer(bytes),
      );
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

    final outBytesPtr = calloc<Pointer<Uint8>>();
    final outSizePtr = calloc<Size>();

    try {
      final result = listFn(_registryHandle!, outBytesPtr, outSizePtr);
      if (result != RacResultCode.success || outBytesPtr.value == nullptr) {
        _logger.debug(
          'rac_model_registry_list_downloaded_proto failed: result=$result',
        );
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

  /// Register a remote model via `rac_register_model_from_url_proto`.
  ///
  /// Mirrors Swift's `RunAnywhere.registerModel(id:name:url:...)` URL form
  /// — commons owns the build-and-save flow; we only ship the proto request
  /// bytes and decode the resulting `ModelInfo` proto.
  Future<model_pb.ModelInfo?> registerModelFromUrl(
    model_pb.RegisterModelFromUrlRequest request,
  ) async {
    final fn = RacNative.bindings.rac_register_model_from_url_proto;
    try {
      return DartBridgeProtoUtils.callRequest<model_pb.ModelInfo>(
        request: request,
        invoke: fn,
        decode: model_pb.ModelInfo.fromBuffer,
        symbol: 'rac_register_model_from_url_proto',
      );
    } catch (e) {
      _logger.debug('rac_register_model_from_url_proto error: $e');
      return null;
    }
  }

  /// Register a multi-file model (VLM gguf+mmproj pairs, embedding
  /// model+vocab sets) via `rac_register_multi_file_model_proto`.
  ///
  /// Mirrors Swift's `RunAnywhere.registerModel(multiFile:...)` — commons
  /// builds the MultiFileArtifact ModelInfo and persists it with
  /// merge-on-reseed semantics.
  Future<model_pb.ModelInfo?> registerMultiFileModel(
    model_pb.RegisterMultiFileModelRequest request,
  ) async {
    final fn = RacNative.bindings.rac_register_multi_file_model_proto;
    try {
      return DartBridgeProtoUtils.callRequest<model_pb.ModelInfo>(
        request: request,
        invoke: fn,
        decode: model_pb.ModelInfo.fromBuffer,
        symbol: 'rac_register_multi_file_model_proto',
      );
    } catch (e) {
      _logger.debug('rac_register_multi_file_model_proto error: $e');
      return null;
    }
  }

  /// Import a local model into the registry via
  /// `rac_model_registry_import_proto`.
  ///
  /// Mirrors Swift's `RunAnywhere.importModel(_:)`. The caller must supply a
  /// stable, platform-normalized `sourcePath` (no transient file-picker
  /// handles).
  Future<model_pb.ModelImportResult> importModel(
    model_pb.ModelImportRequest request,
  ) async {
    final handle = _registryHandle;
    if (handle == null) {
      return model_pb.ModelImportResult(
        success: false,
        errorMessage: 'Model registry not initialized',
      );
    }
    final fn = RacNative.bindings.rac_model_registry_import_proto;
    try {
      return DartBridgeProtoUtils.callRequestWithHandle<
        model_pb.ModelImportResult
      >(
        handle: handle,
        request: request,
        invoke: fn,
        decode: model_pb.ModelImportResult.fromBuffer,
        symbol: 'rac_model_registry_import_proto',
      );
    } catch (e) {
      _logger.debug('rac_model_registry_import_proto error: $e');
      return model_pb.ModelImportResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Update download status for a model
  Future<bool> updateDownloadStatus(String modelId, String? localPath) async {
    if (_registryHandle == null) {
      _logger.error('updateDownloadStatus: registry handle is null!');
      return false;
    }

    final bindings = RacNative.bindings;
    final model = _getProtoModel(modelId);
    if (model == null) return false;
    final updated = model.deepCopy();
    if (localPath == null || localPath.isEmpty) {
      updated.clearLocalPath();
    } else {
      updated.localPath = localPath;
    }

    return _writeProtoModel(
      updated,
      bindings.rac_model_registry_update_proto,
      'rac_model_registry_update_proto',
    );
  }

  /// Remove a model from registry
  Future<bool> removeModel(String modelId) async {
    if (_registryHandle == null) return false;

    final removeProtoFn = RacNative.bindings.rac_model_registry_remove_proto;
    final modelIdPtr = modelId.toNativeUtf8();
    try {
      final result = removeProtoFn(_registryHandle!, modelIdPtr);
      if (result != RacResultCode.success) {
        _logger.debug(
          'rac_model_registry_remove_proto failed for $modelId: result=$result',
        );
      }
      return result == RacResultCode.success;
    } catch (e) {
      _logger.debug('rac_model_registry_remove_proto error: $e');
      return false;
    } finally {
      calloc.free(modelIdPtr);
    }
  }

  /// Update last used timestamp
  Future<bool> updateLastUsed(String modelId) async {
    if (_registryHandle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final updateFn = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Utf8>),
            int Function(Pointer<Void>, Pointer<Utf8>)
          >('rac_model_registry_update_last_used');

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
  // Refresh — bridges rac_model_registry_refresh_proto
  // ============================================================================

  /// Refresh the model registry via the commons proto entry point
  /// `rac_model_registry_refresh_proto`.
  ///
  /// Encodes a [model_pb.ModelRegistryRefreshRequest] and decodes the returned
  /// [model_pb.ModelRegistryRefreshResult]. Local rescan / orphan pruning are
  /// honoured at the C ABI layer (commons runs the adapter rescan via the
  /// registered `file_list_directory` slot); callers that need the discovered
  /// model list should use [discoverDownloadedModels] — the Models capability
  /// does exactly that.
  Future<bool> refresh({
    required bool rescanLocal,
    required bool includeRemoteCatalog,
    required bool pruneOrphans,
  }) async {
    final handle = _registryHandle;
    if (handle == null) return false;
    final fn = RacNative.bindings.rac_model_registry_refresh_proto;
    try {
      // Full request mirrors Swift RunAnywhere+ModelRegistry.swift
      // refreshModelRegistry: rescanLocal is forwarded and
      // includeDownloadedState is always true so the refreshed registry
      // carries downloaded-state reconciliation.
      final result =
          DartBridgeProtoUtils.callRequestWithHandle<
            model_pb.ModelRegistryRefreshResult
          >(
            handle: handle,
            request: model_pb.ModelRegistryRefreshRequest(
              rescanLocal: rescanLocal,
              includeRemoteCatalog: includeRemoteCatalog,
              pruneOrphans: pruneOrphans,
              includeDownloadedState: true,
            ),
            invoke: fn,
            decode: model_pb.ModelRegistryRefreshResult.fromBuffer,
            symbol: 'rac_model_registry_refresh_proto',
          );
      return result.success;
    } catch (e) {
      _logger.debug('rac_model_registry_refresh_proto error: $e');
      return false;
    }
  }

  // ============================================================================
  // Model Discovery
  // ============================================================================

  /// Discover downloaded models via the proto-bytes ABI.
  ///
  /// Mirrors Swift's
  /// `CppBridge.ModelRegistry.discoverDownloadedModels(_:)`. Platform
  /// filesystem traversal is owned by commons through the registered
  /// `rac_platform_adapter_t`; the SDK only ships a serialized
  /// `ModelDiscoveryRequest` and decodes the returned
  /// `ModelDiscoveryResult` proto.
  Future<model_pb.ModelDiscoveryResult> discoverDownloadedModels([
    model_pb.ModelDiscoveryRequest? request,
  ]) async {
    final handle = _registryHandle;
    if (handle == null) {
      return model_pb.ModelDiscoveryResult(success: false);
    }

    final discoverFn = RacNative.bindings.rac_model_registry_discover_proto;

    final discoveryRequest = request ?? _defaultDiscoveryRequest();
    try {
      return DartBridgeProtoUtils.callRequestWithHandle<
        model_pb.ModelDiscoveryResult
      >(
        handle: handle,
        request: discoveryRequest,
        invoke: discoverFn,
        decode: model_pb.ModelDiscoveryResult.fromBuffer,
        symbol: 'rac_model_registry_discover_proto',
      );
    } catch (e) {
      _logger.debug('rac_model_registry_discover_proto error: $e');
      return model_pb.ModelDiscoveryResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  static model_pb.ModelDiscoveryRequest _defaultDiscoveryRequest() {
    return model_pb.ModelDiscoveryRequest(
      linkDownloaded: true,
      recursive: true,
      includeUserImports: true,
      query: model_pb.ModelQuery(downloadedOnly: true),
    );
  }
}

// =============================================================================
// Model Format Bridge (folded from former dart_bridge_model_format.dart)
// =============================================================================

/// Thin proto-byte bridge for URL → ModelFormat / ModelArtifactType inference.
/// Delegates to the commons APIs
/// (`rac_model_format_from_url_proto`, `rac_artifact_infer_from_url_proto`).
///
/// Flutter does NOT own URL-suffix heuristics; commons is authoritative.
class DartBridgeModelFormat {
  DartBridgeModelFormat._();

  static final DartBridgeModelFormat shared = DartBridgeModelFormat._();

  /// URL → ModelFormat via commons.
  model_pb.ModelFormat formatFromUrl(String url) {
    final fn = RacNative.bindings.rac_model_format_from_url_proto;
    final result =
        DartBridgeProtoUtils.callRequest<model_pb.ModelFormatFromUrlResult>(
          request: model_pb.ModelFormatFromUrlRequest(url: url),
          invoke: fn,
          decode: model_pb.ModelFormatFromUrlResult.fromBuffer,
          symbol: 'rac_model_format_from_url_proto',
        );
    // Commons returns the archive-wrapper format for archive URLs; the inner
    // format (e.g. ONNX inside .tar.gz) is in result.innerFormat. For the
    // "what format is this model?" question the SDK asks, the inner format is
    // the authoritative answer when non-unspecified.
    if (result.innerFormat != model_pb.ModelFormat.MODEL_FORMAT_UNSPECIFIED &&
        result.innerFormat != model_pb.ModelFormat.MODEL_FORMAT_UNKNOWN) {
      return result.innerFormat;
    }
    return result.format;
  }

  /// URL → ArtifactInferFromUrlResult via commons.
  model_pb.ArtifactInferFromUrlResult inferArtifact(
    String url, {
    String modelId = '',
  }) {
    final fn = RacNative.bindings.rac_artifact_infer_from_url_proto;
    return DartBridgeProtoUtils.callRequest<
      model_pb.ArtifactInferFromUrlResult
    >(
      request: model_pb.ArtifactInferFromUrlRequest(url: url, modelId: modelId),
      invoke: fn,
      decode: model_pb.ArtifactInferFromUrlResult.fromBuffer,
      symbol: 'rac_artifact_infer_from_url_proto',
    );
  }

  /// Populate the artifact-classification fields on a copy of [model] based on
  /// its `downloadUrl` via commons. Preserves caller-supplied artifact fields
  /// when already set and handles the built-in short-circuit (DIRECTORY).
  /// Mirrors Kotlin
  /// `CppBridgeModelFormat.applyInferredArtifact`.
  model_pb.ModelInfo applyInferredArtifact(
    model_pb.ModelInfo model, [
    String? url,
  ]) {
    if (model.hasArtifactType() ||
        model.hasSingleFile() ||
        model.hasArchive() ||
        model.hasMultiFile() ||
        model.hasBuiltIn() ||
        model.hasCustomStrategyId()) {
      return model;
    }

    if (_isBuiltIn(model)) {
      return model.deepCopy()
        ..artifactType =
            model_pb.ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY
        ..builtIn = true;
    }

    final effectiveUrl = url ?? model.downloadUrl;
    if (effectiveUrl.isEmpty) return _asSingleFile(model);

    final inference = inferArtifact(effectiveUrl, modelId: model.id);

    final copy = model.deepCopy()..artifactType = inference.artifactType;
    switch (inference.artifactType) {
      case model_pb.ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE:
      case model_pb.ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE:
        copy.archive = model_pb.ArchiveArtifact(
          type:
              inference.archiveType ==
                  model_pb.ArchiveType.ARCHIVE_TYPE_UNSPECIFIED
              ? (inference.artifactType ==
                        model_pb
                            .ModelArtifactType
                            .MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE
                    ? model_pb.ArchiveType.ARCHIVE_TYPE_TAR_GZ
                    : model_pb.ArchiveType.ARCHIVE_TYPE_ZIP)
              : inference.archiveType,
          structure: inference.archiveStructure,
        );
        break;
      case model_pb.ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY:
        copy.multiFile = model_pb.MultiFileArtifact();
        break;
      case model_pb.ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE:
      default:
        copy.singleFile = model_pb.SingleFileArtifact();
    }
    return copy;
  }

  model_pb.ModelInfo _asSingleFile(model_pb.ModelInfo model) {
    return model.deepCopy()
      ..artifactType =
          model_pb.ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE
      ..singleFile = model_pb.SingleFileArtifact();
  }

  /// Mirrors the `ProtoModelInfoHelpers.isBuiltIn` extension in
  /// `model_types_cpp_bridge.dart` without introducing a circular import.
  static bool _isBuiltIn(model_pb.ModelInfo model) {
    if (model.hasBuiltIn() && model.builtIn) return true;
    if (model.localPath.startsWith('builtin:')) return true;
    return model.framework ==
            model_pb.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
        model.framework ==
            model_pb.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS ||
        model.framework ==
            model_pb.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN;
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
