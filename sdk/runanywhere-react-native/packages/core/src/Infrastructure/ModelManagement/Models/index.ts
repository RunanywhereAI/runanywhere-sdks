/**
 * ModelManagement Models exports
 */

export { InferenceFramework } from './InferenceFramework';
export {
  getFrameworkDisplayName,
  frameworkSupportsLLM,
  frameworkSupportsSTT,
  frameworkSupportsTTS,
} from './InferenceFramework';

export type { StoredModel } from './StoredModel';
export { createStoredModel } from './StoredModel';

export type { ModelStorageInfo } from './ModelStorageInfo';
export {
  createModelStorageInfo,
  createEmptyModelStorageInfo,
  getModelsForFramework,
  getFrameworkCount,
  getActiveFrameworks,
  formatTotalSize,
} from './ModelStorageInfo';

// Model Artifact Types
export {
  ArchiveType,
  getArchiveTypeExtension,
  detectArchiveType,
  ArchiveStructure,
  type ExpectedModelFiles,
  EXPECTED_MODEL_FILES_NONE,
  createExpectedModelFiles,
  type ModelFileDescriptor,
  createModelFileDescriptor,
  ModelArtifactTypeKind,
  type ModelArtifactType,
  singleFileArtifact,
  archiveArtifact,
  zipArchiveArtifact,
  tarBz2ArchiveArtifact,
  tarGzArchiveArtifact,
  multiFileArtifact,
  customArtifact,
  builtInArtifact,
  inferArtifactType,
  requiresExtraction,
  requiresDownload,
  getExpectedFiles,
  getArtifactTypeDisplayName,
} from './ModelArtifactType';
