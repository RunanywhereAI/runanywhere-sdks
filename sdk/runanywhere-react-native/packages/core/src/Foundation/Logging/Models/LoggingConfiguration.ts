/**
 * LoggingConfiguration.ts
 *
 * Configuration for the logging system with environment presets.
 *
 * Matches iOS: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift
 *              (LoggingConfiguration struct)
 */

import { LogLevel } from './LogLevel';

// ============================================================================
// SDK Environment
// ============================================================================

/**
 * SDK environment for configuration
 * Matches iOS: SDKEnvironment
 */
export enum SDKEnvironment {
  Development = 'development',
  Staging = 'staging',
  Production = 'production',
}

// ============================================================================
// Logging Configuration
// ============================================================================

/**
 * Configuration for the logging system.
 * Matches iOS: LoggingConfiguration struct
 */
export interface LoggingConfiguration {
  /** Enable local console logging */
  enableLocalLogging: boolean;

  /** Minimum log level to output */
  minLogLevel: LogLevel;

  /** Include device metadata in logs */
  includeDeviceMetadata: boolean;

  /** Enable Sentry logging */
  enableSentryLogging: boolean;

  /** Sentry DSN (required if enableSentryLogging is true) */
  sentryDSN?: string;

  /** Current environment */
  environment: SDKEnvironment;
}

// ============================================================================
// Default Configurations
// ============================================================================

/**
 * Default configuration for development environment
 */
export const developmentConfig: LoggingConfiguration = {
  enableLocalLogging: true,
  minLogLevel: LogLevel.Debug,
  includeDeviceMetadata: false,
  enableSentryLogging: true,
  environment: SDKEnvironment.Development,
};

/**
 * Default configuration for staging environment
 */
export const stagingConfig: LoggingConfiguration = {
  enableLocalLogging: true,
  minLogLevel: LogLevel.Info,
  includeDeviceMetadata: true,
  enableSentryLogging: true,
  environment: SDKEnvironment.Staging,
};

/**
 * Default configuration for production environment
 */
export const productionConfig: LoggingConfiguration = {
  enableLocalLogging: false,
  minLogLevel: LogLevel.Warning,
  includeDeviceMetadata: true,
  enableSentryLogging: true,
  environment: SDKEnvironment.Production,
};

/**
 * Get default configuration for an environment
 */
export function getConfigurationForEnvironment(
  environment: SDKEnvironment
): LoggingConfiguration {
  switch (environment) {
    case SDKEnvironment.Development:
      return { ...developmentConfig };
    case SDKEnvironment.Staging:
      return { ...stagingConfig };
    case SDKEnvironment.Production:
      return { ...productionConfig };
  }
}

/**
 * Create a custom configuration
 */
export function createLoggingConfiguration(
  partial: Partial<LoggingConfiguration>
): LoggingConfiguration {
  const defaultConfig = getConfigurationForEnvironment(
    partial.environment ?? SDKEnvironment.Development
  );
  return { ...defaultConfig, ...partial };
}
