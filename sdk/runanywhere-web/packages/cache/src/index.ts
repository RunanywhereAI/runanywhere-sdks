// RunAnywhere Web Cache Package
// Provides caching and persistence for models and responses

// Model Cache exports
export { ModelCache } from './cache/model-cache';
export type {
  ModelMetadata,
  CachedModel,
  CacheConfig
} from './cache/model-cache';

// Response Cache exports
export { ResponseCache } from './cache/response-cache';
export type {
  CachedResponse,
  ResponseCacheConfig
} from './cache/response-cache';

// Utility functions
export function estimateModelSize(modelType: string, parameters?: number): number {
  // Rough estimates for model sizes based on type and parameters
  const estimates: Record<string, number> = {
    'vad-small': 1.5 * 1024 * 1024, // 1.5MB
    'vad-medium': 5 * 1024 * 1024, // 5MB
    'whisper-tiny': 15 * 1024 * 1024, // 15MB
    'whisper-base': 50 * 1024 * 1024, // 50MB
    'whisper-small': 120 * 1024 * 1024, // 120MB
    'whisper-medium': 750 * 1024 * 1024, // 750MB
  };

  if (estimates[modelType]) {
    return estimates[modelType];
  }

  // Fallback estimation based on parameters
  if (parameters) {
    // Rough estimate: 4 bytes per parameter (float32)
    return parameters * 4;
  }

  // Default fallback
  return 10 * 1024 * 1024; // 10MB
}

export function formatCacheSize(bytes: number): string {
  const units = ['B', 'KB', 'MB', 'GB'];
  let size = bytes;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }

  return `${size.toFixed(2)} ${units[unitIndex]}`;
}
