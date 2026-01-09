/**
 * NetworkConfiguration.ts
 *
 * Network configuration types and utilities.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Services/HTTPService.swift
 */

import { SDKEnvironment } from './HTTPService';

export { SDKEnvironment };

/**
 * Network configuration options for SDK initialization
 */
export interface NetworkConfig {
  /**
   * Base URL for API requests
   * - Production: Railway endpoint (e.g., "https://api.runanywhere.ai")
   * - Development: Can be left empty if supabase config is provided
   */
  baseURL?: string;

  /**
   * API key for authentication
   * - Production: RunAnywhere API key
   * - Development: Build token
   */
  apiKey: string;

  /**
   * SDK environment
   * @default SDKEnvironment.Production
   */
  environment?: SDKEnvironment;

  /**
   * Supabase configuration for development mode
   * When provided in development mode, SDK makes calls directly to Supabase
   */
  supabase?: {
    url: string;
    anonKey: string;
  };

  /**
   * Request timeout in milliseconds
   * @default 30000
   */
  timeoutMs?: number;
}

/**
 * Default production base URL
 */
export const DEFAULT_BASE_URL = 'https://api.runanywhere.ai';

/**
 * Default timeout in milliseconds
 */
export const DEFAULT_TIMEOUT_MS = 30000;

/**
 * Create network configuration from SDK init options
 */
export function createNetworkConfig(options: {
  apiKey: string;
  baseURL?: string;
  environment?: 'development' | 'staging' | 'production';
  supabaseURL?: string;
  supabaseKey?: string;
  timeoutMs?: number;
}): NetworkConfig {
  // Map string environment to enum
  let environment = SDKEnvironment.Production;
  if (options.environment === 'development') {
    environment = SDKEnvironment.Development;
  } else if (options.environment === 'staging') {
    environment = SDKEnvironment.Staging;
  }

  // Build supabase config if provided
  const supabase =
    options.supabaseURL && options.supabaseKey
      ? {
          url: options.supabaseURL,
          anonKey: options.supabaseKey,
        }
      : undefined;

  return {
    baseURL: options.baseURL || DEFAULT_BASE_URL,
    apiKey: options.apiKey,
    environment,
    supabase,
    timeoutMs: options.timeoutMs || DEFAULT_TIMEOUT_MS,
  };
}

/**
 * Get environment name string
 */
export function getEnvironmentName(env: SDKEnvironment): string {
  switch (env) {
    case SDKEnvironment.Development:
      return 'development';
    case SDKEnvironment.Staging:
      return 'staging';
    case SDKEnvironment.Production:
      return 'production';
    default:
      return 'unknown';
  }
}

/**
 * Check if environment is development
 */
export function isDevelopment(env: SDKEnvironment): boolean {
  return env === SDKEnvironment.Development;
}

/**
 * Check if environment is production
 */
export function isProduction(env: SDKEnvironment): boolean {
  return env === SDKEnvironment.Production;
}

export default NetworkConfig;
