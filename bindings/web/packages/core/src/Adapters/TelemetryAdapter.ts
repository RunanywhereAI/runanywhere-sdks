/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Browser telemetry delivery. Mirrors the desktop bindings
 * (electron_telemetry_http_callback / py_telemetry_http_callback): it creates a
 * commons telemetry manager, installs it as the SDK event sink, and forwards
 * each queued batch to the backend over the browser's fetch transport, calling
 * rac_telemetry_manager_http_complete when the request settles.
 *
 * Without this the web SDK loaded commons but never routed SDK analytics events
 * anywhere — device registration went out (DeviceRegistrationAdapter) but no
 * llm/stt/tts/generation telemetry did.
 */

import { SDKLogger } from '../Foundation/SDKLogger.js';
import type { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

const logger = new SDKLogger('TelemetryAdapter');

// rac_environment_t (rac_environment.h): DEVELOPMENT=0, PRODUCTION=2.
const RAC_ENV_DEVELOPMENT = 0;
const RAC_ENV_PRODUCTION = 2;
// runanywhere.v1.SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION wire value.
const PROTO_ENV_PRODUCTION = 3;

const DEFAULT_TIMEOUT_MS = 15_000;
// The commons telemetry manager's own periodic flush runs on a background
// thread that is not reliable under the browser's WASM threading, so the
// browser drives the flush cadence from JS instead.
const FLUSH_INTERVAL_MS = 8_000;

/** Minimal view of the emscripten module surface this adapter needs. */
export interface TelemetryModule {
  _malloc(size: number): number;
  _free(ptr: number): void;
  UTF8ToString(ptr: number, maxRead?: number): string;
  lengthBytesUTF8(value: string): number;
  stringToUTF8(value: string, ptr: number, maxBytes: number): void;
  addFunction(fn: (...args: number[]) => void, signature: string): number;
  removeFunction(ptr: number): void;
  _rac_telemetry_manager_create(
    env: number,
    deviceIdPtr: number,
    platformPtr: number,
    sdkVersionPtr: number,
  ): number;
  _rac_telemetry_manager_set_http_callback(managerPtr: number, callbackPtr: number, userData: number): void;
  _rac_telemetry_manager_http_complete(
    managerPtr: number,
    success: number,
    responsePtr: number,
    errorPtr: number,
  ): void;
  _rac_telemetry_manager_flush(managerPtr: number): number;
  _rac_telemetry_manager_destroy(managerPtr: number): void;
  _rac_events_set_telemetry_sink(managerPtr: number): void;
  _rac_state_get_device_id?(): number;
  _rac_auth_get_access_token?(): number;
}

const REQUIRED_EXPORTS: ReadonlyArray<keyof TelemetryModule> = [
  '_rac_telemetry_manager_create',
  '_rac_telemetry_manager_set_http_callback',
  '_rac_telemetry_manager_http_complete',
  '_rac_telemetry_manager_flush',
  '_rac_telemetry_manager_destroy',
  '_rac_events_set_telemetry_sink',
];

export interface TelemetryConfiguration {
  baseURL?: string;
  environment: SDKEnvironment;
  sdkVersion: string;
  requestTimeoutMs?: number;
}

/** Build the absolute control-plane URL, rejecting credential-bearing bases. */
function resolveTelemetryURL(baseURL: string, endpoint: string): string | null {
  const trimmed = baseURL.trim().replace(/\/+$/, '');
  if (!trimmed || !endpoint.startsWith('/') || endpoint.startsWith('//')) return null;
  try {
    const base = new URL(trimmed);
    if (
      (base.protocol !== 'https:' && base.protocol !== 'http:')
      || base.username.length > 0
      || base.password.length > 0
      || base.search.length > 0
      || base.hash.length > 0
    ) {
      return null;
    }
    return `${trimmed}/${endpoint.replace(/^\/+/, '')}`;
  } catch {
    return null;
  }
}

export class TelemetryAdapter {
  private managerPtr = 0;
  private callbackPtr = 0;
  private disposed = false;
  private flushTimer: ReturnType<typeof setInterval> | null = null;

  private constructor(
    private readonly module: TelemetryModule,
    private readonly baseURL: string,
    private readonly sdkVersion: string,
    private readonly requestTimeoutMs: number,
  ) {}

  /**
   * Create the telemetry manager, install the fetch-backed HTTP callback, and
   * register it as the SDK event sink. Returns null (leaving telemetry off) if
   * the module lacks the exports or the manager cannot be created — telemetry
   * is best-effort and must never block initialization.
   */
  static install(module: TelemetryModule, configuration: TelemetryConfiguration): TelemetryAdapter | null {
    for (const name of REQUIRED_EXPORTS) {
      if (typeof module[name] !== 'function') {
        logger.warning(`Telemetry disabled: module missing ${String(name)}.`);
        return null;
      }
    }

    const baseURL = configuration.baseURL?.trim() ?? '';
    const sdkVersion = configuration.sdkVersion;
    const timeout = Math.trunc(configuration.requestTimeoutMs ?? DEFAULT_TIMEOUT_MS);
    const adapter = new TelemetryAdapter(module, baseURL, sdkVersion, timeout > 0 ? timeout : DEFAULT_TIMEOUT_MS);

    const env = configuration.environment === PROTO_ENV_PRODUCTION ? RAC_ENV_PRODUCTION : RAC_ENV_DEVELOPMENT;
    const deviceId = adapter.readNativeString(module._rac_state_get_device_id);

    const deviceIdPtr = adapter.allocString(deviceId);
    const platformPtr = adapter.allocString('web');
    const sdkVersionPtr = adapter.allocString(sdkVersion);
    try {
      adapter.managerPtr = module._rac_telemetry_manager_create(env, deviceIdPtr, platformPtr, sdkVersionPtr);
    } finally {
      module._free(deviceIdPtr);
      module._free(platformPtr);
      module._free(sdkVersionPtr);
    }
    if (!adapter.managerPtr) {
      logger.warning('Telemetry disabled: rac_telemetry_manager_create returned null.');
      return null;
    }

    // Signature: void (i32 userData, i32 endpoint, i32 jsonBody, i32 jsonLen, i32 requiresAuth).
    adapter.callbackPtr = module.addFunction(
      (
        _userData: number,
        endpointPtr: number,
        jsonBodyPtr: number,
        jsonLength: number,
        requiresAuth: number,
      ) => adapter.onHttpRequest(endpointPtr, jsonBodyPtr, jsonLength, requiresAuth),
      'viiiii',
    );
    module._rac_telemetry_manager_set_http_callback(adapter.managerPtr, adapter.callbackPtr, 0);
    module._rac_events_set_telemetry_sink(adapter.managerPtr);
    adapter.flushTimer = setInterval(() => adapter.flushSafely(), FLUSH_INTERVAL_MS);
    logger.info('Telemetry event delivery installed.');
    return adapter;
  }

  private onHttpRequest(endpointPtr: number, jsonBodyPtr: number, jsonLength: number, requiresAuth: number): void {
    if (this.disposed || !endpointPtr || !jsonBodyPtr) {
      this.complete(false, null, 'telemetry request had no payload');
      return;
    }
    const endpoint = this.module.UTF8ToString(endpointPtr);
    const jsonBody = this.module.UTF8ToString(jsonBodyPtr, jsonLength > 0 ? jsonLength : undefined);
    const url = this.baseURL ? resolveTelemetryURL(this.baseURL, endpoint) : null;
    if (!url) {
      this.complete(false, null, 'telemetry base URL unavailable');
      return;
    }

    const headers = new Headers({
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-SDK-Client': 'RunAnywhereSDK',
      'X-SDK-Version': this.sdkVersion,
      'X-Platform': 'web',
    });
    if (requiresAuth !== 0) {
      const token = this.readNativeString(this.module._rac_auth_get_access_token);
      if (token) headers.set('Authorization', `Bearer ${token}`);
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.requestTimeoutMs);
    fetch(url, { method: 'POST', headers, body: jsonBody, signal: controller.signal })
      .then(async (response) => {
        const text = await response.text().catch(() => '');
        this.complete(response.ok, text || null, response.ok ? null : `HTTP ${response.status}`);
      })
      .catch((error: unknown) => {
        const message = controller.signal.aborted ? 'telemetry request timed out' : String(error);
        this.complete(false, null, message);
      })
      .finally(() => clearTimeout(timer));
  }

  private complete(success: boolean, responseBody: string | null, errorMessage: string | null): void {
    if (this.disposed || !this.managerPtr) return;
    const responsePtr = responseBody ? this.allocString(responseBody) : 0;
    const errorPtr = errorMessage ? this.allocString(errorMessage) : 0;
    try {
      this.module._rac_telemetry_manager_http_complete(this.managerPtr, success ? 1 : 0, responsePtr, errorPtr);
    } finally {
      if (responsePtr) this.module._free(responsePtr);
      if (errorPtr) this.module._free(errorPtr);
    }
  }

  private flushSafely(): void {
    if (this.disposed || !this.managerPtr) return;
    try {
      this.module._rac_telemetry_manager_flush(this.managerPtr);
    } catch {
      // Best-effort: a failed flush must not break the interval or the app.
    }
  }

  /** Flush queued events, detach the sink, and free native + table resources. */
  uninstall(): void {
    if (this.disposed) return;
    this.disposed = true;
    if (this.flushTimer !== null) {
      clearInterval(this.flushTimer);
      this.flushTimer = null;
    }
    try {
      if (this.managerPtr) this.module._rac_telemetry_manager_flush(this.managerPtr);
      this.module._rac_events_set_telemetry_sink(0);
    } catch {
      logger.warning('Telemetry flush during teardown did not complete.');
    }
    if (this.managerPtr) {
      this.module._rac_telemetry_manager_destroy(this.managerPtr);
      this.managerPtr = 0;
    }
    if (this.callbackPtr) {
      this.module.removeFunction(this.callbackPtr);
      this.callbackPtr = 0;
    }
  }

  private allocString(value: string): number {
    const size = this.module.lengthBytesUTF8(value) + 1;
    const ptr = this.module._malloc(size);
    this.module.stringToUTF8(value, ptr, size);
    return ptr;
  }

  private readNativeString(fn?: () => number): string {
    if (typeof fn !== 'function') return '';
    try {
      const ptr = fn.call(this.module);
      return ptr ? this.module.UTF8ToString(ptr) : '';
    } catch {
      return '';
    }
  }
}
