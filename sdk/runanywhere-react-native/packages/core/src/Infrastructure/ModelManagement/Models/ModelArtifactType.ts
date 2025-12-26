/**
 * ModelArtifactType.ts
 * RunAnywhere SDK
 *
 * Describes how a model is packaged and what processing it requires after download.
 * Matches iOS: Infrastructure/ModelManagement/Models/Domain/ModelArtifactType.swift
 */

// MARK: - Archive Types

/**
 * Supported archive formats for model packaging
 */
export enum ArchiveType {
  Zip = 'zip',
  TarBz2 = 'tar.bz2',
  TarGz = 'tar.gz',
  TarXz = 'tar.xz',
}

/**
 * Get the file extension for an archive type
 */
export function getArchiveTypeExtension(type: ArchiveType): string {
  return type;
}

/**
 * Detect archive type from a URL or path
 */
export function detectArchiveType(url: string): ArchiveType | undefined {
  const path = url.toLowerCase();

  if (path.endsWith('.tar.bz2') || path.endsWith('.tbz2')) {
    return ArchiveType.TarBz2;
  }
  if (path.endsWith('.tar.gz') || path.endsWith('.tgz')) {
    return ArchiveType.TarGz;
  }
  if (path.endsWith('.tar.xz') || path.endsWith('.txz')) {
    return ArchiveType.TarXz;
  }
  if (path.endsWith('.zip')) {
    return ArchiveType.Zip;
  }

  return undefined;
}

// MARK: - Archive Structure

/**
 * Describes the internal structure of an archive after extraction
 */
export enum ArchiveStructure {
  /** Archive contains a single model file at root or nested in one directory */
  SingleFileNested = 'singleFileNested',
  /** Archive extracts to a directory containing multiple files */
  DirectoryBased = 'directoryBased',
  /** Archive has a subdirectory structure (e.g., extracts to subfolder) */
  NestedDirectory = 'nestedDirectory',
  /** Unknown structure - will be detected after extraction */
  Unknown = 'unknown',
}

// MARK: - Expected Model Files

/**
 * Describes what files are expected after model extraction/download.
 * Used for validation and to understand model requirements.
 */
export interface ExpectedModelFiles {
  /**
   * File patterns that must be present (e.g., "*.onnx", "encoder*.onnx")
   */
  requiredPatterns: string[];

  /**
   * File patterns that may be present but are optional
   */
  optionalPatterns: string[];

  /**
   * Description of the model files for documentation
   */
  description?: string;
}

/**
 * Default empty expected model files
 */
export const EXPECTED_MODEL_FILES_NONE: ExpectedModelFiles = {
  requiredPatterns: [],
  optionalPatterns: [],
};

/**
 * Create expected model files with optional properties
 */
export function createExpectedModelFiles(
  options: Partial<ExpectedModelFiles> = {}
): ExpectedModelFiles {
  return {
    requiredPatterns: options.requiredPatterns ?? [],
    optionalPatterns: options.optionalPatterns ?? [],
    description: options.description,
  };
}

// MARK: - Model File Descriptor

/**
 * Describes a file that needs to be downloaded as part of a multi-file model
 */
export interface ModelFileDescriptor {
  /**
   * Relative path from base URL to this file
   */
  relativePath: string;

  /**
   * Destination path relative to model folder
   */
  destinationPath: string;

  /**
   * Whether this file is required (vs optional)
   * @default true
   */
  isRequired: boolean;
}

/**
 * Create a model file descriptor
 */
export function createModelFileDescriptor(
  relativePath: string,
  destinationPath: string,
  isRequired = true
): ModelFileDescriptor {
  return {
    relativePath,
    destinationPath,
    isRequired,
  };
}

// MARK: - Model Artifact Type

/**
 * Model artifact type discriminator
 */
export enum ModelArtifactTypeKind {
  /** A single model file (e.g., .gguf, .onnx, .mlmodel) */
  SingleFile = 'singleFile',
  /** An archive that needs extraction */
  Archive = 'archive',
  /** Multiple files that need to be downloaded separately */
  MultiFile = 'multiFile',
  /** Use a custom download strategy identified by string */
  Custom = 'custom',
  /** Built-in model that doesn't require download */
  BuiltIn = 'builtIn',
}

/**
 * Describes how a model is packaged and what processing is needed after download.
 * This is set during model registration and drives the download/extraction behavior.
 */
export type ModelArtifactType =
  | {
      kind: ModelArtifactTypeKind.SingleFile;
      expectedFiles: ExpectedModelFiles;
    }
  | {
      kind: ModelArtifactTypeKind.Archive;
      archiveType: ArchiveType;
      structure: ArchiveStructure;
      expectedFiles: ExpectedModelFiles;
    }
  | {
      kind: ModelArtifactTypeKind.MultiFile;
      files: ModelFileDescriptor[];
    }
  | {
      kind: ModelArtifactTypeKind.Custom;
      strategyId: string;
    }
  | {
      kind: ModelArtifactTypeKind.BuiltIn;
    };

