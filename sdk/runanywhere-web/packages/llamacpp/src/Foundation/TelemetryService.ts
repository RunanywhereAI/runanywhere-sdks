/**
 * TelemetryService.ts
 *
 * Web SDK bridge to the C++ telemetry manager (rac_telemetry_manager_*).
 * Mirrors the role of TelemetryBridge.cpp in React Native.
 *
 * Architecture:
 * - Creates rac_telemetry_manager_t via WASM
 * - Registers an HTTP callback that C++ calls when events need sending
 * - The HTTP callback uses HTTPService (browser fetch) to POST to the endpoint
 * - Calls rac_telemetry_manager_http_complete() with the result
 * - Also provides AnalyticsEventCallback for forwarding events from AnalyticsEventsBridge
 *
 * Device UUID:
 * - Persisted in localStorage under 'rac_device_id'
 * - Generated with crypto.randomUUID() on first run
 */

import { SDKLogger, SDKEnvironment, HTTPService } from '@runanywhere/web';
import type { DeviceInfoData } from '@runanywhere/web';
import type { LlamaCppModule } from './LlamaCppBridge';

const logger = new SDKLogger('TelemetryService');

const DEVICE_ID_KEY = 'rac_device_id';
const SDK_VERSION = '0.1.0-beta.8';

// C++ rac_environment_t values
const RAC_ENV_DEVELOPMENT = 0;
const RAC_ENV_STAGING      = 1;
const RAC_ENV_PRODUCTION   = 2;

/**
 * Columns in the V2 `telemetry_events` Supabase table.
 * The C++ telemetry manager serializes modality-specific fields (e.g.
 * `speech_duration_ms`, `audio_duration_ms`, `word_count`) into the same
 * flat JSON payload. In production these go through the backend API which
 * splits them into child tables (`stt_telemetry`, `tts_telemetry`, etc.),
 * but in dev mode we POST directly to Supabase REST API — PostgREST
 * rejects any column not in the target table with HTTP 400.
 */
const TELEMETRY_V2_COLUMNS = new Set([
  'id', 'org_id', 'api_key_id', 'device_id', 'sdk_event_id',
  'event_type', 'modality', 'session_id', 'framework',
  'model_id', 'model_name', 'device', 'os_version', 'platform',
  'sdk_version', 'processing_time_ms', 'success',
  'error_message', 'error_code', 'event_timestamp', 'created_at',
  'received_at', 'migrated_from_v1', 'v1_source_id', 'synced_from_prod',
]);

// ---------------------------------------------------------------------------
// Device UUID helper
// ---------------------------------------------------------------------------

/**
 * Returns the persistent device UUID, creating one if it doesn't exist.
 * Uses localStorage for persistence across page loads.
 */
export function getOrCreateDeviceId(): string {
  try {
    const existing = localStorage.getItem(DEVICE_ID_KEY);
    if (existing) return existing;

    const id = crypto.randomUUID();
    localStorage.setItem(DEVICE_ID_KEY, id);
    return id;
  } catch {
    // Fallback when localStorage is unavailable (e.g., private browsing restrictions)
    return crypto.randomUUID();
  }
}

// ---------------------------------------------------------------------------
// TelemetryService
// ---------------------------------------------------------------------------

/**
 * Manages the lifecycle of the C++ telemetry manager and bridges HTTP calls
 * to browser fetch for telemetry event batching and delivery.
 */
export class TelemetryService {
  private static _instance: TelemetryService | null = null;

  static get shared(): TelemetryService {
    if (!TelemetryService._instance) {
      TelemetryService._instance = new TelemetryService();
    }
    return TelemetryService._instance;
  }

  private _module: LlamaCppModule | null = null;
  private _handle: number = 0;          // rac_telemetry_manager_t*
  private _httpCallbackPtr: number = 0;  // Emscripten function table ptr
  private _initialized = false;

