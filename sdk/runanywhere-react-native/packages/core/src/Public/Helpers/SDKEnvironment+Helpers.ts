/**
 * SDKEnvironment+Helpers.ts
 *
 * Behaviour helpers for the proto-generated `SDKEnvironment` enum.
 *
 * Mirrors Swift `SDKEnvironment.swift:42-128`. Swift delegates to the
 * commons C ABI (`rac_env_is_production`, `rac_env_should_send_telemetry`,
 * …); the C string/predicate table is not exposed through the Nitro proto
 * bridge, so the exact same logic is mirrored here from
 * `sdk/runanywhere-commons/src/infrastructure/network/environment.cpp`.
 * TODO(layer-down): expose the rac_env_* predicates through the Nitro
 * bridge and delegate, removing this mirrored table.
 *
 * Swift's `isCompatibleWithCurrentBuild` / `isDebugBuild` are not ported:
 * they depend on the `#if DEBUG` compile-time flag, which has no
 * cross-bundle RN equivalent.
 */

import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import { LogLevel } from '@runanywhere/proto-ts/logging';

/**
 * All three deployable environments, excluding UNSPECIFIED/UNRECOGNIZED.
 * Mirrors Swift `SDKEnvironment.deployableCases`.
 */
export const deployableEnvironments: readonly SDKEnvironment[] = [
  SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
  SDKEnvironment.SDK_ENVIRONMENT_STAGING,
  SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
];

/** Human-readable description. Mirrors Swift `SDKEnvironment.description`. */
export function environmentDescription(env: SDKEnvironment): string {
  switch (env) {
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
      return 'Development Environment';
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return 'Staging Environment';
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return 'Production Environment';
    default:
      return 'Unspecified Environment';
  }
}

/**
 * Whether this is a production environment.
 * Mirrors Swift `isProduction` → `rac_env_is_production` (env == PRODUCTION).
 */
export function isProduction(env: SDKEnvironment): boolean {
  return env === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
}

/**
 * Whether this is a testing environment.
 * Mirrors Swift `isTesting` → `rac_env_is_testing`
 * (env == DEVELOPMENT || env == STAGING).
 */
export function isTesting(env: SDKEnvironment): boolean {
  return (
    env === SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT ||
    env === SDKEnvironment.SDK_ENVIRONMENT_STAGING
  );
}

/**
 * Whether this environment requires a valid backend URL.
 * Mirrors Swift `requiresBackendURL` → `rac_env_requires_backend_url`
 * (env != DEVELOPMENT).
 */
export function requiresBackendURL(env: SDKEnvironment): boolean {
  return env !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

/**
 * Whether telemetry should be sent (production only).
 * Mirrors Swift `shouldSendTelemetry` → `rac_env_should_send_telemetry`.
 */
export function shouldSendTelemetry(env: SDKEnvironment): boolean {
  return env === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
}

/**
 * Whether to sync with the backend (non-development).
 * Mirrors Swift `shouldSyncWithBackend` → `rac_env_should_sync_with_backend`.
 */
export function shouldSyncWithBackend(env: SDKEnvironment): boolean {
  return env !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

/**
 * Whether API authentication is required (non-development).
 * Mirrors Swift `requiresAuthentication` → `rac_env_requires_auth`.
 */
export function requiresAuthentication(env: SDKEnvironment): boolean {
  return env !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

/**
 * Default logging verbosity for an environment.
 * Mirrors Swift `defaultLogLevel` (SDKEnvironment.swift:112-119).
 */
export function defaultLogLevel(env: SDKEnvironment): LogLevel {
  switch (env) {
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
      return LogLevel.LOG_LEVEL_DEBUG;
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return LogLevel.LOG_LEVEL_INFO;
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return LogLevel.LOG_LEVEL_WARNING;
    default:
      return LogLevel.LOG_LEVEL_INFO;
  }
}
