/**
 * RunAnywhere React Native SDK - Services
 *
 * Core services for SDK functionality.
 */

// Model Registry - Manages model discovery and registration (JS-based)
export {
  ModelRegistry,
  type ModelCriteria,
  type AddModelFromURLOptions,
} from './ModelRegistry';

// File System - Cross-platform file operations using react-native-fs
export {
  FileSystem,
  ArchiveType,
  ArchiveStructure,
  type ModelArtifactType,
  type DownloadProgress as FSDownloadProgress,
  type ExtractionResult,
} from './FileSystem';

// Download Service - Native-based download (delegates to native commons)
export {
  DownloadService,
  DownloadState,
  type DownloadProgress,
  type DownloadTask,
  type DownloadConfiguration,
  type ProgressCallback,
} from './DownloadService';

// TTS Service - Native implementation available
export {
  SystemTTSService,
  getVoicesByLanguage,
  getDefaultVoice,
  getPlatformDefaultVoice,
  PlatformVoices,
} from './SystemTTSService';
