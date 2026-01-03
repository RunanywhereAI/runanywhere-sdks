/// Model Types
///
/// Public types for model management.
/// Matches Swift ModelTypes.swift from Public/Extensions/Models/
/// These are thin wrappers over C++ types in rac_model_types.h
library model_types;

import 'dart:io';

// MARK: - Model Source

/// Source of model data (where the model info came from)
enum ModelSource {
  /// Model info came from remote API (backend model catalog)
  remote('remote'),

  /// Model info was provided locally via SDK input (addModel calls)
  local('local');

  final String rawValue;
  const ModelSource(this.rawValue);

  static ModelSource fromRawValue(String value) {
    return ModelSource.values.firstWhere(
      (s) => s.rawValue == value,
      orElse: () => ModelSource.remote,
    );
  }
}

// MARK: - Model Format

/// Model formats supported
enum ModelFormat {
  onnx('onnx'),
  ort('ort'),
  gguf('gguf'),
  bin('bin'),
  unknown('unknown');

  final String rawValue;
  const ModelFormat(this.rawValue);

  static ModelFormat fromRawValue(String value) {
    return ModelFormat.values.firstWhere(
      (f) => f.rawValue == value.toLowerCase(),
      orElse: () => ModelFormat.unknown,
    );
  }
}

// MARK: - Model Category

/// Defines the category/type of a model based on its input/output modality
enum ModelCategory {
  language('language', 'Language Model'),
  speechRecognition('speech-recognition', 'Speech Recognition'),
  speechSynthesis('speech-synthesis', 'Text-to-Speech'),
  vision('vision', 'Vision Model'),
  imageGeneration('image-generation', 'Image Generation'),
  multimodal('multimodal', 'Multimodal'),
  audio('audio', 'Audio Processing');

  final String rawValue;
  final String displayName;

  const ModelCategory(this.rawValue, this.displayName);

  /// Create from raw string value
  static ModelCategory? fromRawValue(String value) {
    return ModelCategory.values.cast<ModelCategory?>().firstWhere(
          (c) => c?.rawValue == value,
          orElse: () => null,
        );
  }

  /// Whether this category typically requires context length
  /// Note: C++ equivalent is rac_model_category_requires_context_length()
  bool get requiresContextLength {
    switch (this) {
      case ModelCategory.language:
      case ModelCategory.multimodal:
        return true;
      default:
        return false;
    }
  }

  /// Whether this category typically supports thinking/reasoning
  /// Note: C++ equivalent is rac_model_category_supports_thinking()
  bool get supportsThinking {
    switch (this) {
      case ModelCategory.language:
      case ModelCategory.multimodal:
        return true;
      default:
        return false;
    }
  }
}

// MARK: - Inference Framework

/// Supported inference frameworks/runtimes for executing models
enum InferenceFramework {
  // Model-based frameworks
  onnx('ONNX', 'ONNX Runtime', 'onnx'),
  llamaCpp('LlamaCpp', 'llama.cpp', 'llama_cpp'),
  foundationModels('FoundationModels', 'Foundation Models', 'foundation_models'),
  systemTTS('SystemTTS', 'System TTS', 'system_tts'),
  fluidAudio('FluidAudio', 'FluidAudio', 'fluid_audio'),

  // Special cases
  builtIn('BuiltIn', 'Built-in', 'built_in'),
  none('None', 'None', 'none'),
  unknown('Unknown', 'Unknown', 'unknown');

  final String rawValue;
  final String displayName;
  final String analyticsKey;

  const InferenceFramework(this.rawValue, this.displayName, this.analyticsKey);

  static InferenceFramework fromRawValue(String value) {
    final lowercased = value.toLowerCase();
    return InferenceFramework.values.firstWhere(
      (f) => f.rawValue.toLowerCase() == lowercased ||
             f.analyticsKey == lowercased,
      orElse: () => InferenceFramework.unknown,
    );
  }
}

// MARK: - Archive Types

/// Supported archive formats for model packaging
enum ArchiveType {
  zip('zip'),
  tarBz2('tar.bz2'),
  tarGz('tar.gz'),
  tarXz('tar.xz');

  final String rawValue;
  const ArchiveType(this.rawValue);

  /// File extension for this archive type
  String get fileExtension => rawValue;

