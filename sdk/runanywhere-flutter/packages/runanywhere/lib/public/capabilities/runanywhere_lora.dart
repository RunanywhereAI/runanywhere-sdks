// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_lora.dart — LoRA capability surface (canonical §3 namespace).
// Mirrors Swift `RunAnywhere.LoRA` and Kotlin `RunAnywhere.lora` (G-A7).
//
// Canonical runtime and catalog surface:
//   apply / remove / list / state / checkCompatibility /
//   register / listCatalog / queryCatalog / getCatalogEntry /
//   markDownloadCompleted / adaptersForModel / allRegistered

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/download_service.pbenum.dart'
    show DownloadState;
import 'package:runanywhere/generated/errors.pbenum.dart'
    show ErrorCategory, ErrorCode;
import 'package:runanywhere/generated/lora_options.pb.dart';
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show InferenceFramework, ModelCategory, ModelFileRole, ModelFormat,
        ModelSource;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_lora.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';

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
  Future<LoRAApplyResult> apply(LoRAApplyRequest request) async {
    return DartBridgeLora.shared.apply(request);
  }

  /// Remove one or more LoRA adapters, or clear all adapters.
  Future<LoRAState> remove(LoRARemoveRequest request) async {
    return DartBridgeLora.shared.remove(request);
  }

  /// Currently loaded LoRA adapters.
  Future<LoRAState> list() async {
    return DartBridgeLora.shared.list();
  }

  /// LoRA service state reported by commons.
  Future<LoRAState> state() async {
    return DartBridgeLora.shared.state();
  }

  /// Whether the current backend supports the given adapter.
  Future<LoraCompatibilityResult> checkCompatibility(
    LoRAAdapterConfig config,
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

  /// Record native-owned download/import completion in the commons LoRA catalog.
  Future<LoraAdapterDownloadCompletedResult> markDownloadCompleted(
    LoraAdapterDownloadCompletedRequest request,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.markDownloadCompleted(request);
  }

  /// Record native-reported LoRA adapter import completion in commons.
  ///
  /// Mirrors Swift `RunAnywhere.lora.markImportCompleted(_:)`. Uses the
  /// generated download-completed message with `imported = true`, matching the
  /// IDL contract for platform file-picker/import completion.
  Future<LoraAdapterDownloadCompletedResult> markImportCompleted(
    LoraAdapterDownloadCompletedRequest request,
  ) async {
    final importRequest = request.deepCopy()..imported = true;
    if (importRequest.statusMessage.isEmpty) {
      importRequest.statusMessage = 'import completed';
    }
    return markDownloadCompleted(importRequest);
  }

  /// Import a user-picked local adapter file into SDK-owned storage.
  ///
  /// Dart only resolves platform access (file-picker temp path) before
  /// calling; commons owns everything past the readable source path:
  /// deterministic catalog matching, canonical placement, artifact registry
  /// record + manifest persistence, and catalog completion for matched
  /// entries. Mirrors Swift `RunAnywhere.lora.importAdapter(from:)`.
  Future<LoraAdapterImportResult> importAdapter(String sourcePath) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.importAdapter(
      LoraAdapterImportRequest(sourcePath: sourcePath),
    );
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
  // Mirrors Swift RunAnywhere+LoRADownload.swift:97-160.

  static const _loraArtifactModelIdPrefix = 'lora-adapter:';
  static const _loraArtifactTag = 'lora-adapter';

  /// Stable model-registry id used for an adapter's download artifact.
  String _loraArtifactModelId(LoraAdapterCatalogEntry entry) =>
      entry.id.startsWith(_loraArtifactModelIdPrefix)
          ? entry.id
          : '$_loraArtifactModelIdPrefix${entry.id}';

  /// Convert a catalog entry into model-registry metadata used by the
  /// generic download path. Catalog filtering and completion state remain
  /// owned by the LoRA catalog ABI. Mirrors Swift
  /// `RALoraAdapterCatalogEntry.toLoraArtifactModelInfo()`.
  model_pb.ModelInfo _toLoraArtifactModelInfo(LoraAdapterCatalogEntry entry) {
    final urlTail = entry.url.split('/').isNotEmpty
        ? entry.url.split('/').last
        : entry.url;
    final artifactFilename = entry.filename.isNotEmpty
        ? entry.filename
        : urlTail.split('?').first;

    final descriptor = model_pb.ModelFileDescriptor(
      role: ModelFileRole.MODEL_FILE_ROLE_COMPANION,
      url: entry.url,
      filename: artifactFilename,
      relativePath: artifactFilename,
      isRequired: true,
    );
    if (entry.sizeBytes > 0) descriptor.sizeBytes = entry.sizeBytes;
    if (entry.hasChecksumSha256() && entry.checksumSha256.isNotEmpty) {
      descriptor.checksumSha256 = entry.checksumSha256;
    }

    final expectedFiles = model_pb.ExpectedModelFiles(
      files: [descriptor],
      requiredPatterns: [artifactFilename],
      description: 'LoRA adapter artifact',
    );

    final seen = <String>{};
    final tags = <String>[
      _loraArtifactTag,
      ...entry.compatibleModels.map((m) => 'base-model:$m'),
      ...entry.tags,
    ].where(seen.add).toList(growable: false);

    final metadata = model_pb.ModelInfoMetadata(
      description: entry.description,
      tags: tags,
    );
    if (entry.hasAuthor()) metadata.author = entry.author;
    if (entry.hasLicense()) metadata.license = entry.license;

    final model = model_pb.ModelInfo(
      id: _loraArtifactModelId(entry),
      name: entry.name,
      category: ModelCategory.MODEL_CATEGORY_UNSPECIFIED,
      format: ModelFormat.MODEL_FORMAT_GGUF,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN,
      downloadUrl: entry.url,
      source: ModelSource.MODEL_SOURCE_REMOTE,
      description: entry.description,
      singleFile: model_pb.SingleFileArtifact(
        requiredPatterns: [artifactFilename],
        expectedFiles: expectedFiles,
      ),
      expectedFiles: expectedFiles,
      metadata: metadata,
      isAvailable: true,
    );
    if (entry.sizeBytes > 0) model.downloadSizeBytes = entry.sizeBytes;
    if (entry.hasChecksumSha256() && entry.checksumSha256.isNotEmpty) {
      model.checksumSha256 = entry.checksumSha256;
    }
    return model;
  }

  /// Register both the LoRA catalog entry and its downloadable artifact
  /// record. Does not fetch bytes. Mirrors Swift `lora.registerArtifact(_:)`
  /// (RunAnywhere+LoRADownload.swift:97).
  Future<model_pb.ModelInfo> registerArtifact(
    LoraAdapterCatalogEntry entry,
  ) async {
    final registered = await register(entry);
    final artifact = _toLoraArtifactModelInfo(registered);
    final saved =
        await DartBridgeModelRegistry.instance.saveProtoModel(artifact);
    if (!saved) {
      // Mirrors Swift CppBridge.ModelRegistry.save failure
      // (CppBridge+ModelRegistry.swift:160-162): `.processingFailed`.
      throw SDKException.processingFailed(
        'Failed to save model via proto registry: ${artifact.id}',
      );
    }
    return artifact;
  }

  /// Download a LoRA adapter through the canonical model-download pipeline.
  ///
  /// One call does everything: registers the catalog entry + artifact,
  /// downloads with resume/checksum/progress via commons, records completion
  /// in the LoRA catalog, and returns the stable local path of the adapter
  /// file. Mirrors Swift `lora.download(_:onProgress:)`
  /// (RunAnywhere+LoRADownload.swift:111).
  Future<String> download(
    LoraAdapterCatalogEntry entry, {
    void Function(double progress)? onProgress,
  }) async {
    final artifact = await registerArtifact(entry);

    String localPath = '';
    await for (final progress
        in RunAnywhereDownloads.shared.start(artifact.id)) {
      onProgress?.call(progress.overallProgress);
      if (progress.state == DownloadState.DOWNLOAD_STATE_FAILED) {
        // Mirrors Swift's `RunAnywhere.downloadModel` terminal-failure throw
        // (`.downloadFailed`, network category).
        throw SDKException.make(
          code: ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
          message: progress.errorMessage.isNotEmpty
              ? progress.errorMessage
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
      // The import step persisted the path on the registry record.
      final lookup =
          await DartBridgeModelRegistry.instance.getProtoModel(artifact.id);
      localPath = lookup?.localPath ?? '';
    }
    if (localPath.isEmpty) {
      // Mirrors Swift RunAnywhere+LoRADownload.swift:128-134:
      // `.downloadFailed`, network category.
      throw SDKException.make(
        code: ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
        message:
            "LoRA adapter '${entry.id}' downloaded but no local path was recorded",
        category: ErrorCategory.ERROR_CATEGORY_NETWORK,
      );
    }

    await markDownloadCompleted(LoraAdapterDownloadCompletedRequest(
      adapterId: entry.id,
      localPath: localPath,
    ));
    return localPath;
  }
}
