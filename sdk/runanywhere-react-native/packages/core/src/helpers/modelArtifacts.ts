/**
 * helpers/modelArtifacts
 *
 * Swift-parity conveniences for generated model artifact proto types.
 */

import {
  ArchiveArtifact,
  ArchiveStructure,
  ArchiveType,
  InferenceFramework,
  ModelArtifactType,
  ModelFileDescriptor,
  ModelFileRole,
  type CurrentModelResult,
  type ExpectedModelFiles,
  type ModelInfo,
  type ModelLoadResult,
} from '@runanywhere/proto-ts/model_types';

export {
  ArchiveArtifact,
  ArchiveStructure,
  ArchiveType,
  ModelArtifactType,
  ModelFileDescriptor,
  ModelFileRole,
  type CurrentModelResult,
  type ExpectedModelFiles,
  type ModelInfo,
  type ModelLoadResult,
} from '@runanywhere/proto-ts/model_types';

export function emptyExpectedModelFiles(): ExpectedModelFiles {
  return { files: [], requiredPatterns: [], optionalPatterns: [] };
}

export function isEmptyExpectedModelFiles(
  manifest: ExpectedModelFiles | undefined
): boolean {
  return (
    !manifest ||
    (manifest.files.length === 0 &&
      !manifest.rootDirectory &&
      manifest.requiredPatterns.length === 0 &&
      manifest.optionalPatterns.length === 0 &&
      !manifest.description)
  );
}

export function modelFileDescriptorFromUrl(
  url: string,
  filename: string,
  isRequired = true
): ModelFileDescriptor {
  return ModelFileDescriptor.create({
    url,
    filename,
    isRequired,
    relativePath: lastPathComponent(url),
    destinationPath: filename,
  });
}

export function modelFileDescriptorUrlValue(
  descriptor: ModelFileDescriptor
): string | undefined {
  return descriptor.url.length > 0 ? descriptor.url : undefined;
}

export function modelFileDescriptorDestinationFilename(
  descriptor: ModelFileDescriptor
): string {
  return (
    nonEmpty(descriptor.destinationPath) ??
    nonEmpty(descriptor.filename) ??
    nonEmpty(descriptor.relativePath) ??
    ''
  );
}

export function modelFileDescriptorResolvedLocalPath(
  descriptor: ModelFileDescriptor
): string | undefined {
  return nonEmpty(descriptor.localPath);
}

export function resolvedModelFilePath(
  files: readonly ModelFileDescriptor[],
  role: ModelFileRole
): string | undefined {
  return modelFileDescriptorResolvedLocalPath(
    files.find((file) => file.role === role) ?? ModelFileDescriptor.create()
  );
}

export function resolvedPrimaryModelPath(
  files: readonly ModelFileDescriptor[]
): string | undefined {
  return resolvedModelFilePath(files, ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL);
}

export function resolvedVisionProjectorPath(
  files: readonly ModelFileDescriptor[]
): string | undefined {
  return resolvedModelFilePath(files, ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR);
}

export function resolvedTokenizerPath(
  files: readonly ModelFileDescriptor[]
): string | undefined {
  return resolvedModelFilePath(files, ModelFileRole.MODEL_FILE_ROLE_TOKENIZER);
}

export function resolvedConfigPath(
  files: readonly ModelFileDescriptor[]
): string | undefined {
  return resolvedModelFilePath(files, ModelFileRole.MODEL_FILE_ROLE_CONFIG);
}

export function resolvedVocabularyPath(
  files: readonly ModelFileDescriptor[]
): string | undefined {
  return resolvedModelFilePath(files, ModelFileRole.MODEL_FILE_ROLE_VOCABULARY);
}

export function lifecyclePrimaryArtifactPath(
  result: ModelLoadResult | CurrentModelResult
): string | undefined {
  return resolvedPrimaryModelPath(result.resolvedArtifacts) ?? nonEmpty(result.resolvedPath);
}

export function modelArtifactTypeRequiresExtraction(
  type: ModelArtifactType | undefined
): boolean {
  switch (type) {
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE:
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE:
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE:
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE:
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE:
      return true;
    default:
      return false;
  }
}

export function modelArtifactTypeRequiresDownload(
  type: ModelArtifactType | undefined
): boolean {
  return type !== ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN;
}

export function modelArtifactTypeDisplayName(
  type: ModelArtifactType | undefined
): string {
  switch (type) {
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE:
      return 'Single File';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE:
      return 'Archive';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE:
      return 'ZIP Archive';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE:
      return 'TAR.GZ Archive';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE:
      return 'TAR.BZ2 Archive';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE:
      return 'TAR.XZ Archive';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY:
      return 'Directory';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE:
      return 'Multi-File';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_CUSTOM:
      return 'Custom';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN:
      return 'Built-in';
    default:
      return 'Unspecified';
  }
}

