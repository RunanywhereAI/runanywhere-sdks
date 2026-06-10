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
  /// download URL. Builds a complete [ModelInfo] in-place — every capability
  /// field (id, framework, category, memory/download size, thinking, LoRA,
  /// artifact type) carried on the caller's arguments — and persists it
  /// through the registry's proto save path in a single save. The save path
  /// (`rac_model_registry_register_proto`) round-trips every field, so no
  /// from-url build-then-patch-then-resave dance is required.
  ///
  /// Mirrors Swift `RunAnywhere.registerModel(id:name:url:framework:modality:
  /// artifactType:memoryRequirement:supportsThinking:supportsLora:)`.
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

    final nowMs = Int64(DateTime.now().millisecondsSinceEpoch);
    final model = ModelInfo(
      id: id ?? _deriveModelId(name),
      name: name,
      category: modality,
      format: ModelFormat.MODEL_FORMAT_UNSPECIFIED,
      framework: framework,
      downloadUrl: url,
      singleFile: SingleFileArtifact(),
      artifactType:
          artifactType ?? ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE,
      downloadSizeBytes: Int64(memoryRequirement ?? 0),
      memoryRequiredBytes: Int64(memoryRequirement ?? 0),
      contextLength: _defaultContextLength(modality),
      supportsThinking: supportsThinking,
      supportsLora: supportsLora,
      source: ModelSource.MODEL_SOURCE_REMOTE,
      createdAtUnixMs: nowMs,
      updatedAtUnixMs: nowMs,
    );

    await DartBridgeModelRegistry.instance.saveProtoModel(model);
    return model;
  }

  /// Derive a stable, slug-style model id from a display [name] when the
  /// caller does not supply one explicitly.
  static String _deriveModelId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'model' : slug;
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

    // Preserve the structure on the archive artifact. The URL-form inferred
    // artifact only captures the archive type, not the nested/directory
    // layout — patch and re-persist (mirroring Swift's archive overload).
    if (!model.hasArchive()) {
      return model;
    }
    final patchedArchive = model.archive.deepCopy()..structure = structure;
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
      contextLength: contextLength ?? _defaultContextLength(modality),
      supportsThinking: supportsThinking,
      source: source,
      createdAtUnixMs: Int64(DateTime.now().millisecondsSinceEpoch),
      updatedAtUnixMs: Int64(DateTime.now().millisecondsSinceEpoch),
    );

    await DartBridgeModelRegistry.instance.saveProtoModel(model);
    return model;
  }

  static int _defaultContextLength(ModelCategory modality) {
    switch (modality) {
      case ModelCategory.MODEL_CATEGORY_LANGUAGE:
      case ModelCategory.MODEL_CATEGORY_VISION:
      case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
        return 2048;
      default:
        return 0;
    }
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
