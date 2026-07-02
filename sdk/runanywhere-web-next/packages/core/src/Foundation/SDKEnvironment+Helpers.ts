import { LogLevel } from '@runanywhere/proto-ts/logging';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

export function environmentDeployableCases(): SDKEnvironment[] {
  return [
    SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
    SDKEnvironment.SDK_ENVIRONMENT_STAGING,
    SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
  ];
}

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

export function environmentIsProduction(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
}

export function environmentIsTesting(env: SDKEnvironment): boolean {
  const normalized = normalizedEnvironment(env);
  return (
    normalized === SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT ||
    normalized === SDKEnvironment.SDK_ENVIRONMENT_STAGING
  );
}

export function environmentRequiresBackendURL(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

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

export function environmentShouldSendTelemetry(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
}

export function environmentShouldSyncWithBackend(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

export function environmentRequiresAuthentication(env: SDKEnvironment): boolean {
  return normalizedEnvironment(env) !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}
