// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_lora.dart — LoRA capability surface (canonical §3 namespace).
// Mirrors Swift `RunAnywhere.LoRA` and Kotlin `RunAnywhere.lora` (G-A7).
//
// Canonical runtime and catalog surface:
//   apply / remove / list / state / checkCompatibility /
//   register / listCatalog / queryCatalog / getCatalogEntry /
//   registerArtifact / download / importAdapter / adaptersForModel /
//   allRegistered

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/download_service.pbenum.dart'
    show DownloadState;
import 'package:runanywhere/generated/errors.pbenum.dart'
    show ErrorCategory, ErrorCode;
import 'package:runanywhere/generated/lora_options.pb.dart';
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_lora.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';
import 'package:runanywhere/public/extensions/runanywhere_storage.dart';

/// LoRA (Low-Rank Adaptation) capability surface.
///
/// Access via `RunAnywhere.lora`. Mirrors Swift
/// `RunAnywhere.LoRA` and Kotlin `RunAnywhere.lora`.
class RunAnywhereLoRACapability {
  RunAnywhereLoRACapability._();
  static final RunAnywhereLoRACapability _instance =
      RunAnywhereLoRACapability._();
  static RunAnywhereLoRACapability get shared => _instance;

  // --- Runtime adapter operations ----------------------------------------

  /// Apply one or more LoRA adapters to the current model.
  Future<LoraApplyResult> apply(LoraApplyRequest request) async {
    return DartBridgeLora.shared.apply(request);
  }

  /// Apply one registered catalog adapter to the current model.
  ///
  /// Preserves [entry.id] in the generated config so commons can validate
  /// registered catalog adapters against the loaded base model.
  ///
  /// `replaceExisting` keeps its pre-realignment name and `false` default at
  /// this public boundary; only proto construction below inverts it to the
  /// wire's `keep_existing` (idl/lora_options.proto polarity inversion:
  /// `replaceExisting: false` → `keepExisting: true`, i.e. stack on top of
  /// the current set, the unchanged default behavior).
  Future<LoraApplyResult> applyCatalogAdapter(
    LoraAdapterCatalogEntry entry, {
    String? localPath,
    double? scale,
    bool replaceExisting = false,
  }) async {
    final adapterPath =
        localPath ?? (entry.localPath.isNotEmpty ? entry.localPath : '');
    if (adapterPath.isEmpty) {
      throw SDKException.make(
        code: ErrorCode.ERROR_CODE_INVALID_ARGUMENT,
        message: "LoRA catalog adapter '${entry.id}' has no local path",
        category: ErrorCategory.ERROR_CATEGORY_INTERNAL,
      );
    }

    final effectiveScale =
        scale ??
        (entry.hasDefaultScale() && entry.defaultScale > 0
            ? entry.defaultScale
            : 1.0);
    return apply(
      LoraApplyRequest(
        adapters: [
          LoraAdapterConfig(
            adapterPath: adapterPath,
            adapterId: entry.id,
            scale: effectiveScale,
          ),
        ],
        keepExisting: !replaceExisting,
      ),
    );
  }

  /// Remove one or more LoRA adapters, or clear all adapters.
  Future<LoraState> remove(LoraRemoveRequest request) async {
    return DartBridgeLora.shared.remove(request);
  }

  /// Currently loaded LoRA adapters.
  Future<LoraState> list() async {
    return DartBridgeLora.shared.list();
  }

  /// LoRA service state reported by commons.
  Future<LoraState> state() async {
    return DartBridgeLora.shared.state();
  }

  /// Whether the current backend supports the given adapter.
  Future<LoraCompatibilityResult> checkCompatibility(
    LoraAdapterConfig config,
  ) async {
    return DartBridgeLora.shared.checkCompatibility(config);
  }

  // --- Catalog operations -----------------------------------------------

  /// Register a LoRA adapter in the global registry. Entry is
  /// deep-copied internally by C++.
  Future<LoraAdapterCatalogEntry> register(
    LoraAdapterCatalogEntry entry,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.register(entry);
  }