  private constructor() {}

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /**
   * Initialize the telemetry manager.
   * Called from LlamaCppBridge._doLoad() after WASM is loaded.
   */
  async initialize(
    module: LlamaCppModule,
    environment: SDKEnvironment,
    deviceInfo: DeviceInfoData,
  ): Promise<void> {
    if (this._initialized) {
      logger.warning('TelemetryService already initialized');
      return;
    }

    if (typeof module._rac_telemetry_manager_create !== 'function') {
      logger.warning('rac_telemetry_manager_create not available — telemetry disabled');
      return;
    }

    this._module = module;

    // Map TypeScript SDKEnvironment to C++ rac_environment_t
    const racEnv = this.mapEnvironment(environment);

    const deviceId = getOrCreateDeviceId();

    // Alloc C strings
    const deviceIdPtr = this.allocString(deviceId);
    const platformPtr  = this.allocString('web');
    const versionPtr   = this.allocString(SDK_VERSION);

    this._handle = module._rac_telemetry_manager_create!(
      racEnv, deviceIdPtr, platformPtr, versionPtr,
    );

    this.freeAll([deviceIdPtr, platformPtr, versionPtr]);

    if (!this._handle) {
      logger.warning('rac_telemetry_manager_create returned null — telemetry disabled');
      this._module = null;
      return;
    }

    // Set device info
    if (typeof module._rac_telemetry_manager_set_device_info === 'function') {
      const modelPtr     = this.allocString(deviceInfo.model ?? 'Browser');
      const osVersionPtr = this.allocString(deviceInfo.osVersion ?? 'unknown');
      module._rac_telemetry_manager_set_device_info!(this._handle, modelPtr, osVersionPtr);
      this.freeAll([modelPtr, osVersionPtr]);
    }

    // Register HTTP callback
    this.registerHttpCallback(environment);

    // Configure HTTPService in dev mode using WASM dev config
    if (environment === SDKEnvironment.Development) {
      this.configureDevHTTP(module);
    }

    this._initialized = true;
    logger.info(`TelemetryService initialized (env=${environment}, device=${deviceId.substring(0, 8)}...)`);
  }

  /**
   * Callback for AnalyticsEventsBridge — forwards raw C++ event to telemetry manager.
   */
  trackAnalyticsEvent(eventType: number, dataPtr: number): void {
    if (!this._initialized || !this._module || !this._handle) return;

    try {
      if (typeof this._module._rac_telemetry_manager_track_analytics === 'function') {
        this._module._rac_telemetry_manager_track_analytics!(this._handle, eventType, dataPtr);
      }
    } catch {
      // Silent — telemetry must never crash the app
    }
  }

  /**
   * Flush all queued telemetry events immediately.
   */
  flush(): void {
    if (!this._initialized || !this._module || !this._handle) return;

    try {
      if (typeof this._module._rac_telemetry_manager_flush === 'function') {
        this._module._rac_telemetry_manager_flush!(this._handle);
      }
    } catch {
      // Silent — telemetry must never crash the app
    }
  }