  /// Detect archive type from URL path
  static ArchiveType? fromPath(String path) {
    final lowered = path.toLowerCase();
    if (lowered.endsWith('.tar.bz2') || lowered.endsWith('.tbz2')) {
      return ArchiveType.tarBz2;
    } else if (lowered.endsWith('.tar.gz') || lowered.endsWith('.tgz')) {
      return ArchiveType.tarGz;
    } else if (lowered.endsWith('.tar.xz') || lowered.endsWith('.txz')) {
      return ArchiveType.tarXz;
    } else if (lowered.endsWith('.zip')) {
      return ArchiveType.zip;
    }
    return null;
  }
}

/// Describes the internal structure of an archive after extraction
enum ArchiveStructure {
  singleFileNested('singleFileNested'),
  directoryBased('directoryBased'),
  nestedDirectory('nestedDirectory'),
  unknown('unknown');

  final String rawValue;
  const ArchiveStructure(this.rawValue);
}

// MARK: - Expected Model Files

/// Describes what files are expected after model extraction/download
class ExpectedModelFiles {
  final List<String> requiredPatterns;
  final List<String> optionalPatterns;
  final String? description;

  const ExpectedModelFiles({
    this.requiredPatterns = const [],
    this.optionalPatterns = const [],
    this.description,
  });

  static const ExpectedModelFiles none = ExpectedModelFiles();

  Map<String, dynamic> toJson() => {
        'requiredPatterns': requiredPatterns,
        'optionalPatterns': optionalPatterns,
        if (description != null) 'description': description,
      };

  factory ExpectedModelFiles.fromJson(Map<String, dynamic> json) {
    return ExpectedModelFiles(
      requiredPatterns: (json['requiredPatterns'] as List<dynamic>?)
              ?.cast<String>() ??
          [],
      optionalPatterns: (json['optionalPatterns'] as List<dynamic>?)
              ?.cast<String>() ??
          [],
      description: json['description'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpectedModelFiles &&
          requiredPatterns.length == other.requiredPatterns.length &&
          optionalPatterns.length == other.optionalPatterns.length;

  @override
  int get hashCode => Object.hash(requiredPatterns.length, optionalPatterns.length);
}

/// Describes a file that needs to be downloaded as part of a multi-file model
class ModelFileDescriptor {
  final String relativePath;
  final String destinationPath;
  final bool isRequired;

  const ModelFileDescriptor({
    required this.relativePath,
    required this.destinationPath,
    this.isRequired = true,
  });

  Map<String, dynamic> toJson() => {
        'relativePath': relativePath,
        'destinationPath': destinationPath,
        'isRequired': isRequired,
      };

  factory ModelFileDescriptor.fromJson(Map<String, dynamic> json) {
    return ModelFileDescriptor(
      relativePath: json['relativePath'] as String,
      destinationPath: json['destinationPath'] as String,
      isRequired: json['isRequired'] as bool? ?? true,
    );
  }
}

// MARK: - Model Artifact Type

/// Describes how a model is packaged and what processing is needed after download
sealed class ModelArtifactType {
  const ModelArtifactType();

  bool get requiresExtraction => false;
  bool get requiresDownload => true;
  ExpectedModelFiles get expectedFiles => ExpectedModelFiles.none;
  String get displayName;

  Map<String, dynamic> toJson();

  factory ModelArtifactType.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'singleFile':
        final expected = json['expectedFiles'] != null
            ? ExpectedModelFiles.fromJson(
                json['expectedFiles'] as Map<String, dynamic>)
            : ExpectedModelFiles.none;
        return SingleFileArtifact(expectedFiles: expected);
      case 'archive':
        return ArchiveArtifact(
          archiveType: ArchiveType.values.firstWhere(
            (t) => t.rawValue == json['archiveType'],
            orElse: () => ArchiveType.zip,
          ),
          structure: ArchiveStructure.values.firstWhere(
            (s) => s.rawValue == json['structure'],
            orElse: () => ArchiveStructure.unknown,
          ),
          expectedFiles: json['expectedFiles'] != null
              ? ExpectedModelFiles.fromJson(
                  json['expectedFiles'] as Map<String, dynamic>)
              : ExpectedModelFiles.none,
        );
      case 'multiFile':
        return MultiFileArtifact(
          files: (json['files'] as List<dynamic>)
              .map((f) =>
                  ModelFileDescriptor.fromJson(f as Map<String, dynamic>))
              .toList(),
        );
      case 'custom':
        return CustomArtifact(strategyId: json['strategyId'] as String);
      case 'builtIn':
        return const BuiltInArtifact();
      default:
        return const SingleFileArtifact();
    }
  }

  /// Infer artifact type from download URL
  static ModelArtifactType infer(Uri? url, ModelFormat format) {
    if (url == null) return const SingleFileArtifact();
    final archiveType = ArchiveType.fromPath(url.path);
    if (archiveType != null) {
      return ArchiveArtifact(
        archiveType: archiveType,
        structure: ArchiveStructure.unknown,
      );
    }
    return const SingleFileArtifact();
  }
}

class SingleFileArtifact extends ModelArtifactType {
  @override
  final ExpectedModelFiles expectedFiles;

