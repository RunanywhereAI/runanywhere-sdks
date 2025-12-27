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

// JS Download Service - JavaScript-based download using react-native-fs
export {
  JSDownloadService,
  type JSDownloadProgress,
} from './JSDownloadService';

// Download Service - Native-based download (requires native module implementation)
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
