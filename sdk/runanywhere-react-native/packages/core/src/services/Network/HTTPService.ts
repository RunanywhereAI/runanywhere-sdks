/**
 * HTTPService.ts
 *
 * Core HTTP service implementation using fetch (built-in to React Native).
 * All network logic is centralized here.
 *
 * This is analogous to Swift's URLSession - using the platform's native HTTP client.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Services/HTTPService.swift
 */

// React Native global types
declare const fetch: (url: string, init?: RequestInit) => Promise<Response>;
declare const setTimeout: (callback: () => void, ms: number) => number;
declare const clearTimeout: (id: number) => void;
declare const AbortController: {
  new (): {
    signal: AbortSignal;
    abort(): void;
  };
};

interface RequestInit {
  method?: string;
  headers?: Record<string, string>;
  body?: string;
  signal?: AbortSignal;
}

interface AbortSignal {
  aborted: boolean;
}

interface Response {
  ok: boolean;
  status: number;
  statusText: string;
  text(): Promise<string>;
  json(): Promise<unknown>;
}

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { SDKError } from '../../Foundation/ErrorTypes';
import { ErrorCode } from '../../Foundation/ErrorTypes/ErrorCodes';
import { SDKConstants } from '../../Foundation/Constants';

const logger = new SDKLogger('HTTPService');

// SDK Constants - use centralized constants where available
const SDK_CLIENT = 'RunAnywhereSDK';
const SDK_PLATFORM = 'react-native';
const DEFAULT_TIMEOUT_MS = 30000;

/**
 * SDK Environment enum matching Swift/C++ SDKEnvironment
 * Uses string values to match types/enums.ts
 */
export enum SDKEnvironment {
  Development = 'development',
  Staging = 'staging',
  Production = 'production',
}

/**
 * HTTP Service Configuration
 */
export interface HTTPServiceConfig {
  /** Base URL for API requests */
  baseURL: string;
  /** API key for authentication */
  apiKey: string;
  /** SDK environment */
  environment: SDKEnvironment;
  /** Request timeout in milliseconds */
  timeoutMs?: number;
}

/**
 * Development (Supabase) Configuration
 */
export interface DevModeConfig {
  /** Supabase project URL */
  supabaseURL: string;
  /** Supabase anon key */
  supabaseKey: string;
}

/**
 * HTTP Service - Core network implementation using fetch
 *
 * Centralized HTTP transport layer modeled after Swift's URLSession approach.
 * Uses fetch - the built-in HTTP client in React Native.
 *
 * Features:
 * - Environment-aware routing (Supabase for dev, Railway for prod)
 * - Automatic header management
 * - Proper timeout and error handling
 * - Device registration with Supabase UPSERT support
 *
 * Usage:
 * ```typescript
 * // Configure (called during SDK init)
 * HTTPService.shared.configure({
 *   baseURL: 'https://api.runanywhere.ai',
 *   apiKey: 'your-api-key',
 *   environment: SDKEnvironment.Production,
 * });
 *
 * // Make requests
 * const response = await HTTPService.shared.post('/api/v1/devices/register', deviceData);
 * ```
 */
export class HTTPService {
  // ============================================================================
  // Singleton
  // ============================================================================

  private static _instance: HTTPService | null = null;

  /**
   * Get shared HTTPService instance
   */
  static get shared(): HTTPService {
    if (!HTTPService._instance) {
      HTTPService._instance = new HTTPService();
    }
    return HTTPService._instance;
  }

  // ============================================================================
  // Configuration
  // ============================================================================

  private baseURL: string = '';
  private apiKey: string = '';
  private environment: SDKEnvironment = SDKEnvironment.Production;
  private accessToken: string | null = null;
  private timeoutMs: number = DEFAULT_TIMEOUT_MS;

  // Development mode (Supabase)
  private supabaseURL: string = '';
  private supabaseKey: string = '';

  // ============================================================================
  // Initialization
  // ============================================================================

  private constructor() {}

  private get defaultHeaders(): Record<string, string> {
    return {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-SDK-Client': SDK_CLIENT,
      'X-SDK-Version': SDKConstants.version,
      'X-Platform': SDK_PLATFORM,
    };
  }

