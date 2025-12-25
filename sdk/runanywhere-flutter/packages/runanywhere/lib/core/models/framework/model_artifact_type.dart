/// Describes how a model is packaged and what processing is needed after download.
/// This is set during model registration and drives the download/extraction behavior.
/// Matches iOS ModelArtifactType from Infrastructure/ModelManagement/Models/Domain/ModelArtifactType.swift
sealed class ModelArtifactType {
  const ModelArtifactType();

  /// A single model file (e.g., .gguf, .onnx, .mlmodel)
  /// No extraction needed - just download and use
  const factory ModelArtifactType.singleFile({
    ExpectedModelFiles expectedFiles,
  }) = SingleFileArtifact;

  /// An archive that needs extraction
  const factory ModelArtifactType.archive(
    ArchiveType archiveType, {
    required ArchiveStructure structure,
    ExpectedModelFiles expectedFiles,
  }) = ArchiveArtifact;

  /// Multiple files that need to be downloaded separately
  const factory ModelArtifactType.multiFile(
    List<ModelFileDescriptor> files,
  ) = MultiFileArtifact;

  /// Use a custom download strategy identified by string
  const factory ModelArtifactType.custom({
    required String strategyId,
  }) = CustomArtifact;

  /// Built-in model that doesn't require download
  const factory ModelArtifactType.builtIn() = BuiltInArtifact;

  // ============================================================================
  // Convenience Static Getters (match iOS pattern)
  // ============================================================================

  /// Convenience for tar.gz archive with nested directory structure.
  /// Matches iOS `.tarGzArchive(structure: .nestedDirectory)`.
  static const ModelArtifactType tarGzArchive = ArchiveArtifact(
    ArchiveType.tarGz,
    structure: ArchiveStructure.nested,
  );

  /// Convenience for tar.bz2 archive with nested directory structure.
  /// Matches iOS `.tarBz2Archive(structure: .nestedDirectory)`.
  static const ModelArtifactType tarBz2Archive = ArchiveArtifact(
    ArchiveType.tarBz2,
    structure: ArchiveStructure.nested,
  );

  /// Convenience for zip archive with nested directory structure.
  static const ModelArtifactType zipArchive = ArchiveArtifact(
    ArchiveType.zip,
    structure: ArchiveStructure.nested,
  );

  /// Convenience for single file artifact.
  static const ModelArtifactType singleFileType = SingleFileArtifact();

  /// JSON serialization
  Map<String, dynamic> toJson();

  /// Create from JSON
  static ModelArtifactType fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'singleFile':
        return SingleFileArtifact(
          expectedFiles: json['expectedFiles'] != null
              ? ExpectedModelFiles.fromJson(
                  json['expectedFiles'] as Map<String, dynamic>)
              : ExpectedModelFiles.none,
        );
      case 'archive':
        return ArchiveArtifact(
          ArchiveType.fromRawValue(json['archiveType'] as String),
          structure: ArchiveStructure.fromRawValue(json['structure'] as String),
          expectedFiles: json['expectedFiles'] != null
              ? ExpectedModelFiles.fromJson(
                  json['expectedFiles'] as Map<String, dynamic>)
              : ExpectedModelFiles.none,
        );
      case 'multiFile':
        return MultiFileArtifact(
          (json['files'] as List<dynamic>)
              .map((f) =>
                  ModelFileDescriptor.fromJson(f as Map<String, dynamic>))
              .toList(),
        );
      case 'custom':
        return CustomArtifact(strategyId: json['strategyId'] as String);
      case 'builtIn':
        return const BuiltInArtifact();
      default:
        return const BuiltInArtifact();
    }
  }
}

/// Single file artifact (no extraction needed)
class SingleFileArtifact extends ModelArtifactType {
  final ExpectedModelFiles expectedFiles;

  const SingleFileArtifact({
    this.expectedFiles = ExpectedModelFiles.none,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'singleFile',
        'expectedFiles': expectedFiles.toJson(),
      };
}

/// Archive artifact (needs extraction)
class ArchiveArtifact extends ModelArtifactType {
  final ArchiveType archiveType;
  final ArchiveStructure structure;
  final ExpectedModelFiles expectedFiles;

  const ArchiveArtifact(
    this.archiveType, {
    required this.structure,
    this.expectedFiles = ExpectedModelFiles.none,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'archive',
        'archiveType': archiveType.rawValue,
        'structure': structure.rawValue,
        'expectedFiles': expectedFiles.toJson(),
      };
}

/// Multi-file artifact (multiple separate downloads)
class MultiFileArtifact extends ModelArtifactType {
  final List<ModelFileDescriptor> files;

