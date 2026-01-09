/**
 * Network Services
 *
 * Centralized network layer for RunAnywhere React Native SDK.
 * Uses axios for HTTP requests - the industry standard for JavaScript HTTP clients.
 */

// Core HTTP service
export { HTTPService, SDKEnvironment } from './HTTPService';
export type { HTTPServiceConfig, DevModeConfig } from './HTTPService';

// Configuration utilities
export {
  createNetworkConfig,
  getEnvironmentName,
  isDevelopment,
  isProduction,
  DEFAULT_BASE_URL,
  DEFAULT_TIMEOUT_MS,
} from './NetworkConfiguration';
export type { NetworkConfig } from './NetworkConfiguration';

// API endpoints
export { APIEndpoints } from './APIEndpoints';
export type { APIEndpointKey, APIEndpointValue } from './APIEndpoints';

// Telemetry
export { TelemetryService, TelemetryCategory } from './TelemetryService';
export type { TelemetryEvent } from './TelemetryService';
