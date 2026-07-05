/**
 * TelemetryBridge.ts
 *
 * Worker-side wiring of the commons telemetry manager. Mirrors the iOS
 * `CppBridge+Telemetry` bridge: commons owns all event logic, JSON building and
 * batching; the SDK only supplies the HTTP transport for delivery.
 *
 * Why web needs this:
 *   The telemetry manager only flushes when an HTTP delivery is attached
 *   (`rac_telemetry_manager_set_http_callback` / `_set_http_wakeup`); with
 *   neither set, `rac_telemetry_manager_flush` is a no-op and no events ever
 *   leave the device. iOS (Swift) and Android (JNI) each create the manager and
 *   attach a platform HTTP callback, then register it as the event router's
 *   telemetry sink. web-next previously did neither, so no `web` telemetry rows
 *   were ever recorded.
 *
 * This runs in the WASM worker (where the manager, heap and `fetch` all live),
 * installed once during module load. The commons destination-bitmask router
 * (`rac::events::route`) then calls `rac_telemetry_manager_track_proto` for
 * every event carrying the TELEMETRY bit; batches are delivered here via the
 * HTTP callback.
 */

import { SDKLogger } from '../Foundation/SDKLogger';
import type { BootModule } from './WasmModuleLoader';

const logger = new SDKLogger('TelemetryBridge');

const RAC_TRUE = 1;

/** Telemetry endpoint paths are relative (see rac_endpoints.h); prepend baseUrl. */
export interface TelemetryInit {
  /** rac_environment_t integer: 0 development, 1 staging, 2 production. */
  environment: number;
  deviceId: string;
  platform: string;
  version: string;
  deviceModel: string;
  osVersion: string;
  /** Control-plane base URL (no trailing slash required). */
  baseUrl: string;
  /** API key sent as the `apikey` header, mirroring commons control-plane headers. */
  apiKey: string;
}

export interface TelemetryModule extends BootModule {
  _rac_telemetry_manager_create?(
    environment: number,
    deviceIdPtr: number,
    platformPtr: number,
    versionPtr: number,
  ): number;
  _rac_telemetry_manager_set_device_info?(mgr: number, modelPtr: number, osPtr: number): void;
  _rac_telemetry_manager_set_http_callback?(mgr: number, cbPtr: number, userData: number): void;
  _rac_telemetry_manager_flush?(mgr: number): number;
  _rac_telemetry_manager_destroy?(mgr: number): void;
  _rac_events_set_telemetry_sink?(mgr: number): void;
  _rac_auth_get_access_token?(): number;
}

/**
 * Worker-side telemetry manager owner. Created via `TelemetryBridge.install`;
 * holds the manager pointer and the `addFunction` HTTP-callback trampoline so
 * `uninstall()` can detach the sink and free the slot on teardown.
 */
export class TelemetryBridge {
  private managerPtr_ = 0;
  private callbackPtr = 0;

  private constructor(
    private readonly m: TelemetryModule,
    private readonly opts: TelemetryInit,
  ) {}

  /**
   * Create the telemetry manager, attach the HTTP delivery callback, and
   * register it as the commons event router's telemetry sink. Returns the
   * bridge, or `null` if the module lacks the required telemetry exports.
   */
  static install(m: TelemetryModule, opts: TelemetryInit): TelemetryBridge | null {
    if (
      typeof m._rac_telemetry_manager_create !== 'function' ||
      typeof m._rac_telemetry_manager_set_http_callback !== 'function' ||
      typeof m._rac_events_set_telemetry_sink !== 'function'
    ) {
      logger.warning('module missing telemetry exports; telemetry delivery disabled');
      return null;
    }
    const bridge = new TelemetryBridge(m, opts);
    if (!bridge.doInstall()) return null;
    return bridge;
  }

  /** Live telemetry-manager pointer (0 until installed). Used by the SDK to
   * track events (e.g. LLM generation) directly via rac_telemetry_manager_track_proto,
   * since the handle-less LLM proto path does not emit telemetry itself. */
  get managerPtr(): number {
    return this.managerPtr_;
  }

  /** Flush any queued telemetry batches immediately. */
  flush(): void {
    if (this.managerPtr_ !== 0 && typeof this.m._rac_telemetry_manager_flush === 'function') {
      try {
        this.m._rac_telemetry_manager_flush(this.managerPtr_);
      } catch (err) {
        logger.warning(`flush threw: ${err instanceof Error ? err.message : String(err)}`);
      }
    }
  }

