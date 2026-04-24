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
  MultiFileModelCache,
  type ModelFileDescriptor,
  type DownloadProgress as FSDownloadProgress,
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

// Network Layer — HTTP transport lives in native C++ (rac_http_client_*).
// These exports cover configuration helpers, telemetry, and endpoints only.
export {
  SDKEnvironment,
  createNetworkConfig,
  getEnvironmentName,
  isDevelopment,
  isProduction,
  DEFAULT_BASE_URL,
  DEFAULT_TIMEOUT_MS,
  type NetworkConfig,
  TelemetryService,
  TelemetryCategory,
  APIEndpoints,
  type APIEndpointKey,
  type APIEndpointValue,
} from './Network';
