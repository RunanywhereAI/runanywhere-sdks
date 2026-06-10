// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_storage.dart — storage + download helpers.
// Mirrors Swift `RunAnywhere+Storage.swift`.

import 'package:fixnum/fixnum.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/model_types.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_file_manager.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/public/extensions/model_category_extensions.dart';

/// Static helpers for storage + low-level download + model registration.
///
/// Mirrors Swift `RunAnywhere+Storage.swift` — every public method in the
/// Swift extension has a corresponding entry point here.
class RunAnywhereStorage {
  RunAnywhereStorage._();

  // ===========================================================================
  // Model registration (Swift-parity URL / archive / multi-file overloads)
  // ===========================================================================

  /// Register a remote model with the in-memory model registry from a
  /// download URL. Delegates the full build-and-save flow to the commons
  /// single-call factory `rac_register_model_from_url_proto`, which derives
  /// the canonical id from the URL (`rac_model_generate_id`), defaults
  /// format/framework/category/context-length, infers the artifact type from
  /// the URL extension (archive vs single-file), overlays the caller-supplied
  /// capability fields, and persists through the registry save path.
  ///
  /// Mirrors Swift `RunAnywhere.registerModel(id:name:url:framework:modality:
  /// artifactType:memoryRequirement:supportsThinking:supportsLora:)`, which
  /// routes through the same commons factory (`rac_model_info_make_proto`).
  static Future<ModelInfo> registerModel({
    String? id,
    required String name,
    required String url,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ModelArtifactType? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
    bool supportsLora = false,
  }) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final request = RegisterModelFromUrlRequest(
      url: url,
      name: name,
      framework: framework,
      category: modality,
      source: ModelSource.MODEL_SOURCE_REMOTE,
      supportsThinking: supportsThinking,
      supportsLora: supportsLora,
    );
    // Caller-supplied id always wins; otherwise commons derives it from the
    // URL (matching Swift's `generatedModelID(from:name:)`).
    if (id != null) {
      request.id = id;
    }
    // Explicit artifact-type override wins over commons' URL inference.
    if (artifactType != null) {
      request.artifactType = artifactType;
    }
    if (memoryRequirement != null) {
      request.memoryRequiredBytes = Int64(memoryRequirement);
      request.downloadSizeBytes = Int64(memoryRequirement);
    }

