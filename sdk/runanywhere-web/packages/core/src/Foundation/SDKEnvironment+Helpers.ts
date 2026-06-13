/**
 * RunAnywhere Web SDK - SDKEnvironment helpers.
 *
 * Standalone helper functions over the proto-generated `SDKEnvironment`
 * enum (idl/model_types.proto). Port of the Swift extension members on
 * `RASDKEnvironment` (SDKEnvironment.swift:42-128), which delegate to the
 * C commons env predicates (rac_environment.h / environment.cpp). Web
 * cannot call those C helpers synchronously before WASM is loaded, so the
 * (trivial, stable) predicate logic is mirrored here 1:1 from
 * `sdk/runanywhere-commons/src/infrastructure/network/environment.cpp`.
 *
 * Wire-format helpers are NOT re-implemented here: use the codegen-generated
 * `sDKEnvironmentWireString` / `sDKEnvironmentFromWireString` from
 * `@runanywhere/proto-ts/convenience/model_types_convenience` (they back
 * Swift's Codable conformance, SDKEnvironment.swift:28-38).
 */

import { LogLevel } from '@runanywhere/proto-ts/logging';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

/**
 * All three deployable environments, excluding UNSPECIFIED / UNRECOGNIZED.
 * Swift parity: `RASDKEnvironment.deployableCases` (SDKEnvironment.swift:46-48).
 */
export function environmentDeployableCases(): SDKEnvironment[] {
  return [
    SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
    SDKEnvironment.SDK_ENVIRONMENT_STAGING,
    SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
  ];
}

/**
 * Normalize to one of the three deployable environments.
 *
 * Mirrors Swift's `cEnvironment` bridge (SDKEnvironment.swift:53-60), whose
 * `default:` arm maps UNSPECIFIED / UNRECOGNIZED to development before the C
 * predicates run. All boolean helpers below go through this so they return
 * exactly what Swift's C-backed computed properties return.
 */
function normalizedEnvironment(env: SDKEnvironment): SDKEnvironment {
  switch (env) {
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return SDKEnvironment.SDK_ENVIRONMENT_STAGING;
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
    default:
      return SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
  }
}

/**
 * Human-readable description.
 * Swift parity: `RASDKEnvironment.description` (SDKEnvironment.swift:63-70).
 */
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
 * Check if this is a production environment.
 * Swift parity: `RASDKEnvironment.isProduction` (SDKEnvironment.swift:73),
 * backed by `rac_env_is_production` (environment.cpp:39-41).
 */
export function environmentIsProduction(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
}

/**
 * Check if this is a testing environment (development or staging).
 * Swift parity: `RASDKEnvironment.isTesting` (SDKEnvironment.swift:76),
 * backed by `rac_env_is_testing` (environment.cpp:43-45).
 */
export function environmentIsTesting(env: SDKEnvironment): boolean {
  const normalized = normalizedEnvironment(env);
  return (
    normalized === SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT ||
    normalized === SDKEnvironment.SDK_ENVIRONMENT_STAGING
  );
}

/**
 * Check if this environment requires a valid backend URL (non-development).
 * Swift parity: `RASDKEnvironment.requiresBackendURL` (SDKEnvironment.swift:79),
 * backed by `rac_env_requires_backend_url` (environment.cpp:35-37).
 */
export function environmentRequiresBackendURL(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

/**
 * Determine logging verbosity based on environment.
 * Swift parity: `RASDKEnvironment.defaultLogLevel` (SDKEnvironment.swift:112-119).
 * Note: Swift switches on the proto value directly (default → .info) without
 * the `cEnvironment` normalization, so UNSPECIFIED yields INFO here too.
 */
export function environmentDefaultLogLevel(env: SDKEnvironment): LogLevel {
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

/**
 * Should send telemetry data (production only).
 * Swift parity: `RASDKEnvironment.shouldSendTelemetry` (SDKEnvironment.swift:122),
 * backed by `rac_env_should_send_telemetry` (environment.cpp:60-62).
 */
export function environmentShouldSendTelemetry(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
}

/**
 * Should sync with backend (non-development).
 * Swift parity: `RASDKEnvironment.shouldSyncWithBackend` (SDKEnvironment.swift:125),
 * backed by `rac_env_should_sync_with_backend` (environment.cpp:64-66).
 */
export function environmentShouldSyncWithBackend(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

/**
 * Requires API authentication (non-development).
 * Swift parity: `RASDKEnvironment.requiresAuthentication` (SDKEnvironment.swift:128),
 * backed by `rac_env_requires_auth` (environment.cpp:31-33).
 */
export function environmentRequiresAuthentication(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}