// MARK: - Factory Methods

/**
 * Create a single file artifact type
 */
export function singleFileArtifact(
  expectedFiles: ExpectedModelFiles = EXPECTED_MODEL_FILES_NONE
): ModelArtifactType {
  return {
    kind: ModelArtifactTypeKind.SingleFile,
    expectedFiles,
  };
}

/**
 * Create an archive artifact type
 */
export function archiveArtifact(
  archiveType: ArchiveType,
  structure: ArchiveStructure = ArchiveStructure.Unknown,
  expectedFiles: ExpectedModelFiles = EXPECTED_MODEL_FILES_NONE
): ModelArtifactType {
  return {
    kind: ModelArtifactTypeKind.Archive,
    archiveType,
    structure,
    expectedFiles,
  };
}

/**
 * Create a ZIP archive artifact type
 */
export function zipArchiveArtifact(
  structure: ArchiveStructure = ArchiveStructure.DirectoryBased,
  expectedFiles: ExpectedModelFiles = EXPECTED_MODEL_FILES_NONE
): ModelArtifactType {
  return archiveArtifact(ArchiveType.Zip, structure, expectedFiles);
}

/**
 * Create a tar.bz2 archive artifact type
 */
export function tarBz2ArchiveArtifact(
  structure: ArchiveStructure = ArchiveStructure.NestedDirectory,
  expectedFiles: ExpectedModelFiles = EXPECTED_MODEL_FILES_NONE
): ModelArtifactType {
  return archiveArtifact(ArchiveType.TarBz2, structure, expectedFiles);
}

/**
 * Create a tar.gz archive artifact type
 */
export function tarGzArchiveArtifact(
  structure: ArchiveStructure = ArchiveStructure.NestedDirectory,
  expectedFiles: ExpectedModelFiles = EXPECTED_MODEL_FILES_NONE
): ModelArtifactType {
  return archiveArtifact(ArchiveType.TarGz, structure, expectedFiles);
}

/**
 * Create a multi-file artifact type
 */
export function multiFileArtifact(
  files: ModelFileDescriptor[]
): ModelArtifactType {
  return {
    kind: ModelArtifactTypeKind.MultiFile,
    files,
  };
}

/**
 * Create a custom artifact type
 */
export function customArtifact(strategyId: string): ModelArtifactType {
  return {
    kind: ModelArtifactTypeKind.Custom,
    strategyId,
  };
}

/**
 * Create a built-in artifact type
 */
export function builtInArtifact(): ModelArtifactType {
  return {
    kind: ModelArtifactTypeKind.BuiltIn,
  };
}

/**
 * Infer artifact type from download URL
 */
export function inferArtifactType(url?: string): ModelArtifactType {
  if (!url) {
    return singleFileArtifact();
  }

  const archiveType = detectArchiveType(url);
  if (archiveType) {
    return archiveArtifact(archiveType, ArchiveStructure.Unknown);
  }

  return singleFileArtifact();
}

// MARK: - Utility Functions

/**
 * Check if artifact type requires extraction after download
 */
export function requiresExtraction(artifactType: ModelArtifactType): boolean {
  return artifactType.kind === ModelArtifactTypeKind.Archive;
}

/**
 * Check if artifact type requires downloading
 */
export function requiresDownload(artifactType: ModelArtifactType): boolean {
  return artifactType.kind !== ModelArtifactTypeKind.BuiltIn;
}

/**
 * Get expected files for an artifact type
 */
export function getExpectedFiles(
  artifactType: ModelArtifactType
): ExpectedModelFiles {
  if (
    artifactType.kind === ModelArtifactTypeKind.SingleFile ||
    artifactType.kind === ModelArtifactTypeKind.Archive
  ) {
    return artifactType.expectedFiles;
  }
  return EXPECTED_MODEL_FILES_NONE;
}

/**
 * Get human-readable display name for artifact type
 */
export function getArtifactTypeDisplayName(
  artifactType: ModelArtifactType
): string {
  switch (artifactType.kind) {
    case ModelArtifactTypeKind.SingleFile:
      return 'Single File';
    case ModelArtifactTypeKind.Archive:
      return `${artifactType.archiveType.toUpperCase()} Archive`;
    case ModelArtifactTypeKind.MultiFile:
      return `Multi-File (${artifactType.files.length} files)`;
    case ModelArtifactTypeKind.Custom:
      return `Custom (${artifactType.strategyId})`;
    case ModelArtifactTypeKind.BuiltIn:
      return 'Built-in';
  }
}
