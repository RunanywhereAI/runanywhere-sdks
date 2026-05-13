/**
 * LoggingConfiguration.ts
 *
 * Configuration for the logging system with environment presets.
 *
 * Matches iOS: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift
 *              (LoggingConfiguration struct)
 */

import { LogLevel } from './LogLevel';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

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
};

/**
 * Default configuration for staging environment
 */
export const stagingConfig: LoggingConfiguration = {
  enableLocalLogging: true,
  minLogLevel: LogLevel.Info,
  includeDeviceMetadata: true,
  enableSentryLogging: false,
};

/**
 * Default configuration for production environment
 */
export const productionConfig: LoggingConfiguration = {
  enableLocalLogging: false,
  minLogLevel: LogLevel.Warning,
  includeDeviceMetadata: true,
  enableSentryLogging: false,
};

/**
 * Get default configuration for an environment
 */
export function getConfigurationForEnvironment(
  environment: SDKEnvironment
): LoggingConfiguration {
  switch (environment) {
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
      return { ...developmentConfig };
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return { ...stagingConfig };
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return { ...productionConfig };
    default:
      return { ...developmentConfig };
  }
}

export { SDKEnvironment };
