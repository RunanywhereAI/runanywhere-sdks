/**
 * ConfigurationService.ts
 *
 * Simple configuration service with fallback system
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Services/ConfigurationService.swift
 */

import { SDKLogger } from '../Logging/Logger/SDKLogger';

/**
 * Configuration data structure
 */
export interface ConfigurationData {
  readonly id: string;
  readonly source: string; // ConfigurationSource
  readonly routing?: any;
  readonly generation?: any;
  readonly storage?: any;
  readonly api?: any;
  readonly download?: any;
  readonly hardware?: any;
  readonly debugMode: boolean;
  readonly apiKey?: string;
  readonly allowUserOverride: boolean;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

/**
 * Simple configuration service with fallback system
 */
export class ConfigurationService {
  private logger: SDKLogger;
  private configRepository: any | null;
  private syncCoordinator: any | null;
  private currentConfig: ConfigurationData | null = null;

  constructor(
    configRepository?: any | null,
    syncCoordinator?: any | null
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
  public async loadConfigurationOnLaunch(apiKey: string): Promise<ConfigurationData> {
    // Development mode: Skip remote fetch and use defaults
    if (!this.configRepository) {
      this.logger.info('Development mode: Using SDK defaults');
      const defaultConfig = this.getSDKDefaults(apiKey);
      this.currentConfig = defaultConfig;
      return defaultConfig;
    }

    // Step 1: Try to fetch remote configuration
    try {
      const remoteConfig = await this.configRepository.fetchRemoteConfiguration(apiKey);
      if (remoteConfig) {
        this.logger.info('Remote configuration loaded, saving to DB');
        await this.configRepository.save(remoteConfig);
        this.currentConfig = remoteConfig;
        return remoteConfig;
      }
    } catch (error) {
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
    } catch (error) {
      // Continue to next step
    }

    // Step 3: Try consumer configuration
    try {
      const consumerConfig = await this.configRepository.getConsumerConfiguration();
      if (consumerConfig) {
        this.logger.info('Using consumer configuration fallback');
        this.currentConfig = consumerConfig;
        return consumerConfig;
      }
    } catch (error) {
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