  /** Detach the sink, destroy the manager, and free the callback slot. Idempotent. */
  uninstall(): void {
    try {
      this.m._rac_events_set_telemetry_sink?.(0);
    } catch {
      /* noop */
    }
    if (this.managerPtr_ !== 0) {
      try {
        this.m._rac_telemetry_manager_destroy?.(this.managerPtr_);
      } catch {
        /* noop */
      }
      this.managerPtr_ = 0;
    }
    if (this.callbackPtr !== 0) {
      try {
        this.m.removeFunction(this.callbackPtr);
      } catch {
        /* noop */
      }
      this.callbackPtr = 0;
    }
  }

  // ---------------------------------------------------------------------------

  private doInstall(): boolean {
    const m = this.m;
    const create = m._rac_telemetry_manager_create;
    const setCallback = m._rac_telemetry_manager_set_http_callback;
    const setSink = m._rac_events_set_telemetry_sink;
    if (!create || !setCallback || !setSink) return false;

    const deviceIdPtr = this.allocCString(this.opts.deviceId);
    const platformPtr = this.allocCString(this.opts.platform);
    const versionPtr = this.allocCString(this.opts.version);
    try {
      this.managerPtr_ = create(this.opts.environment, deviceIdPtr, platformPtr, versionPtr);
    } finally {
      m._free(deviceIdPtr);
      m._free(platformPtr);
      m._free(versionPtr);
    }
    if (this.managerPtr_ === 0) {
      logger.warning('rac_telemetry_manager_create returned null');
      return false;
    }

    if (typeof m._rac_telemetry_manager_set_device_info === 'function') {
      const modelPtr = this.allocCString(this.opts.deviceModel);
      const osPtr = this.allocCString(this.opts.osVersion);
      try {
        m._rac_telemetry_manager_set_device_info(this.managerPtr_, modelPtr, osPtr);
      } finally {
        m._free(modelPtr);
        m._free(osPtr);
      }
    }

    // rac_telemetry_http_callback_t:
    //   void (*)(void* user_data, const char* endpoint, const char* json_body,
    //            size_t json_length, rac_bool_t requires_auth)
    // Emscripten sig 'viiiii' (size_t is 32-bit in wasm32).
    this.callbackPtr = m.addFunction(
      ((userData: number, endpointPtr: number, jsonPtr: number, jsonLen: number, requiresAuth: number) => {
        void userData;
        this.deliver(endpointPtr, jsonPtr, jsonLen, requiresAuth);
      }) as (...a: never[]) => unknown,
      'viiiii',
    );

    setCallback(this.managerPtr_, this.callbackPtr, 0);
    setSink(this.managerPtr_);

    logger.info('telemetry manager wired (HTTP callback + event sink)');
    return true;
  }

  /**
   * Deliver one telemetry batch. Fire-and-forget async `fetch` — the C callback
   * returns void and does not wait. Reads the endpoint/body out of the WASM heap
   * before the async boundary (the C strings are only valid during this call).
   */
  private deliver(endpointPtr: number, jsonPtr: number, jsonLen: number, requiresAuth: number): void {
    if (endpointPtr === 0 || jsonPtr === 0) return;
    const endpoint = this.m.UTF8ToString(endpointPtr);
    const body = jsonLen > 0 ? this.m.UTF8ToString(jsonPtr, jsonLen) : this.m.UTF8ToString(jsonPtr);

    const base = this.opts.baseUrl.replace(/\/+$/, '');
    const url = base + endpoint;

    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.opts.apiKey) headers['apikey'] = this.opts.apiKey;
    if (this.opts.platform) headers['X-Platform'] = this.opts.platform;
    if (requiresAuth === RAC_TRUE) {
      const token = this.accessToken();
      if (token) headers['Authorization'] = `Bearer ${token}`;
    }

    void fetch(url, { method: 'POST', headers, body })
      .then((res) => {
        if (res.ok) logger.info(`telemetry POST ${endpoint} -> HTTP ${res.status}`);
        else logger.warning(`telemetry POST ${endpoint} -> HTTP ${res.status}`);
      })
      .catch((err) => {
        logger.warning(`telemetry POST ${endpoint} failed: ${err instanceof Error ? err.message : String(err)}`);
      });
  }

  private accessToken(): string | null {
    const get = this.m._rac_auth_get_access_token;
    if (typeof get !== 'function') return null;
    const ptr = get();
    return ptr ? this.m.UTF8ToString(ptr) : null;
  }

  private allocCString(str: string): number {
    const len = this.m.lengthBytesUTF8(str) + 1;
    const ptr = this.m._malloc(len);
    this.m.stringToUTF8(str, ptr, len);
    return ptr;
  }
}
