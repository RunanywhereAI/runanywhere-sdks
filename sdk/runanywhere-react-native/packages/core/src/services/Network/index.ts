/**
 * Network Services
 *
 * HTTP transport, telemetry, authentication, and device registration are
 * implemented in native commons. This module only exposes configuration
 * value helpers for TypeScript call sites.
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