    final model =
        await DartBridgeModelRegistry.instance.registerModelFromUrl(request);
    if (model == null) {
      throw SDKException.internalError(
        'rac_register_model_from_url_proto failed for model "$name"',
      );
    }
    return model;
  }

  /// Register an archive-packaged model (tar.gz / tar.bz2 / tar.xz / zip)
  /// where the caller needs to specify the on-disk layout
  /// ([ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED],
  /// [ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY], etc.) the
  /// URL-form [registerModel] cannot infer.
  ///
  /// Composes [registerModel] and then patches the resolved
  /// [ArchiveArtifact.structure] before re-saving through the registry.
  ///
  /// Mirrors Swift `RunAnywhere.registerModel(archive:structure:...)`.
  static Future<ModelInfo> registerArchiveModel({
    required String archiveUrl,
    required ArchiveStructure structure,
    String? id,
    required String name,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ArchiveType? archiveType,
    int? memoryRequirement,
    bool supportsThinking = false,
    bool supportsLora = false,
  }) async {
    // Map an explicit caller archive type to its artifact-type override.
    // When the caller passes none, leave the override unset so commons
    // infers the archive type from the URL extension (mirroring Swift's
    // `ArchiveType.from(url:)`, which lives behind
    // `rac_model_info_make_proto`).
    final ModelArtifactType? resolvedArtifactType;
    if (archiveType == null) {
      resolvedArtifactType = null;
    } else {
      switch (archiveType) {
        case ArchiveType.ARCHIVE_TYPE_ZIP:
          resolvedArtifactType =
              ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE;
          break;
        case ArchiveType.ARCHIVE_TYPE_TAR_GZ:
          resolvedArtifactType =
              ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE;
          break;
        case ArchiveType.ARCHIVE_TYPE_TAR_BZ2:
          resolvedArtifactType =
              ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE;
          break;
        case ArchiveType.ARCHIVE_TYPE_TAR_XZ:
          resolvedArtifactType =
              ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE;
          break;
        default:
          resolvedArtifactType = ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE;
      }
    }

    var model = await registerModel(
      id: id,
      name: name,
      url: archiveUrl,
      framework: framework,
      modality: modality,
      artifactType: resolvedArtifactType,
      memoryRequirement: memoryRequirement,
      supportsThinking: supportsThinking,
      supportsLora: supportsLora,
    );

    // Preserve the caller-specified layout on the archive artifact. Commons
    // infers the archive type from the URL; the nested/directory layout can
    // only come from the caller — patch and re-persist (mirroring Swift's
    // archive overload, which always carries an archive artifact with the
    // caller's structure).
    final patchedArchive =
        (model.hasArchive() ? model.archive.deepCopy() : ArchiveArtifact())
          ..structure = structure;
    if (archiveType != null) {
      patchedArchive.type = archiveType;
    }
    model = model.deepCopy()
      ..archive = patchedArchive
      ..updatedAtUnixMs = Int64(DateTime.now().millisecondsSinceEpoch);
    await DartBridgeModelRegistry.instance.saveProtoModel(model);
    return model;
  }

  /// Register a multi-file model (e.g., VLMs with a separate `mmproj`,
  /// MiniLM embedding with `vocab.txt`). Builds a [ModelInfo] in-place and
  /// persists through the registry's proto save path — no URL is involved at
  /// the model level because each [ModelFileDescriptor] carries its own URL.
  ///
  /// Mirrors Swift `RunAnywhere.registerModel(multiFile:id:name:framework:
  /// modality:memoryRequirement:contextLength:supportsThinking:source:)`.
  static Future<ModelInfo> registerMultiFileModel({
    required List<ModelFileDescriptor> files,
    required String id,
    required String name,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    int? memoryRequirement,
    int? contextLength,
    bool supportsThinking = false,
    ModelSource source = ModelSource.MODEL_SOURCE_REMOTE,
  }) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final model = ModelInfo(
      id: id,
      name: name,
      category: modality,
      format: ModelFormat.MODEL_FORMAT_UNSPECIFIED,
      framework: framework,
      multiFile: MultiFileArtifact(files: files),
      artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY,
      downloadSizeBytes: Int64(memoryRequirement ?? 0),
      memoryRequiredBytes: Int64(memoryRequirement ?? 0),
      // Mirrors Swift RunAnywhere+Storage.swift:156 —
      // `contextLength ?? (modality.requiresContextLength ? 2048 : nil)`;
      // the requires-context-length table is owned by commons.
      contextLength:
          contextLength ?? (modality.requiresContextLength ? 2048 : 0),
      supportsThinking: supportsThinking,
      source: source,
      createdAtUnixMs: Int64(DateTime.now().millisecondsSinceEpoch),
      updatedAtUnixMs: Int64(DateTime.now().millisecondsSinceEpoch),
    );

    await DartBridgeModelRegistry.instance.saveProtoModel(model);
    return model;
  }

  /// Import a stable, platform-normalized local model path into the
  /// generated registry. Also the public local-import entry point for
  /// file-picker / bookmark flows after the platform has handled sandbox
  /// access.
  ///
  /// Mirrors Swift `RunAnywhere.importModel(_:)`. Backed by
  /// `rac_model_registry_import_proto`.
  static Future<ModelImportResult> importModel(
    ModelImportRequest request,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeModelRegistry.instance.importModel(request);
  }

  // ===========================================================================
  // Storage availability (existing Flutter-specific helpers)
  // ===========================================================================

  /// Clear the SDK's Temp directory. Mirrors Swift's `cleanTempFiles()`.
  static Future<void> cleanTempFiles() async {
    if (!DartBridgeFileManager.clearTemp()) {
      throw SDKException.storageError('Failed to clean temp files');
    }
  }
}
