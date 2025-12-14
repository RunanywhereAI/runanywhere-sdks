/**
 * Configuration Service for RunAnywhere React Native SDK
 *
 * Manages SDK configuration with fallback system.
 * The actual configuration logic lives in the native SDK.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Services/ConfigurationService.swift
 */

import { requireNativeModule } from '../native';
import type { ConfigurationData, ConfigurationSource, SDKEnvironment } from '../types';

/**
 * Configuration update options
 */
export interface ConfigurationUpdateOptions {
  /** Whether to persist the configuration */
  persist?: boolean;
  /** Whether to sync to cloud */
  syncToCloud?: boolean;
}

/**
 * Configuration Service
 *
 * Provides access to SDK configuration with automatic fallback:
 * Remote → Database → Consumer → SDK Defaults
 */
class ConfigurationServiceImpl {
  private cachedConfig: ConfigurationData | null = null;

  /**
   * Get the current configuration
   *
   * @returns Current configuration data or null if not loaded
   */
  async getConfiguration(): Promise<ConfigurationData | null> {
    if (this.cachedConfig) {
      return this.cachedConfig;
    }

    try {
      const native = requireNativeModule();
      const configJson = await native.getConfiguration();
      const config = JSON.parse(configJson) as ConfigurationData;
      this.cachedConfig = config;
      return config;
    } catch {
      return null;
    }
  }

  /**
   * Load configuration on launch with fallback system
   *
   * Fallback order:
   * 1. Remote configuration (if network available)
   * 2. Database (cached configuration)
   * 3. Consumer configuration (app-provided defaults)
   * 4. SDK defaults
   *
   * @returns Loaded configuration data
   */
  async loadConfigurationOnLaunch(): Promise<ConfigurationData> {
    const native = requireNativeModule();
    const configJson = await native.loadConfigurationOnLaunch();
    const config = JSON.parse(configJson) as ConfigurationData;
    this.cachedConfig = config;
    return config;
  }

  /**
   * Set consumer configuration override
   *
   * This allows the consuming app to provide default configuration
   * that takes precedence over SDK defaults.
   *
   * @param config - The consumer configuration to set
   */
  async setConsumerConfiguration(config: Partial<ConfigurationData>): Promise<void> {
    const native = requireNativeModule();
    await native.setConsumerConfiguration(JSON.stringify(config));
  }

  /**
   * Update configuration with a modifier function
   *
   * @param updates - Partial configuration updates
   * @param _options - Update options (not yet supported by native module)
   */
  async updateConfiguration(
    updates: Partial<ConfigurationData>,
    _options?: ConfigurationUpdateOptions
  ): Promise<void> {
    const native = requireNativeModule();
    // Native module expects a single JSON string argument
    const configJson = JSON.stringify(updates);
    await native.updateConfiguration(configJson);

    // Update cache
    if (this.cachedConfig) {
      this.cachedConfig = { ...this.cachedConfig, ...updates };
    }
  }

  /**
   * Sync configuration to cloud
   */
  async syncToCloud(): Promise<void> {
    const native = requireNativeModule();
    await native.syncConfigurationToCloud();
  }

  /**
   * Clear configuration cache
   */
  async clearCache(): Promise<void> {
    const native = requireNativeModule();
    await native.clearConfigurationCache();
    this.cachedConfig = null;
  }

  /**
   * Get the current environment
   */
  async getCurrentEnvironment(): Promise<SDKEnvironment | null> {
    const native = requireNativeModule();
    const envString = await native.getCurrentEnvironment();
    // Parse the string environment to SDKEnvironment enum
    if (!envString) return null;
    return envString as SDKEnvironment;
  }

  /**
   * Get configuration source (where the current config came from)
   */
  async getConfigurationSource(): Promise<ConfigurationSource | null> {
    const config = await this.getConfiguration();
    return config?.source ?? null;
  }

  /**
   * Check if configuration is loaded
   */
  isLoaded(): boolean {
    return this.cachedConfig !== null;
  }

  /**
   * Reset the configuration service
   */
  reset(): void {
    this.cachedConfig = null;
  }
}

/**
 * Singleton instance of the Configuration Service
 */
export const ConfigurationService = new ConfigurationServiceImpl();

export default ConfigurationService;