export function archiveTypeArtifactType(type: ArchiveType | undefined): ModelArtifactType {
  switch (type) {
    case ArchiveType.ARCHIVE_TYPE_ZIP:
      return ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE;
    case ArchiveType.ARCHIVE_TYPE_TAR_GZ:
      return ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE;
    case ArchiveType.ARCHIVE_TYPE_TAR_BZ2:
      return ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE;
    case ArchiveType.ARCHIVE_TYPE_TAR_XZ:
      return ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE;
    default:
      return ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE;
  }
}

export function modelInfoArtifactType(model: ModelInfo): ModelArtifactType {
  if (model.singleFile) return ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE;
  if (model.archive) return archiveTypeArtifactType(model.archive.type);
  if (model.multiFile) return ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE;
  if (model.customStrategyId !== undefined) return ModelArtifactType.MODEL_ARTIFACT_TYPE_CUSTOM;
  if (model.builtIn === true) return ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN;
  return model.artifactType ?? ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED;
}

export function modelInfoIsBuiltIn(model: ModelInfo): boolean {
  return (
    model.builtIn === true ||
    model.artifactType === ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN ||
    model.localPath.startsWith('builtin:') ||
    model.framework === InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
    model.framework === InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS
  );
}

export function modelInfoRequiresExtraction(model: ModelInfo): boolean {
  return modelArtifactTypeRequiresExtraction(modelInfoArtifactType(model));
}

export function modelInfoRequiresDownload(model: ModelInfo): boolean {
  return modelInfoIsBuiltIn(model)
    ? false
    : modelArtifactTypeRequiresDownload(modelInfoArtifactType(model));
}

export function modelInfoArtifactDisplayName(model: ModelInfo): string {
  if (model.archive) {
    return `${archiveTypeDisplayName(model.archive.type)} Archive`;
  }
  if (model.multiFile) {
    return `Multi-File (${model.multiFile.files.length} files)`;
  }
  if (model.customStrategyId !== undefined) {
    return model.customStrategyId.length > 0
      ? `Custom (${model.customStrategyId})`
      : 'Custom';
  }
  return modelArtifactTypeDisplayName(modelInfoArtifactType(model));
}

export function modelInfoArchiveArtifact(
  model: ModelInfo
): ArchiveArtifact | undefined {
  if (model.archive) return model.archive;
  const type = legacyArchiveType(model.artifactType);
  return type === undefined
    ? undefined
    : ArchiveArtifact.create({
        type,
        structure: ArchiveStructure.ARCHIVE_STRUCTURE_UNKNOWN,
      });
}

export function modelInfoMultiFileDescriptors(
  model: ModelInfo
): ModelFileDescriptor[] {
  return model.multiFile?.files ?? [];
}

export function modelInfoExpectedArtifactFiles(model: ModelInfo): ExpectedModelFiles {
  if (model.expectedFiles) return model.expectedFiles;
  if (model.singleFile?.expectedFiles) return model.singleFile.expectedFiles;
  if (model.singleFile) {
    return {
      files: [],
      requiredPatterns: model.singleFile.requiredPatterns,
      optionalPatterns: model.singleFile.optionalPatterns,
    };
  }
  if (model.archive?.expectedFiles) return model.archive.expectedFiles;
  if (model.archive) {
    return {
      files: [],
      requiredPatterns: model.archive.requiredPatterns,
      optionalPatterns: model.archive.optionalPatterns,
    };
  }
  if (model.multiFile) {
    return {
      files: model.multiFile.files,
      requiredPatterns: [],
      optionalPatterns: [],
    };
  }
  return emptyExpectedModelFiles();
}

export function modelInfoIsAvailableForUse(model: ModelInfo): boolean {
  return modelInfoIsBuiltIn(model) || model.isDownloaded === true || model.isAvailable === true;
}

function legacyArchiveType(
  type: ModelArtifactType | undefined
): ArchiveType | undefined {
  switch (type) {
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE:
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE:
      return ArchiveType.ARCHIVE_TYPE_ZIP;
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE:
      return ArchiveType.ARCHIVE_TYPE_TAR_GZ;
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE:
      return ArchiveType.ARCHIVE_TYPE_TAR_BZ2;
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE:
      return ArchiveType.ARCHIVE_TYPE_TAR_XZ;
    default:
      return undefined;
  }
}

function archiveTypeDisplayName(type: ArchiveType | undefined): string {
  switch (type) {
    case ArchiveType.ARCHIVE_TYPE_ZIP:
      return 'ZIP';
    case ArchiveType.ARCHIVE_TYPE_TAR_GZ:
      return 'TAR.GZ';
    case ArchiveType.ARCHIVE_TYPE_TAR_BZ2:
      return 'TAR.BZ2';
    case ArchiveType.ARCHIVE_TYPE_TAR_XZ:
      return 'TAR.XZ';
    default:
      return 'Archive';
  }
}

function nonEmpty(value: string | undefined): string | undefined {
  return value && value.length > 0 ? value : undefined;
}

function lastPathComponent(value: string): string {
  const withoutQuery = value.split(/[?#]/, 1)[0] ?? value;
  const trimmed = withoutQuery.replace(/\/+$/, '');
  return trimmed.substring(trimmed.lastIndexOf('/') + 1);
}
