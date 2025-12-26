/**
 * ConfigurationService.ts
 *
 * Simple configuration service with fallback system
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Services/ConfigurationService.swift
 */

import { SDKLogger } from '../Logging/Logger/SDKLogger';

/**
 * Configuration section types for structured configuration data
 */
export interface RoutingConfig {
  preferOnDevice?: boolean;
  costWeight?: number;
  latencyWeight?: number;
}

export interface GenerationConfig {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
}

export interface StorageConfig {
  maxCacheSize?: number;
  cleanupThreshold?: number;
}

export interface APIConfig {
  baseURL?: string;
  timeout?: number;
}

export interface DownloadConfig {
  maxConcurrent?: number;
  retryCount?: number;
}

export interface HardwareConfig {
  preferGPU?: boolean;
  maxMemoryUsage?: number;
}

/**
 * Configuration data structure
 */
export interface ConfigurationData {
  readonly id: string;
  readonly source: string; // ConfigurationSource
  readonly routing?: RoutingConfig;
  readonly generation?: GenerationConfig;
  readonly storage?: StorageConfig;
  readonly api?: APIConfig;
  readonly download?: DownloadConfig;
  readonly hardware?: HardwareConfig;
  readonly debugMode: boolean;
  readonly apiKey?: string;
  readonly allowUserOverride: boolean;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

/**
 * Repository interface for configuration persistence
 */
interface ConfigurationRepository {
  fetchRemoteConfiguration(apiKey: string): Promise<ConfigurationData | null>;
  fetch(id: string): Promise<ConfigurationData | null>;
  save(config: ConfigurationData): Promise<void>;
  getConsumerConfiguration(): Promise<ConfigurationData | null>;
}

/**
 * Simple configuration service with fallback system
 */
export class ConfigurationService {
  private logger: SDKLogger;
  private configRepository: ConfigurationRepository | null;
  private syncCoordinator: unknown | null;
  private currentConfig: ConfigurationData | null = null;

  constructor(
    configRepository?: ConfigurationRepository | null,
    syncCoordinator?: unknown | null
  ) {
    this.logger = new SDKLogger('ConfigurationService');
    this.configRepository = configRepository ?? null;
    this.syncCoordinator = syncCoordinator ?? null;
  }

  /**
   * Get current configuration
   */
  public getConfiguration(): ConfigurationData | null {
    return this.currentConfig;
  }

  /**
   * Load configuration on app launch
   */
  public async loadConfigurationOnLaunch(
    apiKey: string
  ): Promise<ConfigurationData> {
    // Development mode: Skip remote fetch and use defaults
    if (!this.configRepository) {
      this.logger.info('Development mode: Using SDK defaults');
      const defaultConfig = this.getSDKDefaults(apiKey);
      this.currentConfig = defaultConfig;
      return defaultConfig;
    }

    // Step 1: Try to fetch remote configuration
    try {
      const remoteConfig =
        await this.configRepository.fetchRemoteConfiguration(apiKey);
      if (remoteConfig) {
        this.logger.info('Remote configuration loaded, saving to DB');
        await this.configRepository.save(remoteConfig);
        this.currentConfig = remoteConfig;
        return remoteConfig;
      }
    } catch {
      // Continue to next step
    }

    // Step 2: Try to load from DB
    try {
      const dbConfig = await this.configRepository.fetch('default');
      if (dbConfig) {
        this.logger.info('Using DB configuration');
        this.currentConfig = dbConfig;
        return dbConfig;
      }
    } catch {
      // Continue to next step
    }

    // Step 3: Try consumer configuration
    try {
      const consumerConfig =
        await this.configRepository.getConsumerConfiguration();
      if (consumerConfig) {
        this.logger.info('Using consumer configuration fallback');
        this.currentConfig = consumerConfig;
        return consumerConfig;
      }
    } catch {
      // Continue to next step
    }

    // Step 4: Use SDK defaults
    this.logger.info('Using SDK default configuration');
    const defaultConfig = this.getSDKDefaults(apiKey);
    this.currentConfig = defaultConfig;
    return defaultConfig;
  }

  /**
   * Ensure configuration is loaded
   */
  public async ensureConfigurationLoaded(): Promise<void> {
    if (!this.currentConfig) {
      this.currentConfig = await this.loadConfigurationOnLaunch('');
    }
  }

  /**
   * Get SDK defaults
   */
  private getSDKDefaults(apiKey: string): ConfigurationData {
    return {
      id: 'default',
      source: 'defaults',
      debugMode: false,
      allowUserOverride: true,
      apiKey,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
  }
}
