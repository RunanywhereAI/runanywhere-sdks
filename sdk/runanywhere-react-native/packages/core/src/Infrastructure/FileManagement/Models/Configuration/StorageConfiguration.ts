/**
 * StorageConfiguration.ts
 * RunAnywhere SDK
 *
 * Configuration for storage behavior.
 * Matches iOS: Infrastructure/FileManagement/Models/Configuration/StorageConfiguration.swift
 */

/**
 * Configuration for storage behavior
 */
export interface StorageConfiguration {
  /**
   * Maximum cache size in bytes
   * @default 1073741824 (1GB)
   */
  maxCacheSize: number;

  /**
   * Storage directory name
   * @default 'RunAnywhere'
   */
  directoryName: string;

  /**
   * Whether to enable automatic cleanup
   * @default true
   */
  enableAutoCleanup: boolean;

  /**
   * Auto cleanup interval in seconds
   * @default 86400 (24 hours)
   */
  autoCleanupInterval: number;

  /**
   * Minimum free space to maintain (in bytes)
   * @default 500000000 (500MB)
   */
  minimumFreeSpace: number;

  /**
   * Whether to compress stored models
   * @default false
   */
  enableCompression: boolean;
}

/**
 * Default storage configuration
 */
export const DEFAULT_STORAGE_CONFIGURATION: StorageConfiguration = {
  maxCacheSize: 1_073_741_824, // 1GB
  directoryName: 'RunAnywhere',
  enableAutoCleanup: true,
  autoCleanupInterval: 86400, // 24 hours
  minimumFreeSpace: 500_000_000, // 500MB
  enableCompression: false,
};

/**
 * Create a storage configuration with optional overrides
 */
export function createStorageConfiguration(
  overrides?: Partial<StorageConfiguration>
): StorageConfiguration {
  return {
    ...DEFAULT_STORAGE_CONFIGURATION,
    ...overrides,
  };
}

/**
 * Storage configuration presets
 */
export const StorageConfigurationPresets = {
  /**
   * Default configuration (1GB cache, LRU eviction)
   */
  default: DEFAULT_STORAGE_CONFIGURATION,

  /**
   * Small device configuration (512MB cache)
   */
  smallDevice: {
    ...DEFAULT_STORAGE_CONFIGURATION,
    maxCacheSize: 512_000_000, // 512MB
    minimumFreeSpace: 200_000_000, // 200MB
  } as StorageConfiguration,

  /**
   * Large device configuration (4GB cache)
   */
  largeDevice: {
    ...DEFAULT_STORAGE_CONFIGURATION,
    maxCacheSize: 4_294_967_296, // 4GB
    minimumFreeSpace: 1_000_000_000, // 1GB
  } as StorageConfiguration,

  /**
   * Aggressive cleanup configuration
   */
  aggressiveCleanup: {
    ...DEFAULT_STORAGE_CONFIGURATION,
    autoCleanupInterval: 3600, // 1 hour
  } as StorageConfiguration,
};
