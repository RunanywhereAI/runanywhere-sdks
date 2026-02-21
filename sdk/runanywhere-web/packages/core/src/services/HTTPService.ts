/**
 * HTTPService.ts
 *
 * Core HTTP service for the RunAnywhere Web SDK.
 * Ported from sdk/runanywhere-react-native/packages/core/src/services/Network/HTTPService.ts
 * Adapted for browser (uses native fetch, AbortController, setTimeout globals).
 *
 * Responsibilities:
 * - Centralized HTTP transport layer for telemetry, device registration, etc.
 * - Environment-aware routing (Supabase for dev, Railway for prod/staging)
 * - Automatic header management (API key, auth tokens, SDK metadata)
 */

import { SDKLogger } from '../Foundation/SDKLogger';
import { SDKError, SDKErrorCode } from '../Foundation/ErrorTypes';
import { SDKEnvironment } from '../types/enums';

const logger = new SDKLogger('HTTPService');

const SDK_CLIENT = 'RunAnywhereSDK';
const SDK_PLATFORM = 'web';
const SDK_VERSION = '0.1.0-beta.8';
const DEFAULT_TIMEOUT_MS = 30000;
const DEVICE_ID_KEY = 'rac_device_id';
const TELEMETRY_TABLE = 'rest/v1/telemetry_events';

// NOTE: TELEMETRY_COLUMNS filter removed — all telemetry now flows through
// the C++ telemetry manager via AnalyticsEmitter → rac_analytics_emit_*().

/**
 * HTTP Service Configuration for non-dev environments.
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
 * HTTPService - Centralized HTTP transport layer for the Web SDK.
 *
 * Environment-aware routing:
 * - Development: Supabase credentials compiled into WASM (rac_dev_config_*)
 * - Staging/Production: Railway backend with API key
 */
export class HTTPService {
  private static _instance: HTTPService | null = null;

  static get shared(): HTTPService {
    if (!HTTPService._instance) {
      HTTPService._instance = new HTTPService();
    }
    return HTTPService._instance;
  }

  private baseURL: string = '';
  private apiKey: string = '';
  private environment: SDKEnvironment = SDKEnvironment.Production;
  private accessToken: string | null = null;
  private timeoutMs: number = DEFAULT_TIMEOUT_MS;

  private supabaseURL: string = '';
  private supabaseKey: string = '';

  private constructor() {}

