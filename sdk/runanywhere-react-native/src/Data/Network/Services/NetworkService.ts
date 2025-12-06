/**
 * NetworkService.ts
 *
 * Protocol defining the network service interface
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Protocols/NetworkService.swift
 */

/**
 * API endpoint
 */
export interface APIEndpoint {
  readonly path: string;
  readonly method: 'GET' | 'POST' | 'PUT' | 'DELETE';
}

/**
 * Protocol defining the network service interface
 */
export interface NetworkService {
  /**
   * Perform a POST request
   */
  post<T, R>(endpoint: APIEndpoint, payload: T, requiresAuth?: boolean): Promise<R>;

  /**
   * Perform a GET request
   */
  get<R>(endpoint: APIEndpoint, requiresAuth?: boolean): Promise<R>;

  /**
   * Perform a raw POST request (returns Data)
   */
  postRaw(endpoint: APIEndpoint, payload: ArrayBuffer, requiresAuth?: boolean): Promise<ArrayBuffer>;

  /**
   * Perform a raw GET request (returns Data)
   */
  getRaw(endpoint: APIEndpoint, requiresAuth?: boolean): Promise<ArrayBuffer>;
}

/**
 * Simple network service implementation
 */
export class NetworkServiceImpl implements NetworkService {
  private baseURL: string;
  private apiKey: string | null;

  constructor(baseURL: string, apiKey?: string | null) {
    this.baseURL = baseURL;
    this.apiKey = apiKey ?? null;
  }

  public async post<T, R>(
    endpoint: APIEndpoint,
    payload: T,
    requiresAuth: boolean = true
  ): Promise<R> {
    const data = JSON.stringify(payload);
    const encoded = new TextEncoder().encode(data);
    const arrayBuffer = encoded.buffer.slice(encoded.byteOffset, encoded.byteOffset + encoded.byteLength) as ArrayBuffer;
    const responseData = await this.postRaw(endpoint, arrayBuffer, requiresAuth);
    const text = new TextDecoder().decode(responseData);
    return JSON.parse(text) as R;
  }

  public async get<R>(
    endpoint: APIEndpoint,
    requiresAuth: boolean = true
  ): Promise<R> {
    const responseData = await this.getRaw(endpoint, requiresAuth);
    const text = new TextDecoder().decode(responseData);
    return JSON.parse(text) as R;
  }

  public async postRaw(
    endpoint: APIEndpoint,
    payload: ArrayBuffer,
    requiresAuth: boolean = true
  ): Promise<ArrayBuffer> {
    const url = `${this.baseURL}${endpoint.path}`;
    const headers: { [key: string]: string } = {
      'Content-Type': 'application/json',
    };

    if (requiresAuth && this.apiKey) {
      headers['Authorization'] = `Bearer ${this.apiKey}`;
    }

    const response = await fetch(url, {
      method: endpoint.method,
      headers,
      body: payload,
    });

    if (!response.ok) {
      throw new Error(`Network request failed: ${response.statusText}`);
    }

    const arrayBuffer = await response.arrayBuffer();
    return arrayBuffer;
  }

  public async getRaw(
    endpoint: APIEndpoint,
    requiresAuth: boolean = true
  ): Promise<ArrayBuffer> {
    const url = `${this.baseURL}${endpoint.path}`;
    const headers: { [key: string]: string } = {};

    if (requiresAuth && this.apiKey) {
      headers['Authorization'] = `Bearer ${this.apiKey}`;
    }

    const response = await fetch(url, {
      method: 'GET',
      headers,
    });

    if (!response.ok) {
      throw new Error(`Network request failed: ${response.statusText}`);
    }

    const arrayBuffer = await response.arrayBuffer();
    return arrayBuffer;
  }
}
