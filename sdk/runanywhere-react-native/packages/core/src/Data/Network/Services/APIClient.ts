/**
 * APIClient.ts
 *
 * HTTP client for RunAnywhere SDK API calls.
 * Implements iOS APIClient patterns:
 * - Bearer token injection via AuthenticationService
 * - SDK headers (X-SDK-Client, X-SDK-Version, X-Platform)
 * - Flexible error response parsing
 * - Typed request/response handling
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Services/APIClient.swift
 */

import type { APIEndpointDefinition } from '../APIEndpoint';
import type { NetworkService } from './NetworkService';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';

/**
 * SDK constants for request headers
 */
const SDK_CONSTANTS = {
  clientName: 'RunAnywhereSDK-RN',
  version: '0.1.0',
  platform: 'react-native',
} as const;

/**
 * Error response formats supported
 */
interface ErrorResponseFormat1 {
  detail: string;
}

interface ErrorResponseFormat2 {
  detail: Array<{ msg: string }>;
}

interface ErrorResponseFormat3 {
  message: string;
}

interface ErrorResponseFormat4 {
  error: string;
}

type ErrorResponse =
  | ErrorResponseFormat1
  | ErrorResponseFormat2
  | ErrorResponseFormat3
  | ErrorResponseFormat4;

/**
 * API Client Error
 *
 * Thrown when API requests fail
 */
export class APIClientError extends Error {
  /** HTTP status code */
  public readonly statusCode: number;
  /** Original response body */
  public readonly responseBody?: string;
  /** Parsed error details */
  public readonly details?: string;

  constructor(
    message: string,
    statusCode: number,
    responseBody?: string,
    details?: string
  ) {
    super(message);
    this.name = 'APIClientError';
    this.statusCode = statusCode;
    this.responseBody = responseBody;
    this.details = details;
  }

  /**
   * Create from HTTP response
   */
  static async fromResponse(response: Response): Promise<APIClientError> {
    const statusCode = response.status;
    let responseBody: string | undefined;
    let details: string | undefined;

    try {
      responseBody = await response.text();
      details = parseErrorMessage(responseBody, statusCode);
    } catch {
      details = `HTTP ${statusCode}`;
    }

    return new APIClientError(
      details ?? `Request failed with status ${statusCode}`,
      statusCode,
      responseBody,
      details
    );
  }
}

/**
 * Parse error message from response body
 *
 * Supports multiple error response formats (matching iOS):
 * 1. {"detail": "Error message"}
 * 2. {"detail": [{"msg": "Error 1"}, {"msg": "Error 2"}]}
 * 3. {"message": "Error message"}
 * 4. {"error": "Error message"}
 */
function parseErrorMessage(responseBody: string, statusCode: number): string {
  const defaultMessage = `HTTP ${statusCode}`;

  if (!responseBody) {
    return defaultMessage;
  }

  try {
    const errorData = JSON.parse(responseBody) as ErrorResponse;

    // Format 1: {"detail": "string"}
    if ('detail' in errorData && typeof errorData.detail === 'string') {
      return errorData.detail;
    }

    // Format 2: {"detail": [{"msg": "Error"}]}
    if ('detail' in errorData && Array.isArray(errorData.detail)) {
      const messages = (errorData.detail as Array<{ msg?: string }>)
        .map((item) => item.msg)
        .filter((msg): msg is string => typeof msg === 'string');
      if (messages.length > 0) {
        return messages.join(', ');
      }
    }

    // Format 3: {"message": "string"}
    if ('message' in errorData && typeof errorData.message === 'string') {
      return errorData.message;
    }

    // Format 4: {"error": "string"}
    if ('error' in errorData && typeof errorData.error === 'string') {
      return errorData.error;
    }
  } catch {
    // JSON parse failed, return default
  }

  return defaultMessage;
}

/**
 * Authentication provider interface
 *
 * Allows APIClient to get tokens without direct AuthenticationService dependency.
 * This avoids circular dependencies.
 */
export interface AuthenticationProvider {
  /**
   * Get the current access token
   * Should handle refresh automatically if needed
   * Returns null if no valid token is available
   */
  getAccessToken(): Promise<string | null>;
}

/**
 * API Client configuration
 */
export interface APIClientConfig {
  /** Base URL for API requests */
  baseURL: string;
  /** API key for unauthenticated requests */
  apiKey: string;
  /** Optional authentication provider for authenticated requests */
  authProvider?: AuthenticationProvider;
  /** Request timeout in milliseconds (default: 30000) */
  timeout?: number;
}

/**
 * APIClient
 *
 * Main HTTP client for SDK API calls.
 * Implements NetworkService interface for compatibility.
 */
export class APIClient implements NetworkService {
  private readonly logger = new SDKLogger('APIClient');
  private readonly baseURL: string;
  private readonly apiKey: string;
  private readonly timeout: number;
  private authProvider: AuthenticationProvider | null = null;

  constructor(config: APIClientConfig) {
    this.baseURL = config.baseURL.replace(/\/$/, ''); // Remove trailing slash
    this.apiKey = config.apiKey;
    this.timeout = config.timeout ?? 30000;
    this.authProvider = config.authProvider ?? null;
  }