  const SingleFileArtifact({this.expectedFiles = ExpectedModelFiles.none});

  @override
  String get displayName => 'Single File';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'singleFile',
        if (expectedFiles != ExpectedModelFiles.none)
          'expectedFiles': expectedFiles.toJson(),
      };
}

class ArchiveArtifact extends ModelArtifactType {
  final ArchiveType archiveType;
  final ArchiveStructure structure;
  @override
  final ExpectedModelFiles expectedFiles;

  const ArchiveArtifact({
    required this.archiveType,
    required this.structure,
    this.expectedFiles = ExpectedModelFiles.none,
  });

  @override
  bool get requiresExtraction => true;

  @override
  String get displayName => '${archiveType.rawValue.toUpperCase()} Archive';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'archive',
        'archiveType': archiveType.rawValue,
        'structure': structure.rawValue,
        if (expectedFiles != ExpectedModelFiles.none)
          'expectedFiles': expectedFiles.toJson(),
      };
}

class MultiFileArtifact extends ModelArtifactType {
  final List<ModelFileDescriptor> files;

  const MultiFileArtifact({required this.files});

  @override
  String get displayName => 'Multi-File (${files.length} files)';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'multiFile',
        'files': files.map((f) => f.toJson()).toList(),
      };
}

class CustomArtifact extends ModelArtifactType {
  final String strategyId;

  const CustomArtifact({required this.strategyId});

  @override
  String get displayName => 'Custom ($strategyId)';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'custom',
        'strategyId': strategyId,
      };
}

class BuiltInArtifact extends ModelArtifactType {
  const BuiltInArtifact();

  @override
  bool get requiresDownload => false;

  @override
  String get displayName => 'Built-in';

  @override
  Map<String, dynamic> toJson() => {'type': 'builtIn'};
}

// MARK: - Thinking Tag Pattern

/// Pattern for extracting thinking tags from model output
class ThinkingTagPattern {
  final String openTag;
  final String closeTag;

  const ThinkingTagPattern({
    required this.openTag,
    required this.closeTag,
  });

  static const ThinkingTagPattern defaultPattern = ThinkingTagPattern(
    openTag: '<think>',
    closeTag: '</think>',
  );

  Map<String, dynamic> toJson() => {
        'openTag': openTag,
        'closeTag': closeTag,
      };

  factory ThinkingTagPattern.fromJson(Map<String, dynamic> json) {
    return ThinkingTagPattern(
      openTag: json['openTag'] as String? ?? '<think>',
      closeTag: json['closeTag'] as String? ?? '</think>',
    );
  }
}

// MARK: - Model Info

/// Information about a model - in-memory entity
/// Matches Swift ModelInfo from Public/Extensions/Models/ModelTypes.swift
class ModelInfo {
  // Essential identifiers
  final String id;
  final String name;
  final ModelCategory category;

  // Format and location
  final ModelFormat format;
  final Uri? downloadURL;
  Uri? localPath;

  // Artifact type
  final ModelArtifactType artifactType;

  // Size information
  final int? downloadSize;

  // Framework
  final InferenceFramework framework;

  // Model-specific capabilities
  final int? contextLength;
  final bool supportsThinking;
  final ThinkingTagPattern? thinkingPattern;

  // Optional metadata
  final String? description;

  // Tracking fields
  final ModelSource source;
  final DateTime createdAt;
  DateTime updatedAt;

  ModelInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.format,
    required this.framework,
    this.downloadURL,
    this.localPath,
    ModelArtifactType? artifactType,
    this.downloadSize,
    int? contextLength,
    bool supportsThinking = false,
    ThinkingTagPattern? thinkingPattern,
    this.description,
    ModelSource? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : artifactType =
            artifactType ?? ModelArtifactType.infer(downloadURL, format),
        contextLength = category.requiresContextLength
            ? (contextLength ?? 2048)
            : contextLength,
        supportsThinking = category.supportsThinking ? supportsThinking : false,
        thinkingPattern = (category.supportsThinking && supportsThinking)
            ? (thinkingPattern ?? ThinkingTagPattern.defaultPattern)
            : null,
        source = source ?? ModelSource.remote,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Whether this model is downloaded and available locally
  bool get isDownloaded {
    final path = localPath;
    if (path == null) return false;

    // Built-in models are always available
    if (path.scheme == 'builtin') return true;

    // Check if file or directory exists
    final localFile = File(path.toFilePath());
    final localDir = Directory(path.toFilePath());

    if (localFile.existsSync()) return true;

    if (localDir.existsSync()) {
      final contents = localDir.listSync();
      return contents.isNotEmpty;
    }

    return false;
  }

  /// Whether this model is available for use
  bool get isAvailable => isDownloaded;

  /// Whether this is a built-in platform model
  bool get isBuiltIn {
    if (artifactType is BuiltInArtifact) return true;
    if (localPath?.scheme == 'builtin') return true;
    return framework == InferenceFramework.foundationModels ||
        framework == InferenceFramework.systemTTS;
  }

  /// JSON serialization
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.rawValue,
        'format': format.rawValue,
        if (downloadURL != null) 'downloadURL': downloadURL.toString(),
        if (localPath != null) 'localPath': localPath.toString(),
        'artifactType': artifactType.toJson(),
        if (downloadSize != null) 'downloadSize': downloadSize,
        'framework': framework.rawValue,
        if (contextLength != null) 'contextLength': contextLength,
        'supportsThinking': supportsThinking,
        if (thinkingPattern != null) 'thinkingPattern': thinkingPattern!.toJson(),
        if (description != null) 'description': description,
        'source': source.rawValue,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      category: ModelCategory.fromRawValue(json['category'] as String) ??
          ModelCategory.language,
      format: ModelFormat.fromRawValue(json['format'] as String? ?? 'unknown'),
      framework: InferenceFramework.fromRawValue(
          json['framework'] as String? ?? 'unknown'),
      downloadURL: json['downloadURL'] != null
          ? Uri.parse(json['downloadURL'] as String)
          : null,
      localPath: json['localPath'] != null
          ? Uri.parse(json['localPath'] as String)
          : null,
      artifactType: json['artifactType'] != null
          ? ModelArtifactType.fromJson(
              json['artifactType'] as Map<String, dynamic>)
          : null,
      downloadSize: json['downloadSize'] as int?,
      contextLength: json['contextLength'] as int?,
      supportsThinking: json['supportsThinking'] as bool? ?? false,
      thinkingPattern: json['thinkingPattern'] != null
          ? ThinkingTagPattern.fromJson(
              json['thinkingPattern'] as Map<String, dynamic>)
          : null,
      description: json['description'] as String?,
      source: ModelSource.fromRawValue(json['source'] as String? ?? 'remote'),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  /// Copy with modifications
  ModelInfo copyWith({
    String? id,
    String? name,
    ModelCategory? category,
    ModelFormat? format,
    InferenceFramework? framework,
    Uri? downloadURL,
    Uri? localPath,
    ModelArtifactType? artifactType,
    int? downloadSize,
    int? contextLength,
    bool? supportsThinking,
    ThinkingTagPattern? thinkingPattern,
    String? description,
    ModelSource? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ModelInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      format: format ?? this.format,
      framework: framework ?? this.framework,
      downloadURL: downloadURL ?? this.downloadURL,
      localPath: localPath ?? this.localPath,
      artifactType: artifactType ?? this.artifactType,
      downloadSize: downloadSize ?? this.downloadSize,
      contextLength: contextLength ?? this.contextLength,
      supportsThinking: supportsThinking ?? this.supportsThinking,
      thinkingPattern: thinkingPattern ?? this.thinkingPattern,
      description: description ?? this.description,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelInfo && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ModelInfo(id: $id, name: $name, category: $category)';
}
