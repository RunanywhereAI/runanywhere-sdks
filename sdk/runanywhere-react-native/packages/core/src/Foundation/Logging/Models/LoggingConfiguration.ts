/**
 * LoggingConfiguration.ts
 *
 * Environment presets for the generated `LoggingConfiguration` from
 * `@runanywhere/proto-ts/logging`. The wire shape (enableLocalLogging,
 * minLogLevel, includeSourceLocation, includeDeviceMetadata,
 * enableRemoteLogging, enableSentryLogging) is shared across SDKs; this file
 * only supplies the per-environment defaults. Fields not set here fall back to
 * the proto defaults via `fromPartial`.
 */

import { LogLevel } from './LogLevel';
import { LoggingConfiguration } from '@runanywhere/proto-ts/logging';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

export type { LoggingConfiguration };

const DEVELOPMENT: LoggingConfiguration = LoggingConfiguration.fromPartial({
  enableLocalLogging: true,
  minLogLevel: LogLevel.LOG_LEVEL_DEBUG,
  enableSentryLogging: true,
});

const STAGING: LoggingConfiguration = LoggingConfiguration.fromPartial({
  enableLocalLogging: true,
  minLogLevel: LogLevel.LOG_LEVEL_INFO,
  enableSentryLogging: false,
});

const PRODUCTION: LoggingConfiguration = LoggingConfiguration.fromPartial({
  enableLocalLogging: false,
  minLogLevel: LogLevel.LOG_LEVEL_WARNING,
  enableSentryLogging: false,
});

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