  /**
   * Set the authentication provider
   *
   * Matches iOS: setAuthenticationService(_:)
   */
  setAuthenticationProvider(provider: AuthenticationProvider): void {
    this.authProvider = provider;
  }

  /**
   * Perform a typed POST request
   */
  async post<T, R>(
    endpoint: APIEndpointDefinition,
    payload: T,
    requiresAuth: boolean = true
  ): Promise<R> {
    const data = JSON.stringify(payload);
    const encoder = new TextEncoder();
    const arrayBuffer = encoder.encode(data).buffer as ArrayBuffer;
    const responseData = await this.postRaw(
      endpoint,
      arrayBuffer,
      requiresAuth
    );
    const decoder = new TextDecoder();
    const text = decoder.decode(responseData);
    return JSON.parse(text) as R;
  }

  /**
   * Perform a typed GET request
   */
  async get<R>(
    endpoint: APIEndpointDefinition,
    requiresAuth: boolean = true
  ): Promise<R> {
    const responseData = await this.getRaw(endpoint, requiresAuth);
    const decoder = new TextDecoder();
    const text = decoder.decode(responseData);
    return JSON.parse(text) as R;
  }

  /**
   * Perform a raw POST request
   */
  async postRaw(
    endpoint: APIEndpointDefinition,
    payload: ArrayBuffer,
    requiresAuth: boolean = true
  ): Promise<ArrayBuffer> {
    const url = this.buildURL(endpoint);
    const headers = await this.buildHeaders(requiresAuth);

    this.logger.debug(`POST ${endpoint.path}`);

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.timeout);

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers,
        body: payload,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      // POST accepts 200 or 201 (matching iOS)
      if (response.status !== 200 && response.status !== 201) {
        const error = await APIClientError.fromResponse(response);
        this.logger.error(`POST ${endpoint.path} failed: ${error.message}`);
        throw error;
      }

      return await response.arrayBuffer();
    } catch (error) {
      clearTimeout(timeoutId);

      if (error instanceof APIClientError) {
        throw error;
      }

      if ((error as Error).name === 'AbortError') {
        throw new APIClientError('Request timeout', 0);
      }

      throw new APIClientError(
        (error as Error).message ?? 'Network request failed',
        0
      );
    }
  }

  /**
   * Perform a raw GET request
   */
  async getRaw(
    endpoint: APIEndpointDefinition,
    requiresAuth: boolean = true
  ): Promise<ArrayBuffer> {
    const url = this.buildURL(endpoint);
    const headers = await this.buildHeaders(requiresAuth);

    this.logger.debug(`GET ${endpoint.path}`);

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.timeout);

    try {
      const response = await fetch(url, {
        method: 'GET',
        headers,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      // GET accepts 200 only (matching iOS)
      if (response.status !== 200) {
        const error = await APIClientError.fromResponse(response);
        this.logger.error(`GET ${endpoint.path} failed: ${error.message}`);
        throw error;
      }

      return await response.arrayBuffer();
    } catch (error) {
      clearTimeout(timeoutId);

      if (error instanceof APIClientError) {
        throw error;
      }

      if ((error as Error).name === 'AbortError') {
        throw new APIClientError('Request timeout', 0);
      }

      throw new APIClientError(
        (error as Error).message ?? 'Network request failed',
        0
      );
    }
  }

  /**
   * Build the full URL for an endpoint
   */
  private buildURL(endpoint: APIEndpointDefinition): string {
    // Handle paths that already start with /
    const path = endpoint.path.startsWith('/')
      ? endpoint.path
      : `/${endpoint.path}`;
    return `${this.baseURL}${path}`;
  }

  /**
   * Build request headers
   *
   * Matches iOS header configuration:
   * - Content-Type: application/json
   * - X-SDK-Client: RunAnywhereSDK
   * - X-SDK-Version: <version>
   * - X-Platform: <platform>
   * - apikey: <apiKey> (Supabase compatible)
   * - Prefer: return=representation (Supabase compatible)
   * - Authorization: Bearer <token>
   */
  private async buildHeaders(
    requiresAuth: boolean
  ): Promise<Record<string, string>> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'X-SDK-Client': SDK_CONSTANTS.clientName,
      'X-SDK-Version': SDK_CONSTANTS.version,
      'X-Platform': SDK_CONSTANTS.platform,
      // Supabase-compatible headers
      'apikey': this.apiKey,
      'Prefer': 'return=representation',
    };

    // Get token for Authorization header
    let token: string;

    if (requiresAuth && this.authProvider) {
      try {
        const accessToken = await this.authProvider.getAccessToken();
        token = accessToken ?? this.apiKey;
      } catch {
        this.logger.warning(
          'Failed to get access token, falling back to API key'
        );
        token = this.apiKey;
      }
    } else {
      // Use API key as bearer token for non-auth requests (Supabase compatibility)
      token = this.apiKey;
    }

    headers.Authorization = `Bearer ${token}`;

    return headers;
  }
}

/**
 * Create an APIClient instance
 */
export function createAPIClient(config: APIClientConfig): APIClient {
  return new APIClient(config);
}
