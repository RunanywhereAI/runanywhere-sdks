/**
 * CoreAnalyticsTypes.ts
 * RunAnywhere SDK
 *
 * Core analytics types used across all capabilities.
 */

// MARK: - Analytics Metrics Protocol

/**
 * Base interface for analytics metrics
 */
export interface AnalyticsMetrics {
  totalEvents: number;
  startTime: Date;
  lastEventTime: Date | null;
}

// MARK: - Inference Framework

/**
 * Inference frameworks used for tracking which engine is processing requests.
 * Use "none" for services that don't require a model/framework.
 */
export enum InferenceFrameworkType {
  LLAMA_CPP = 'llama_cpp',
  WHISPER_KIT = 'whisper_kit',
  ONNX = 'onnx',
  CORE_ML = 'core_ml',
  FOUNDATION_MODELS = 'foundation_models',
  MLX = 'mlx',
  BUILT_IN = 'built_in', // For simple services like energy-based VAD
  NONE = 'none', // For services that don't use a model
  UNKNOWN = 'unknown',
}

// MARK: - Model Lifecycle Event Types

/**
 * Event types for model lifecycle across all capabilities
 */
export enum ModelLifecycleEventType {
  LOADING_STARTED = 'model_loading_started',
  LOAD_COMPLETED = 'model_load_completed',
  LOAD_FAILED = 'model_load_failed',
  UNLOAD_COMPLETED = 'model_unload_completed',
  DOWNLOAD_STARTED = 'model_download_started',
  DOWNLOAD_PROGRESS = 'model_download_progress',
  DOWNLOAD_COMPLETED = 'model_download_completed',
  DOWNLOAD_FAILED = 'model_download_failed',
  ERROR = 'model_lifecycle_error',
}

// MARK: - Model Lifecycle Metrics

/**
 * Metrics for model lifecycle operations
 */
export interface ModelLifecycleMetrics extends AnalyticsMetrics {
  totalLoads: number;
  successfulLoads: number;
  failedLoads: number;
  averageLoadTimeMs: number; // -1 indicates N/A for services without models
  totalUnloads: number;
  totalDownloads: number;
  successfulDownloads: number;
  failedDownloads: number;
  totalBytesDownloaded: number;
  framework: InferenceFrameworkType;
}

/**
 * Creates a default ModelLifecycleMetrics object
 */
export function createModelLifecycleMetrics(
  overrides?: Partial<ModelLifecycleMetrics>
): ModelLifecycleMetrics {
  return {
    totalEvents: 0,
    startTime: new Date(),
    lastEventTime: null,
    totalLoads: 0,
    successfulLoads: 0,
    failedLoads: 0,
    averageLoadTimeMs: -1, // -1 indicates N/A for services without models
    totalUnloads: 0,
    totalDownloads: 0,
    successfulDownloads: 0,
    failedDownloads: 0,
    totalBytesDownloaded: 0,
    framework: InferenceFrameworkType.UNKNOWN,
    ...overrides,
  };
}