  // ============================================================================
  // Configuration Methods
  // ============================================================================

  /**
   * Configure HTTP service with base URL and API key
   */
  configure(config: HTTPServiceConfig): void {
    this.baseURL = config.baseURL;
    this.apiKey = config.apiKey;
    this.environment = config.environment;
    this.timeoutMs = config.timeoutMs || DEFAULT_TIMEOUT_MS;

    logger.info(
      `Configured for ${this.getEnvironmentName()} environment: ${this.getHostname(config.baseURL)}`
    );
  }

  /**
   * Configure development mode with Supabase credentials
   *
   * When in development mode, SDK makes calls directly to Supabase
   * instead of going through the Railway backend.
   */
  configureDev(config: DevModeConfig): void {
    this.supabaseURL = config.supabaseURL;
    this.supabaseKey = config.supabaseKey;

    logger.info('Development mode configured with Supabase');
  }

  /**
   * Set authorization token
   */
  setToken(token: string): void {
    this.accessToken = token;
    logger.debug('Access token set');
  }

  /**
   * Clear authorization token
   */
  clearToken(): void {
    this.accessToken = null;
    logger.debug('Access token cleared');
  }

  /**
   * Check if HTTP service is configured
   */
  get isConfigured(): boolean {
    if (this.environment === SDKEnvironment.Development) {
      return !!this.supabaseURL;
    }
    return !!this.baseURL && !!this.apiKey;
  }

  /**
   * Get current base URL
   */
  get currentBaseURL(): string {
    if (this.environment === SDKEnvironment.Development && this.supabaseURL) {
      return this.supabaseURL;
    }
    return this.baseURL;
  }

  // ============================================================================
  // HTTP Methods
  // ============================================================================

  /**
   * POST request with JSON body
   *
   * @param path API endpoint path
   * @param data Request body (will be JSON serialized)
   * @returns Response data
   */
  async post<T = unknown, R = unknown>(path: string, data?: T): Promise<R> {
    let url = this.buildFullURL(path);

    // Handle device registration - add UPSERT for Supabase
    const isDeviceReg = this.isDeviceRegistrationPath(path);
    const headers = this.buildHeaders(isDeviceReg);

    if (isDeviceReg && this.environment === SDKEnvironment.Development) {
      const separator = url.includes('?') ? '&' : '?';
      url = `${url}${separator}on_conflict=device_id`;
    }

    const response = await this.executeRequest('POST', url, headers, data);

    // Handle 409 as success for device registration (device already exists)
    if (isDeviceReg && response.status === 409) {
      logger.info('Device already registered (409) - treating as success');
      return this.parseResponse<R>(response);
    }

    return this.handleResponse<R>(response, path);
  }

  /**
   * GET request
   *
   * @param path API endpoint path
   * @returns Response data
   */
  async get<R = unknown>(path: string): Promise<R> {
    const url = this.buildFullURL(path);
    const headers = this.buildHeaders(false);

    const response = await this.executeRequest('GET', url, headers);
    return this.handleResponse<R>(response, path);
  }

  /**
   * PUT request
   *
   * @param path API endpoint path
   * @param data Request body
   * @returns Response data
   */
  async put<T = unknown, R = unknown>(path: string, data?: T): Promise<R> {
    const url = this.buildFullURL(path);
    const headers = this.buildHeaders(false);

    const response = await this.executeRequest('PUT', url, headers, data);
    return this.handleResponse<R>(response, path);
  }

  /**
   * DELETE request
   *
   * @param path API endpoint path
   * @returns Response data
   */
  async delete<R = unknown>(path: string): Promise<R> {
    const url = this.buildFullURL(path);
    const headers = this.buildHeaders(false);

    const response = await this.executeRequest('DELETE', url, headers);
    return this.handleResponse<R>(response, path);
  }

  /**
   * POST request with raw response (returns raw data)
   *
   * @param path API endpoint path
   * @param data Request body
   * @returns Raw response data as string
   */
  async postRaw(path: string, data?: unknown): Promise<string> {
    const response = await this.post<unknown, unknown>(path, data);
    return typeof response === 'string' ? response : JSON.stringify(response);
  }

