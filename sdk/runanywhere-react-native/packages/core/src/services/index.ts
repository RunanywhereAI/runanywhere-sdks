/**
 * RunAnywhere React Native SDK - Services
 *
 * Core services for SDK functionality.
 *
 * Model registry, downloads, archive extraction, and filesystem path policy
 * are owned by native commons (`runanywhere-commons`). The JS layer talks
 * to commons via Nitro proto-byte calls — there is no JS-side mirror.
 */

export type { ModelFileDescriptor } from '@runanywhere/proto-ts/model_types';

// Network Layer — HTTP transport, telemetry, auth, and device registration
// live in native commons. JS keeps only configuration value helpers.
export {
  SDKEnvironment,
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
  type NetworkConfig,
} from './Network';
