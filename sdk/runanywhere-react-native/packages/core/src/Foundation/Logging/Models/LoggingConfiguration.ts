/**
 * LoggingConfiguration.ts
 *
 * Configuration shape for the logging system with environment presets.
 *
 * Mirrors the `LoggingConfiguration` struct in
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift`.
 */

import { LogLevel } from './LogLevel';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

export interface LoggingConfiguration {
  /** Enable local console logging. */
  enableLocalLogging: boolean;
  /** Minimum severity to emit. */
  minLogLevel: LogLevel;
  /** Enable Sentry forwarding. */
  enableSentryLogging: boolean;
}

const DEVELOPMENT: LoggingConfiguration = {
  enableLocalLogging: true,
  minLogLevel: LogLevel.Debug,
  enableSentryLogging: true,
};

const STAGING: LoggingConfiguration = {
  enableLocalLogging: true,
  minLogLevel: LogLevel.Info,
  enableSentryLogging: false,
};

const PRODUCTION: LoggingConfiguration = {
  enableLocalLogging: false,
  minLogLevel: LogLevel.Warning,
  enableSentryLogging: false,
};

export function getConfigurationForEnvironment(
  environment: SDKEnvironment
): LoggingConfiguration {
  switch (environment) {
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
      return { ...DEVELOPMENT };
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return { ...STAGING };
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return { ...PRODUCTION };
    default:
      return { ...DEVELOPMENT };
  }
}
