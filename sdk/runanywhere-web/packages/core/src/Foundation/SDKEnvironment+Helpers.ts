/**
 * RunAnywhere Web SDK - SDKEnvironment helpers.
 *
 * Standalone helper functions over the proto-generated `SDKEnvironment`
 * enum (idl/model_types.proto). Port of the Swift extension members on
 * `RASDKEnvironment` (SDKEnvironment.swift), which delegate to the
 * C commons env predicates (rac_environment.h / environment.cpp).
 */

import { LogLevel } from '@runanywhere/proto-ts/logging';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

/**
 * Deployable product environments (development + production).
 */
export function environmentDeployableCases(): SDKEnvironment[] {
  return [
    SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
    SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
  ];
}

/**
 * Normalize to a product environment (UNSPECIFIED → development).
 */
function normalizedEnvironment(env: SDKEnvironment): SDKEnvironment {
  switch (env) {
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
    default:
      return SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
  }
}

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

export function environmentIsProduction(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
}

export function environmentIsTesting(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) === SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

export function environmentRequiresBackendURL(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

export function environmentDefaultLogLevel(env: SDKEnvironment): LogLevel {
  switch (env) {
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
      return LogLevel.LOG_LEVEL_DEBUG;
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return LogLevel.LOG_LEVEL_WARNING;
    default:
      return LogLevel.LOG_LEVEL_INFO;
  }
}

export function environmentShouldSendTelemetry(_env: SDKEnvironment): boolean {
  return true;
}

export function environmentShouldSyncWithBackend(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

export function environmentRequiresAuthentication(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}
