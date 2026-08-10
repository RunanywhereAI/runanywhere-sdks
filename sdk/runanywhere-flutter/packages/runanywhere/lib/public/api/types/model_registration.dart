// SPDX-License-Identifier: Apache-2.0
//
// Registration and filter inputs for `RunAnywhere.models`.

import 'package:runanywhere/generated/model_types.pb.dart'
    show ModelFileDescriptor, ModelQuery;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show
        ArchiveStructure,
        ArchiveType,
        InferenceFramework,
        ModelArtifactType,
        ModelCategory,
        ModelSource;

/// How a model's files are laid out at its source.
enum ModelArtifactKind {
  /// One downloadable weight file.
  singleFile,

  /// One downloadable archive that unpacks into a model directory.
  archive,

  /// Several files that must all be present.
  multiFile,
}

/// A model to add to the registry: single file, archive, or multi-file.
class ModelRegistration {
  const ModelRegistration._({
    required this.kind,
    required this.name,
    required this.framework,
    required this.category,
    this.id,
    this.url,
    this.archiveStructure,
    this.archiveType,
    this.files = const <ModelFileDescriptor>[],
    this.artifactType,
    this.memoryRequirementBytes,
    this.downloadSizeBytes,
    this.contextLength,
    this.supportsThinking = false,
    this.supportsLora = false,
    this.source = ModelSource.MODEL_SOURCE_REMOTE,
    this.description,
    this.cuaProfile,
  });

  /// Register one downloadable weight file.
  factory ModelRegistration.url({
    required String name,
    required String url,
    required InferenceFramework framework,
    String? id,
    ModelCategory category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ModelArtifactType? artifactType,
    int? memoryRequirementBytes,
    int? downloadSizeBytes,
    int? contextLength,
    ModelSource source = ModelSource.MODEL_SOURCE_REMOTE,
    String? description,
    bool supportsThinking = false,
    bool supportsLora = false,
    String? cuaProfile,
  }) => ModelRegistration._(
    kind: ModelArtifactKind.singleFile,
    name: name,
    framework: framework,
    category: category,
    id: id,
    url: url,
    artifactType: artifactType,
    memoryRequirementBytes: memoryRequirementBytes,
    downloadSizeBytes: downloadSizeBytes,
    contextLength: contextLength,
    source: source,
    description: description,
    supportsThinking: supportsThinking,
    supportsLora: supportsLora,
    cuaProfile: cuaProfile,
  );

  /// Register an archive that unpacks into a model directory.
  factory ModelRegistration.archive({
    required String name,
    required String url,
    required ArchiveStructure structure,
    required InferenceFramework framework,
    String? id,
    ModelCategory category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ArchiveType? archiveType,
    int? memoryRequirementBytes,
    bool supportsThinking = false,
    bool supportsLora = false,
    String? cuaProfile,
  }) => ModelRegistration._(
    kind: ModelArtifactKind.archive,
    name: name,
    framework: framework,
    category: category,
    id: id,
    url: url,
    archiveStructure: structure,
    archiveType: archiveType,
    memoryRequirementBytes: memoryRequirementBytes,
    supportsThinking: supportsThinking,
    supportsLora: supportsLora,
    cuaProfile: cuaProfile,
  );

  /// Register several files that together make up one model.
  factory ModelRegistration.multiFile({
    required String id,
    required String name,
    required List<ModelFileDescriptor> files,
    required InferenceFramework framework,
    ModelCategory category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    int? memoryRequirementBytes,
    int? downloadSizeBytes,
    int? contextLength,
    bool supportsThinking = false,
    ModelSource source = ModelSource.MODEL_SOURCE_REMOTE,
    String? cuaProfile,
  }) => ModelRegistration._(
    kind: ModelArtifactKind.multiFile,
    name: name,
    framework: framework,
    category: category,
    id: id,
    files: files,
    memoryRequirementBytes: memoryRequirementBytes,
    downloadSizeBytes: downloadSizeBytes,
    contextLength: contextLength,
    supportsThinking: supportsThinking,
    source: source,
    cuaProfile: cuaProfile,
  );

  /// Which registration shape this is.
  final ModelArtifactKind kind;

  /// Display name.
  final String name;

  /// Engine that will run the model.
  final InferenceFramework framework;

  /// Modality the model serves.
  final ModelCategory category;

  /// Registry id. Derived from [name] when omitted.
  final String? id;

  /// Download URL for single-file and archive registrations.
  final String? url;

  /// On-disk layout the archive unpacks into.
  final ArchiveStructure? archiveStructure;

  /// Archive compression, when it cannot be inferred from [url].
  final ArchiveType? archiveType;

  /// Files for a multi-file registration.
  final List<ModelFileDescriptor> files;

  /// Artifact type hint for single-file registrations.
  final ModelArtifactType? artifactType;

  /// Resident memory the model needs.
  final int? memoryRequirementBytes;

  /// Artifact bytes used for download planning and validation.
  final int? downloadSizeBytes;

  /// Context window the model supports.
  final int? contextLength;

  /// True when the model emits chain-of-thought.
  final bool supportsThinking;

  /// True when LoRA adapters may be applied.
  final bool supportsLora;

  /// Where the model comes from.
  final ModelSource source;

  /// Optional catalog description preserved on the registry entry.
  final String? description;

  /// Computer-Use-Agent profile id (e.g. `'fara'`) for a CUA-capable model.
  /// Lands on `ModelInfo.cuaProfile` so callers can discover which
  /// registered models are drivable through `RunAnywhere.cua`.
  final String? cuaProfile;
}

/// Narrows `models.list` to a subset of the registry.
class ModelFilter {
  /// Filter by any combination of modality, engine, and download state.
  const ModelFilter({
    this.category,
    this.framework,
    this.downloadedOnly,
    this.searchQuery,
  });

  /// Keep only models serving this modality.
  final ModelCategory? category;

  /// Keep only models runnable by this engine.
  final InferenceFramework? framework;

  /// True keeps only models already on disk.
  final bool? downloadedOnly;

  /// Free-text match against id and name.
  final String? searchQuery;

  /// Build the generated registry query.
  ModelQuery toProto() {
    final query = ModelQuery();
    if (category != null) query.category = category!;
    if (framework != null) query.framework = framework!;
    if (downloadedOnly != null) query.downloadedOnly = downloadedOnly!;
    final search = searchQuery;
    if (search != null && search.isNotEmpty) query.searchQuery = search;
    return query;
  }
}
