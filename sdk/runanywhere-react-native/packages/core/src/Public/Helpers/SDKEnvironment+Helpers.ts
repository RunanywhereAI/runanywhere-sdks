/**
 * SDKEnvironment+Helpers.ts
 *
 * Behaviour helpers for the proto-generated `SDKEnvironment` enum.
 * Mirrors Swift `SDKEnvironment.swift` / commons `rac_env_*` predicates.
 */

import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import { LogLevel } from '@runanywhere/proto-ts/logging';

/** Deployable product environments (development + production). */
export const deployableEnvironments: readonly SDKEnvironment[] = [
  SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
  SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
];

export function environmentDescription(env: SDKEnvironment): string {
  switch (env) {
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
      return 'Development Environment';
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return 'Production Environment';
    default:
      return 'Unspecified Environment';
  }
}

export function isProduction(env: SDKEnvironment): boolean {
  return env === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
}

export function isTesting(env: SDKEnvironment): boolean {
  return env === SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

export function requiresBackendURL(env: SDKEnvironment): boolean {
  return env !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

export function shouldSendTelemetry(_env: SDKEnvironment): boolean {
  return true;
}

export function shouldSyncWithBackend(env: SDKEnvironment): boolean {
  return env !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

export function requiresAuthentication(env: SDKEnvironment): boolean {
  return env !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

export function defaultLogLevel(env: SDKEnvironment): LogLevel {
  switch (env) {
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
      return LogLevel.LOG_LEVEL_DEBUG;
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return LogLevel.LOG_LEVEL_WARNING;
    default:
      return LogLevel.LOG_LEVEL_INFO;
  }
}