  const MultiFileArtifact(this.files);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'multiFile',
        'files': files.map((f) => f.toJson()).toList(),
      };
}

/// Custom artifact (uses custom download strategy)
class CustomArtifact extends ModelArtifactType {
  final String strategyId;

  const CustomArtifact({required this.strategyId});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'custom',
        'strategyId': strategyId,
      };
}

/// Built-in artifact (no download needed)
class BuiltInArtifact extends ModelArtifactType {
  const BuiltInArtifact();

  @override
  Map<String, dynamic> toJson() => {
        'type': 'builtIn',
      };
}

/// Archive type enum
/// Matches iOS ArchiveType
enum ArchiveType {
  zip('zip'),
  tarGz('tar.gz'),
  tarBz2('tar.bz2'),
  tar('tar');

  final String rawValue;
  const ArchiveType(this.rawValue);

  static ArchiveType fromRawValue(String value) {
    return ArchiveType.values.firstWhere(
      (t) => t.rawValue == value,
      orElse: () => ArchiveType.zip,
    );
  }
}

/// Archive structure enum
/// Matches iOS ArchiveStructure
enum ArchiveStructure {
  /// Single file in the archive (extract to get model file)
  flat('flat'),

  /// Files are in a subdirectory within the archive
  nested('nested'),

  /// Multiple files at root level
  multipleFlat('multipleFlat'),

  /// Complex directory structure
  directory('directory');

  final String rawValue;
  const ArchiveStructure(this.rawValue);

  static ArchiveStructure fromRawValue(String value) {
    return ArchiveStructure.values.firstWhere(
      (s) => s.rawValue == value,
      orElse: () => ArchiveStructure.flat,
    );
  }
}

/// Expected model files specification
/// Matches iOS ExpectedModelFiles
sealed class ExpectedModelFiles {
  const ExpectedModelFiles();

  /// No specific files expected
  static const ExpectedModelFiles none = NoExpectedFiles();

  /// Single file expected
  const factory ExpectedModelFiles.single(String filename) = SingleExpectedFile;

  /// Multiple files expected (for multi-file models)
  const factory ExpectedModelFiles.multiple(List<String> filenames) =
      MultipleExpectedFiles;

  /// Model stored in a directory
  const factory ExpectedModelFiles.directory(String dirname) =
      DirectoryExpectedFiles;

  /// JSON serialization
  Map<String, dynamic> toJson();

  /// Create from JSON
  static ExpectedModelFiles fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'none':
        return ExpectedModelFiles.none;
      case 'single':
        return ExpectedModelFiles.single(json['filename'] as String);
      case 'multiple':
        return ExpectedModelFiles.multiple(
          (json['filenames'] as List<dynamic>).cast<String>(),
        );
      case 'directory':
        return ExpectedModelFiles.directory(json['dirname'] as String);
      default:
        return ExpectedModelFiles.none;
    }
  }
}

class NoExpectedFiles extends ExpectedModelFiles {
  const NoExpectedFiles();

  @override
  Map<String, dynamic> toJson() => {'type': 'none'};
}

class SingleExpectedFile extends ExpectedModelFiles {
  final String filename;
  const SingleExpectedFile(this.filename);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'single',
        'filename': filename,
      };
}

class MultipleExpectedFiles extends ExpectedModelFiles {
  final List<String> filenames;
  const MultipleExpectedFiles(this.filenames);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'multiple',
        'filenames': filenames,
      };
}

class DirectoryExpectedFiles extends ExpectedModelFiles {
  final String dirname;
  const DirectoryExpectedFiles(this.dirname);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'directory',
        'dirname': dirname,
      };
}

/// Descriptor for individual model files in a multi-file model
/// Matches iOS ModelFileDescriptor
class ModelFileDescriptor {
  /// Relative path within the model directory
  final String relativePath;

  /// Download URL for this file
  final Uri downloadURL;

  /// Expected file size in bytes
  final int? size;

  /// SHA256 hash for verification
  final String? sha256;

  /// Whether this file is required for the model to work
  final bool required;

  const ModelFileDescriptor({
    required this.relativePath,
    required this.downloadURL,
    this.size,
    this.sha256,
    this.required = true,
  });

  Map<String, dynamic> toJson() => {
        'relativePath': relativePath,
        'downloadURL': downloadURL.toString(),
        if (size != null) 'size': size,
        if (sha256 != null) 'sha256': sha256,
        'required': required,
      };

  factory ModelFileDescriptor.fromJson(Map<String, dynamic> json) {
    return ModelFileDescriptor(
      relativePath: json['relativePath'] as String,
      downloadURL: Uri.parse(json['downloadURL'] as String),
      size: json['size'] as int?,
      sha256: json['sha256'] as String?,
      required: json['required'] as bool? ?? true,
    );
  }
}