  /**
   * Flush and tear down the telemetry manager.
   */
  shutdown(): void {
    if (!this._initialized) return;

    this.flush();

    try {
      if (this._module && this._handle) {
        if (typeof this._module._rac_telemetry_manager_set_http_callback === 'function') {
          this._module._rac_telemetry_manager_set_http_callback!(this._handle, 0, 0);
        }
        if (typeof this._module._rac_telemetry_manager_destroy === 'function') {
          this._module._rac_telemetry_manager_destroy!(this._handle);
        }
      }

      if (this._module && this._httpCallbackPtr !== 0) {
        if (typeof this._module.removeFunction === 'function') {
          this._module.removeFunction(this._httpCallbackPtr);
        }
      }
    } catch {
      // Silent — cleanup must not throw
    }

    this._handle = 0;
    this._httpCallbackPtr = 0;
    this._module = null;
    this._initialized = false;
    TelemetryService._instance = null;
    logger.debug('TelemetryService shut down');
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  /**
   * Registers the HTTP callback with the WASM telemetry manager.
   * C++ will call this when it wants to POST a telemetry batch.
   *
   * C signature: void(void* user_data, const char* endpoint, const char* json_body,
   *                   size_t json_length, rac_bool_t requires_auth)
   * Emscripten signature: 'viiiii'
   *
   * IMPORTANT: We call http_complete SYNCHRONOUSLY (before the async fetch) to
   * prevent C++ from re-flushing the same event while awaiting the HTTP response,
   * which caused duplicate POSTs. The actual fetch continues in the background.
   */
  private registerHttpCallback(environment: SDKEnvironment): void {
    const m = this._module!;
    if (typeof m._rac_telemetry_manager_set_http_callback !== 'function') return;

    this._httpCallbackPtr = m.addFunction(
      (_userData: number, endpointPtr: number, jsonBodyPtr: number, _jsonLength: number, _requiresAuth: number) => {
        const endpoint = m.UTF8ToString(endpointPtr);
        const jsonBody = m.UTF8ToString(jsonBodyPtr);

        // Tell C++ immediately that the request is being handled (prevents retry/re-flush)
        if (typeof m._rac_telemetry_manager_http_complete === 'function') {
          m._rac_telemetry_manager_http_complete!(this._handle, 1, 0, 0);
        }

        // Fire-and-forget async HTTP POST (actual delivery happens in background)
        this.performHttpPost(endpoint, jsonBody, environment).catch((err: unknown) => {
          logger.debug(`Telemetry POST failed: ${err instanceof Error ? err.message : String(err)}`);
        });
      },
      'viiiii',
    );

    m._rac_telemetry_manager_set_http_callback!(this._handle, this._httpCallbackPtr, 0);
    logger.debug('Telemetry HTTP callback registered');
  }

  /**
   * Perform the actual HTTP POST for a telemetry batch.
   * Returns the response JSON string on success.
   */
  private async performHttpPost(
    endpoint: string,
    jsonBody: string,
    environment: SDKEnvironment,
  ): Promise<string | null> {
    if (!HTTPService.shared.isConfigured) {
      logger.debug('HTTPService not configured — skipping telemetry POST');
      return null;
    }

    try {
      let body: unknown;
      try {
        body = JSON.parse(jsonBody);
      } catch {
        body = jsonBody;
      }

      // In dev mode we POST directly to Supabase REST API which rejects
      // columns that don't exist on the target table. The C++ telemetry
      // manager includes modality-specific metrics (e.g. speech_duration_ms,
      // audio_duration_ms) that belong in child tables in V2.  Strip them
      // so PostgREST accepts the payload.
      if (environment === SDKEnvironment.Development && endpoint.includes('telemetry_events')) {
        body = this.filterForDevTable(body);
      }

      const response = await HTTPService.shared.post<unknown, unknown>(endpoint, body);
      return typeof response === 'string' ? response : JSON.stringify(response);
    } catch (err) {
      logger.debug(`Telemetry POST failed (${environment}): ${err instanceof Error ? err.message : String(err)}`);
      return null;
    }
  }

  /**
   * Strip keys that don't exist in the V2 `telemetry_events` table.
   * Handles both array format (dev flat batch) and single-object format.
   */
  private filterForDevTable(body: unknown): unknown {
    if (Array.isArray(body)) {
      return body.map((item) => this.filterObject(item as Record<string, unknown>));
    }
    if (body !== null && typeof body === 'object') {
      return this.filterObject(body as Record<string, unknown>);
    }
    return body;
  }

  private filterObject(obj: Record<string, unknown>): Record<string, unknown> {
    const filtered: Record<string, unknown> = {};
    for (const key of Object.keys(obj)) {
      if (TELEMETRY_V2_COLUMNS.has(key)) {
        filtered[key] = obj[key];
      }
    }
    return filtered;
  }

  /**
   * If the WASM module has dev config compiled in, use it to configure HTTPService.
   */
  private configureDevHTTP(module: LlamaCppModule): void {
    if (typeof module._rac_wasm_dev_config_is_available !== 'function') return;
    if (!module._rac_wasm_dev_config_is_available!()) return;

    const urlPtr  = module._rac_wasm_dev_config_get_supabase_url?.() ?? 0;
    const keyPtr  = module._rac_wasm_dev_config_get_supabase_key?.() ?? 0;
    const url  = urlPtr  ? module.UTF8ToString(urlPtr)  : '';
    const key  = keyPtr  ? module.UTF8ToString(keyPtr)  : '';

    if (url && key) {
      HTTPService.shared.configureDev({ supabaseURL: url, supabaseKey: key });
      logger.info('HTTPService configured with WASM dev config (Supabase)');
    }
  }

  private mapEnvironment(env: SDKEnvironment): number {
    switch (env) {
      case SDKEnvironment.Development: return RAC_ENV_DEVELOPMENT;
      case SDKEnvironment.Staging:     return RAC_ENV_STAGING;
      case SDKEnvironment.Production:  return RAC_ENV_PRODUCTION;
      default:                          return RAC_ENV_PRODUCTION;
    }
  }

  private allocString(str: string): number {
    const m = this._module!;
    const len = m.lengthBytesUTF8(str) + 1;
    const ptr = m._malloc(len);
    m.stringToUTF8(str, ptr, len);
    return ptr;
  }

  private freeAll(ptrs: number[]): void {
    const m = this._module!;
    for (const ptr of ptrs) {
      if (ptr) m._free(ptr);
    }
  }
}