  /**
   * GET request with raw response
   *
   * @param path API endpoint path
   * @returns Raw response data as string
   */
  async getRaw(path: string): Promise<string> {
    const response = await this.get<unknown>(path);
    return typeof response === 'string' ? response : JSON.stringify(response);
  }

  // ============================================================================
  // Private Implementation
  // ============================================================================

  private async executeRequest<T>(
    method: string,
    url: string,
    headers: Record<string, string>,
    data?: T
  ): Promise<Response> {
    logger.debug(`${method} ${url}`);

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const options: RequestInit = {
        method,
        headers,
        signal: controller.signal,
      };

      if (data !== undefined && method !== 'GET') {
        options.body = JSON.stringify(data);
      }

      const response = await fetch(url, options);
      return response;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  private buildHeaders(isDeviceRegistration: boolean): Record<string, string> {
    const headers: Record<string, string> = { ...this.defaultHeaders };

    if (this.environment === SDKEnvironment.Development) {
      // Development mode - use Supabase headers
      // Supabase requires BOTH apikey AND Authorization: Bearer headers
      if (this.supabaseKey) {
        headers['apikey'] = this.supabaseKey;
        headers['Authorization'] = `Bearer ${this.supabaseKey}`;
        headers['Prefer'] = isDeviceRegistration
          ? 'resolution=merge-duplicates'
          : 'return=representation';
      }
    } else {
      // Production/Staging - use Bearer token
      const token = this.accessToken || this.apiKey;
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
    }

    return headers;
  }

  private buildFullURL(path: string): string {
    // Handle full URLs
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    const base = this.currentBaseURL.replace(/\/$/, '');
    const endpoint = path.startsWith('/') ? path : `/${path}`;
    return `${base}${endpoint}`;
  }

  private isDeviceRegistrationPath(path: string): boolean {
    return (
      path.includes('sdk_devices') ||
      path.includes('devices/register') ||
      path.includes('rest/v1/sdk_devices')
    );
  }

  private async parseResponse<R>(response: Response): Promise<R> {
    const text = await response.text();
    if (!text) {
      return {} as R;
    }
    try {
      return JSON.parse(text) as R;
    } catch {
      return text as unknown as R;
    }
  }

  private async handleResponse<R>(response: Response, path: string): Promise<R> {
    if (response.ok) {
      return this.parseResponse<R>(response);
    }

    // Parse error response
    let errorMessage = `HTTP ${response.status}`;
    try {
      const errorData = (await response.json()) as Record<string, unknown>;
      errorMessage =
        (errorData.message as string) ||
        (errorData.error as string) ||
        (errorData.hint as string) ||
        errorMessage;
    } catch {
      // Ignore JSON parse errors
    }

    logger.error(`HTTP ${response.status}: ${path}`);
    throw this.createError(response.status, errorMessage, path);
  }

  private createError(statusCode: number, message: string, path: string): SDKError {
    switch (statusCode) {
      case 400:
        return new SDKError(ErrorCode.InvalidInput, `Bad request: ${message}`);
      case 401:
        return new SDKError(ErrorCode.AuthenticationFailed, message);
      case 403:
        return new SDKError(ErrorCode.AuthenticationFailed, `Forbidden: ${message}`);
      case 404:
        return new SDKError(ErrorCode.ApiError, `Not found: ${path}`);
      case 429:
        return new SDKError(ErrorCode.NetworkTimeout, `Rate limited: ${message}`);
      case 500:
      case 502:
      case 503:
      case 504:
        return new SDKError(ErrorCode.ApiError, `Server error (${statusCode}): ${message}`);
      default:
        return new SDKError(ErrorCode.NetworkUnavailable, `HTTP ${statusCode}: ${message}`);
    }
  }

  private getEnvironmentName(): string {
    switch (this.environment) {
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

  private getHostname(url: string): string {
    // Simple hostname extraction for React Native compatibility
    const match = url.match(/^https?:\/\/([^/:]+)/);
    return match ? match[1] : url.substring(0, 30);
  }
}

export default HTTPService;