  /// Generated-proto LoRA catalog list surface.
  Future<LoraAdapterCatalogListResult> listCatalog([
    LoraAdapterCatalogListRequest? request,
  ]) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.listCatalog(
      request ?? LoraAdapterCatalogListRequest(),
    );
  }

  /// Generated-proto LoRA catalog query surface.
  Future<LoraAdapterCatalogListResult> queryCatalog(
    LoraAdapterCatalogQuery query,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.queryCatalog(query);
  }

  /// Generated-proto LoRA catalog get surface.
  Future<LoraAdapterCatalogGetResult> getCatalogEntry(
    LoraAdapterCatalogGetRequest request,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.getCatalogEntry(request);
  }

  /// All registered LoRA adapters compatible with [modelId].
  Future<List<LoraAdapterCatalogEntry>> adaptersForModel(String modelId) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.getForModel(modelId);
  }

  /// All registered LoRA adapters.
  Future<List<LoraAdapterCatalogEntry>> allRegistered() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.getAll();
  }

  // --- SDK-owned artifact registration + download -------------------------
  // Mirrors Swift RunAnywhere+LoRADownload.swift.
  //
  // `LoraAdapterCatalogEntry` no longer carries url/filename/size/checksum
  // metadata (idl/lora_options.proto: "everything generic about the
  // artifact ... lives on the ModelInfo record for this adapter"), so the
  // artifact can no longer be derived from the entry alone — callers supply
  // the `artifact` describing where/how to fetch the adapter bytes.

  static const _loraArtifactTag = 'lora-adapter';

  /// Register both the LoRA catalog entry and its caller-supplied
  /// downloadable artifact record. Does not fetch bytes. Mirrors Swift
  /// `lora.registerArtifact(_:artifact:)`.
  Future<model_pb.ModelInfo> registerArtifact(
    LoraAdapterCatalogEntry entry,
    model_pb.ModelInfo artifact,
  ) async {
    await register(entry);
    final tagged = artifact.deepCopy();
    if (!tagged.metadata.tags.contains(_loraArtifactTag)) {
      tagged.metadata.tags.add(_loraArtifactTag);
    }
    final saved = await DartBridgeModelRegistry.instance.saveProtoModel(
      tagged,
    );
    if (!saved) {
      throw SDKException.processingFailed(
        'Failed to save model via proto registry: ${tagged.id}',
      );
    }
    return tagged;
  }

  /// Download a LoRA adapter through the canonical model-download pipeline.
  ///
  /// One call does everything: registers the catalog entry + caller-supplied
  /// [artifact], downloads with resume/checksum/progress via commons, and
  /// returns the stable local path of the adapter file. Mirrors Swift
  /// `lora.download(_:artifact:onProgress:)`.
  Future<String> download(
    LoraAdapterCatalogEntry entry,
    model_pb.ModelInfo artifact, {
    void Function(double progress)? onProgress,
  }) async {
    final registeredArtifact = await registerArtifact(entry, artifact);

    String localPath = '';
    await for (final progress in RunAnywhereDownloads.shared.start(
      registeredArtifact.id,
    )) {
      onProgress?.call(progress.overallProgress);
      if (progress.state == DownloadState.DOWNLOAD_STATE_FAILED) {
        // Mirrors Swift's `RunAnywhere.downloadModel` terminal-failure throw
        // (`.downloadFailed`, network category).
        throw SDKException.make(
          code: ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
          message: progress.hasError()
              ? progress.error.message
              : 'LoRA adapter download failed for ${entry.id}',
          category: ErrorCategory.ERROR_CATEGORY_NETWORK,
        );
      }
      if (progress.state == DownloadState.DOWNLOAD_STATE_COMPLETED) {
        localPath = progress.localPath;
        break;
      }
    }

    if (localPath.isEmpty) {
      // The download step persisted the path on the registry record.
      final lookup = await DartBridgeModelRegistry.instance.getProtoModel(
        registeredArtifact.id,
      );
      localPath = lookup?.localPath ?? '';
    }
    if (localPath.isEmpty) {
      throw SDKException.make(
        code: ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
        message:
            "LoRA adapter '${entry.id}' downloaded but no local path was recorded",
        category: ErrorCategory.ERROR_CATEGORY_NETWORK,
      );
    }
    return localPath;
  }

  /// Import a user-picked LoRA adapter file (file-picker / share sheet) into
  /// SDK-owned storage.
  ///
  /// `LoraAdapterImportRequest`/`Result` were deleted outright
  /// (idl/lora_options.proto, lora-delete-download-import-bookkeeping): the
  /// LoRA-domain import verb — which used to do deterministic catalog
  /// matching, canonical placement, and catalog `imported=true` completion —
  /// has no replacement in that domain. Adapter files are now acquired
  /// exclusively through the models domain's generic import verb
  /// (`RunAnywhereStorage.importModel`, `ModelImportRequest`/`Result`), so
  /// this resolves the source path and imports as a plain model artifact
  /// tagged `lora-adapter`. Unlike the retired ABI, this does NOT
  /// automatically match the import against an existing LoRA catalog entry —
  /// callers that need the catalog association call
  /// `register`/`registerArtifact` with the matching entry themselves once
  /// they know which adapter this file corresponds to. Mirrors Swift
  /// `lora.importAdapter(from:)`.
  Future<model_pb.ModelImportResult> importAdapter(String sourcePath) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final model = model_pb.ModelInfo(
      metadata: model_pb.ModelInfoMetadata(tags: [_loraArtifactTag]),
    );
    return RunAnywhereStorage.importModel(
      model_pb.ModelImportRequest(
        model: model,
        sourcePath: sourcePath,
        copyIntoManagedStorage: true,
        validateBeforeRegister: true,
      ),
    );
  }
}
