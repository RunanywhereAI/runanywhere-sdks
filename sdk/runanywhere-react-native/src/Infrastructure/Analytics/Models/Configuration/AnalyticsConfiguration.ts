/**
 * AnalyticsConfiguration.ts
 * RunAnywhere SDK
 *
 * Configuration for analytics capability.
 * Matches iOS: Infrastructure/Analytics/Models/Configuration/AnalyticsConfiguration.swift
 */

import { AnalyticsError } from '../../Errors/AnalyticsError';

/**
 * Configuration for the Analytics capability
 */
export interface AnalyticsConfiguration {
  // MARK: - Queue Settings

  /**
   * Maximum number of events to batch before flushing
   * @default 50
   */
  batchSize: number;

  /**
   * Interval in seconds between automatic flushes
   * @default 30.0
   */
  flushInterval: number;

  /**
   * Maximum number of retry attempts for failed operations
   * @default 3
   */
  maxRetries: number;

  // MARK: - Storage Settings

  /**
   * Whether to persist events locally before syncing
   * @default true
   */
  enableLocalPersistence: boolean;

  /**
   * Maximum age of events to keep locally (in days)
   * @default 30
   */
  retentionDays: number;

  /**
   * Maximum number of events to store locally
   * @default 10000
   */
  maxLocalEvents: number;

  // MARK: - Sync Settings

  /**
   * Whether to sync events to remote server
   * @default true
   */
  enableRemoteSync: boolean;

  /**
   * Whether to sync only on WiFi
   * @default false
   */
  syncOnlyOnWiFi: boolean;

  // MARK: - Privacy Settings

  /**
   * Whether to include device information in events
   * @default true
   */
  includeDeviceInfo: boolean;

  /**
   * Whether to anonymize user data
   * @default false
   */
  anonymizeData: boolean;

  // MARK: - Debug Settings

  /**
   * Whether to enable verbose logging
   * @default false
   */
  debugLogging: boolean;
}

/**
 * Default analytics configuration
 */
export const DEFAULT_ANALYTICS_CONFIGURATION: AnalyticsConfiguration = {
  batchSize: 50,
  flushInterval: 30.0,
  maxRetries: 3,
  enableLocalPersistence: true,
  retentionDays: 30,
  maxLocalEvents: 10000,
  enableRemoteSync: true,
  syncOnlyOnWiFi: false,
  includeDeviceInfo: true,
  anonymizeData: false,
  debugLogging: false,
};

/**
 * Analytics configuration presets
 */
export const AnalyticsConfigurationPresets = {
  /**
   * Default configuration for production use
   */
  default: DEFAULT_ANALYTICS_CONFIGURATION,

  /**
   * Configuration optimized for development
   */
  development: {
    ...DEFAULT_ANALYTICS_CONFIGURATION,
    batchSize: 10,
    flushInterval: 5.0,
    enableRemoteSync: false,
    debugLogging: true,
  } as AnalyticsConfiguration,

  /**
   * Configuration with minimal data collection
   */
  minimal: {
    ...DEFAULT_ANALYTICS_CONFIGURATION,
    enableLocalPersistence: false,
    enableRemoteSync: false,
    includeDeviceInfo: false,
    anonymizeData: true,
  } as AnalyticsConfiguration,
};

/**
 * Create an analytics configuration with optional overrides
 */
export function createAnalyticsConfiguration(
  overrides?: Partial<AnalyticsConfiguration>
): AnalyticsConfiguration {
  return {
    ...DEFAULT_ANALYTICS_CONFIGURATION,
    ...overrides,
  };
}

/**
 * Validate an analytics configuration
 * @throws AnalyticsError if configuration is invalid
 */
export function validateAnalyticsConfiguration(
  config: AnalyticsConfiguration
): void {
  if (config.batchSize <= 0) {
    throw AnalyticsError.invalidConfiguration(
      'Batch size must be greater than 0'
    );
  }
  if (config.flushInterval <= 0) {
    throw AnalyticsError.invalidConfiguration(
      'Flush interval must be greater than 0'
    );
  }
  if (config.maxRetries < 0) {
    throw AnalyticsError.invalidConfiguration('Max retries cannot be negative');
  }
  if (config.retentionDays <= 0) {
    throw AnalyticsError.invalidConfiguration(
      'Retention days must be greater than 0'
    );
  }
  if (config.maxLocalEvents <= 0) {
    throw AnalyticsError.invalidConfiguration(
      'Max local events must be greater than 0'
    );
  }
}

/**
 * Builder class for AnalyticsConfiguration
 */
export class AnalyticsConfigurationBuilder {
  private config: AnalyticsConfiguration = { ...DEFAULT_ANALYTICS_CONFIGURATION };

  batchSize(value: number): this {
    this.config.batchSize = value;
    return this;
  }

  flushInterval(value: number): this {
    this.config.flushInterval = value;
    return this;
  }

  maxRetries(value: number): this {
    this.config.maxRetries = value;
    return this;
  }

  enableLocalPersistence(value: boolean): this {
    this.config.enableLocalPersistence = value;
    return this;
  }

  retentionDays(value: number): this {
    this.config.retentionDays = value;
    return this;
  }

  maxLocalEvents(value: number): this {
    this.config.maxLocalEvents = value;
    return this;
  }

  enableRemoteSync(value: boolean): this {
    this.config.enableRemoteSync = value;
    return this;
  }

  syncOnlyOnWiFi(value: boolean): this {
    this.config.syncOnlyOnWiFi = value;
    return this;
  }

  includeDeviceInfo(value: boolean): this {
    this.config.includeDeviceInfo = value;
    return this;
  }

  anonymizeData(value: boolean): this {
    this.config.anonymizeData = value;
    return this;
  }

  debugLogging(value: boolean): this {
    this.config.debugLogging = value;
    return this;
  }

  build(): AnalyticsConfiguration {
    validateAnalyticsConfiguration(this.config);
    return { ...this.config };
  }
}
