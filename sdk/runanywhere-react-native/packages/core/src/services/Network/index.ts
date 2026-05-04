/**
 * Network Services
 *
 * HTTP transport is implemented entirely in native C++ (libcurl via
 * rac_http_client_*). This module only exposes the high-level configuration
 * types and telemetry facade the TypeScript layer still owns.
 */

export {
  createNetworkConfig,
  getEnvironmentName,
  looksLikePlaceholder,
  isUsableHttpUrl,
  isUsableCredential,
  hasUsableBackendConfig,
  hasUsableSupabaseConfig,
  isDevelopment,
  isProduction,
  DEFAULT_BASE_URL,
  DEFAULT_TIMEOUT_MS,
  SDKEnvironment,
} from './NetworkConfiguration';
export type { NetworkConfig } from './NetworkConfiguration';

export { APIEndpoints } from './APIEndpoints';
export type { APIEndpointKey, APIEndpointValue } from './APIEndpoints';

export { TelemetryService, TelemetryCategory } from './TelemetryService';
