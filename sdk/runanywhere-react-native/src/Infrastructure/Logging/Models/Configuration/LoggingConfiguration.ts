/**
 * LoggingConfiguration.ts
 * RunAnywhere SDK
 *
 * Configuration settings for the logging system.
 * Matches iOS: Infrastructure/Logging/Models/Configuration/LoggingConfiguration.swift
 */

import { LogLevel } from '../../../../Foundation/Logging/Models/LogLevel';

/**
 * Logging configuration for local debugging
 */
export interface LoggingConfiguration {
  /**
   * Enable local logging (console output)
   * @default true
   */
  enableLocalLogging: boolean;

  /**
   * Minimum log level filter
   * @default LogLevel.Info
   */
  minLogLevel: LogLevel;

  /**
   * Include device metadata in logs
   * @default true
   */
  includeDeviceMetadata: boolean;

  /**
   * Enable Sentry logging for crash reporting and error tracking.
   * When enabled, logs at warning level and above are sent to Sentry.
   * @default false
   */
  enableSentryLogging: boolean;
}

/**
 * Default logging configuration
 */
export const DEFAULT_LOGGING_CONFIGURATION: LoggingConfiguration = {
  enableLocalLogging: true,
  minLogLevel: LogLevel.Info,
  includeDeviceMetadata: true,
  enableSentryLogging: false,
};

/**
 * Logging configuration presets
 */
export const LoggingConfigurationPresets = {
  /**
   * Default configuration
   */
  default: DEFAULT_LOGGING_CONFIGURATION,

  /**
   * Configuration preset for development environment.
   * Sentry logging is enabled by default for development.
   */
  development: {
    enableLocalLogging: true,
    minLogLevel: LogLevel.Debug,
    includeDeviceMetadata: false,
    enableSentryLogging: true,
  } as LoggingConfiguration,

  /**
   * Configuration preset for staging environment
   */
  staging: {
    enableLocalLogging: true,
    minLogLevel: LogLevel.Info,
    includeDeviceMetadata: true,
    enableSentryLogging: false,
  } as LoggingConfiguration,

  /**
   * Configuration preset for production environment
   */
  production: {
    enableLocalLogging: false,
    minLogLevel: LogLevel.Warning,
    includeDeviceMetadata: true,
    enableSentryLogging: false,
  } as LoggingConfiguration,
};

/**
 * Create a logging configuration with optional overrides
 */
export function createLoggingConfiguration(
  overrides?: Partial<LoggingConfiguration>
): LoggingConfiguration {
  return {
    ...DEFAULT_LOGGING_CONFIGURATION,
    ...overrides,
  };
}

/**
 * Validate a logging configuration
 */
export function validateLoggingConfiguration(
  _config: LoggingConfiguration
): void {
  // Currently all configurations are valid
  // Add validation rules here if needed in the future
}

/**
 * Builder class for LoggingConfiguration
 */
export class LoggingConfigurationBuilder {
  private config: LoggingConfiguration = { ...DEFAULT_LOGGING_CONFIGURATION };

  enableLocalLogging(value: boolean): this {
    this.config.enableLocalLogging = value;
    return this;
  }

  minLogLevel(value: LogLevel): this {
    this.config.minLogLevel = value;
    return this;
  }

  includeDeviceMetadata(value: boolean): this {
    this.config.includeDeviceMetadata = value;
    return this;
  }

  enableSentryLogging(value: boolean): this {
    this.config.enableSentryLogging = value;
    return this;
  }

  build(): LoggingConfiguration {
    validateLoggingConfiguration(this.config);
    return { ...this.config };
  }
}