  private get defaultHeaders(): Record<string, string> {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-SDK-Client': SDK_CLIENT,
      'X-SDK-Version': SDK_VERSION,
      'X-Platform': SDK_PLATFORM,
    };
  }

  // ---------------------------------------------------------------------------
  // Telemetry helpers
  // ---------------------------------------------------------------------------

  /**
   * @deprecated Use `AnalyticsEmitter` instead.  All telemetry now routes
   * through the C++ telemetry manager via `rac_analytics_emit_*()`.
   * Kept as a fallback for edge cases where C++ is unavailable.
   */
  postTelemetryEvent(partialPayload: Record<string, unknown>): void {
    if (!this.isConfigured) return;

    const payload: Record<string, unknown> = {
      sdk_event_id: crypto.randomUUID(),
      event_timestamp: new Date().toISOString(),
      created_at: new Date().toISOString(),
      device_id: this.getOrCreateDeviceId(),
      platform: SDK_PLATFORM,
      sdk_version: SDK_VERSION,
      ...partialPayload,
    };

    const url = this.buildFullURL(TELEMETRY_TABLE);
    const headers = this.buildHeaders(false);
    this.executeRequest('POST', url, headers, [payload]).catch(() => { /* silent */ });
  }

  /**
   * Returns the persistent device UUID, creating one if it doesn't exist.
   * Mirrors getOrCreateDeviceId() in TelemetryService.ts.
   */
  getOrCreateDeviceId(): string {
    try {
      const existing = localStorage.getItem(DEVICE_ID_KEY);
      if (existing) return existing;
      const id = crypto.randomUUID();
      localStorage.setItem(DEVICE_ID_KEY, id);
      return id;
    } catch {
      return crypto.randomUUID();
    }
  }

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  configure(config: HTTPServiceConfig): void {
    this.baseURL = config.baseURL;
    this.apiKey = config.apiKey;
    this.environment = config.environment;
    this.timeoutMs = config.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    logger.info(`Configured for ${config.environment} environment`);
  }

  /**
   * Configure development mode using Supabase credentials.
   * Called during WASM init using credentials read from rac_dev_config_*.
   */
  configureDev(config: DevModeConfig): void {
    this.supabaseURL = config.supabaseURL;
    this.supabaseKey = config.supabaseKey;
    this.environment = SDKEnvironment.Development;
    logger.info('Development mode configured with Supabase');
  }

  setToken(token: string): void {
    this.accessToken = token;
  }

  clearToken(): void {
    this.accessToken = null;
  }

  get isConfigured(): boolean {
    if (this.environment === SDKEnvironment.Development) {
      return !!this.supabaseURL;
    }
    return !!this.baseURL && !!this.apiKey;
  }

  get currentBaseURL(): string {
    if (this.environment === SDKEnvironment.Development && this.supabaseURL) {
      return this.supabaseURL;
    }
    return this.baseURL;
  }

  // ---------------------------------------------------------------------------
  // HTTP Methods
  // ---------------------------------------------------------------------------

  async post<T = unknown, R = unknown>(path: string, data?: T): Promise<R> {
    let url = this.buildFullURL(path);
    const isDeviceReg = this.isDeviceRegistrationPath(path);
    const headers = this.buildHeaders(isDeviceReg);

    if (isDeviceReg && this.environment === SDKEnvironment.Development) {
      const separator = url.includes('?') ? '&' : '?';
      url = `${url}${separator}on_conflict=device_id`;
    }

    const response = await this.executeRequest('POST', url, headers, data);

    if (isDeviceReg && response.status === 409) {
      logger.info('Device already registered (409) — treating as success');
      return this.parseResponse<R>(response);
    }

    return this.handleResponse<R>(response, path);
  }

  async get<R = unknown>(path: string): Promise<R> {
    const url = this.buildFullURL(path);
    const headers = this.buildHeaders(false);
    const response = await this.executeRequest('GET', url, headers);
    return this.handleResponse<R>(response, path);
  }

  async delete<R = unknown>(path: string): Promise<R> {
    const url = this.buildFullURL(path);
    const headers = this.buildHeaders(false);
    const response = await this.executeRequest('DELETE', url, headers);
    return this.handleResponse<R>(response, path);
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  private async executeRequest<T>(
    method: string,
    url: string,
    headers: Record<string, string>,
    data?: T,
  ): Promise<Response> {
    logger.debug(`${method} ${url}`);

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const options: RequestInit = { method, headers, signal: controller.signal };
      if (data !== undefined && method !== 'GET') {
        options.body = JSON.stringify(data);
      }
      return await fetch(url, options);
    } finally {
      clearTimeout(timeoutId);
    }
  }

  private buildHeaders(isDeviceRegistration: boolean): Record<string, string> {
    const headers = { ...this.defaultHeaders };

    if (this.environment === SDKEnvironment.Development) {
      if (this.supabaseKey) {
        headers['apikey'] = this.supabaseKey;
        headers['Authorization'] = `Bearer ${this.supabaseKey}`;
        headers['Prefer'] = isDeviceRegistration ? 'resolution=merge-duplicates' : 'return=representation';
      }
    } else {
      const token = this.accessToken || this.apiKey;
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
    }

    return headers;
  }

  private buildFullURL(path: string): string {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    const base = this.currentBaseURL.replace(/\/$/, '');
    const endpoint = path.startsWith('/') ? path : `/${path}`;
    return `${base}${endpoint}`;
  }

  private isDeviceRegistrationPath(path: string): boolean {
    return path.includes('sdk_devices') || path.includes('devices/register') || path.includes('rest/v1/sdk_devices');
  }

  private async parseResponse<R>(response: Response): Promise<R> {
    const text = await response.text();
    if (!text) return {} as R;
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

    let errorMessage = `HTTP ${response.status}`;
    try {
      const errorData = (await response.json()) as Record<string, unknown>;
      errorMessage = (errorData.message as string) || (errorData.error as string) || errorMessage;
    } catch {
      // ignore
    }

    // Telemetry failures are non-critical — log at debug level only
    if (path.includes('telemetry')) {
      logger.debug(`HTTP ${response.status}: ${path}`);
    } else {
      logger.error(`HTTP ${response.status}: ${path}`);
    }
    throw this.mapHttpError(response.status, errorMessage);
  }

  private mapHttpError(status: number, message: string): SDKError {
    switch (status) {
      case 401:
      case 403:
        return new SDKError(SDKErrorCode.AuthenticationFailed, message);
      case 408:
      case 429:
        return new SDKError(SDKErrorCode.NetworkTimeout, message);
      default:
        return new SDKError(SDKErrorCode.NetworkError, `HTTP ${status}: ${message}`);
    }
  }
}
