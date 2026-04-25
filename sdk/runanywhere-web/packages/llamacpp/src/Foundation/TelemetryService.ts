/**
 * TelemetryService.ts
 *
 * Web SDK bridge to the C++ telemetry manager (rac_telemetry_manager_*).
 * Mirrors the role of TelemetryBridge.cpp in React Native.
 *
 * Architecture:
 * - Creates rac_telemetry_manager_t via WASM
 * - Registers an HTTP callback that C++ calls when events need sending
 * - The HTTP callback POSTs the telemetry batch through HTTPAdapter
 * - Calls rac_telemetry_manager_http_complete() with the result
 * - Also provides AnalyticsEventCallback for forwarding events from AnalyticsEventsBridge
 *
 * Device UUID:
 * - Persisted in localStorage under 'rac_device_id'
 * - Generated with crypto.randomUUID() on first run
 */

import { SDKLogger, SDKEnvironment, HTTPAdapter } from '@runanywhere/web';
import type { DeviceInfoData, HTTPHeader } from '@runanywhere/web';
import type { LlamaCppModule } from './LlamaCppBridge';

const logger = new SDKLogger('TelemetryService');

const DEVICE_ID_KEY = 'rac_device_id';
const SDK_VERSION = '0.1.0-beta.8';
const SDK_CLIENT = 'RunAnywhereSDK';
const SDK_PLATFORM = 'web';

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
 * to HTTPAdapter for telemetry event batching and delivery.
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
  private _handle: number = 0;           // rac_telemetry_manager_t*
  private _httpCallbackPtr: number = 0;  // Emscripten function table ptr
  private _initialized = false;
  private _initPromise: Promise<void> | null = null;  // guards concurrent initialize() calls

  // Dev-mode HTTP config (Supabase). Populated from WASM-compiled credentials
  // in `configureDevHTTP()` — kept local to the service since telemetry is
  // the only HTTP path in the current web SDK.
  private _supabaseURL: string = '';
  private _supabaseKey: string = '';

  private constructor() {}

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /**
   * Initialize the telemetry manager.
   * Called from LlamaCppBridge._doLoad() after WASM is loaded.
   *
   * Concurrent calls are safe: a second caller awaits the in-flight promise
   * rather than starting a duplicate initialization, preventing duplicate
   * WASM handles and leaked function-table entries.
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
    // If initialization is already in flight, wait for it rather than
    // starting a second one — mirrors the LlamaCppBridge.ensureLoaded() pattern.
    if (this._initPromise) {
      await this._initPromise;
      return;
    }
    this._initPromise = this._doInitialize(module, environment, deviceInfo);
    try {
      await this._initPromise;
    } finally {
      this._initPromise = null;
    }
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
    this._supabaseURL = '';
    this._supabaseKey = '';
    TelemetryService._instance = null;
    logger.debug('TelemetryService shut down');
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  /**
   * Core initialization logic — only called once, guarded by initialize().
   */
  private async _doInitialize(
    module: LlamaCppModule,
    environment: SDKEnvironment,
    deviceInfo: DeviceInfoData,
  ): Promise<void> {
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

    // Configure dev HTTP credentials before registering the callback so the
    // first flush can succeed. Prod path currently has no HTTP transport wired
    // up — telemetry batches are simply dropped there.
    if (environment === SDKEnvironment.Development) {
      this.configureDevHTTP(module);
    }

    // Register HTTP callback
    this.registerHttpCallback(environment);

    this._initialized = true;
    logger.info(`TelemetryService initialized (env=${environment}, device=${deviceId.substring(0, 8)}...)`);
  }

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
   * Returns the response body (as text) on success, or null on failure / when
   * HTTP transport is not configured (e.g. prod mode without credentials).
   *
   * Only the dev/Supabase path is wired up here — prod telemetry currently
   * flows through the C++ manager but has no JS-side HTTP transport.
   */
  private async performHttpPost(
    endpoint: string,
    jsonBody: string,
    environment: SDKEnvironment,
  ): Promise<string | null> {
    if (!this.isHttpConfigured) {
      logger.debug('Telemetry HTTP not configured — skipping POST');
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
      // audio_duration_ms) that belong in child tables in V2. Strip them
      // so PostgREST accepts the payload.
      if (environment === SDKEnvironment.Development && endpoint.includes('telemetry_events')) {
        body = this.filterForDevTable(body);
      }

      const url = this.buildURL(endpoint);
      const response = await this.postTelemetry(url, endpoint, JSON.stringify(body));

      // Device registration is idempotent — a 409 means we're already
      // registered and is not an error.
      if (response.status < 200 || response.status >= 300) {
        if (response.status === 409 && this.isDeviceRegistrationPath(endpoint)) {
          return '';
        }
        logger.debug(`Telemetry POST HTTP ${response.status}: ${endpoint}`);
        return null;
      }

      return response.body ? new TextDecoder().decode(response.body) : '';
    } catch (err) {
      logger.debug(`Telemetry POST failed (${environment}): ${err instanceof Error ? err.message : String(err)}`);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // HTTP transport (inlined from the former `HTTPService`)
  // ---------------------------------------------------------------------------

  private get isHttpConfigured(): boolean {
    return !!this._supabaseURL && !!this._supabaseKey;
  }

  private buildURL(path: string): string {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    const base = this._supabaseURL.replace(/\/$/, '');
    const endpoint = path.startsWith('/') ? path : `/${path}`;
    // Device registration is idempotent in Supabase via on_conflict=device_id.
    if (this.isDeviceRegistrationPath(endpoint)) {
      const sep = endpoint.includes('?') ? '&' : '?';
      return `${base}${endpoint}${sep}on_conflict=device_id`;
    }
    return `${base}${endpoint}`;
  }

  private async postTelemetry(url: string, endpoint: string, jsonBody: string): Promise<{ status: number; body: Uint8Array | null }> {
    const http = HTTPAdapter.tryDefault()
      ?? new HTTPAdapter(this._module! as unknown as Parameters<typeof HTTPAdapter.setDefaultModule>[0]);

    return http.request({
      method: 'POST',
      url,
      headers: this.buildHeaders(endpoint),
      body: new TextEncoder().encode(jsonBody),
      followRedirects: true,
    });
  }

  private buildHeaders(path: string): HTTPHeader[] {
    return [
      { name: 'Content-Type', value: 'application/json' },
      { name: 'Accept', value: 'application/json' },
      { name: 'X-SDK-Client', value: SDK_CLIENT },
      { name: 'X-SDK-Version', value: SDK_VERSION },
      { name: 'X-Platform', value: SDK_PLATFORM },
      { name: 'apikey', value: this._supabaseKey },
      { name: 'Authorization', value: `Bearer ${this._supabaseKey}` },
      {
        name: 'Prefer',
        value: this.isDeviceRegistrationPath(path)
          ? 'resolution=merge-duplicates'
          : 'return=representation',
      },
    ];
  }

  private isDeviceRegistrationPath(path: string): boolean {
    return path.includes('sdk_devices')
      || path.includes('devices/register')
      || path.includes('rest/v1/sdk_devices');
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
   * Pull Supabase credentials compiled into the WASM dev config, if available.
   */
  private configureDevHTTP(module: LlamaCppModule): void {
    if (typeof module._rac_wasm_dev_config_is_available !== 'function') return;
    if (!module._rac_wasm_dev_config_is_available!()) return;

    const urlPtr  = module._rac_wasm_dev_config_get_supabase_url?.() ?? 0;
    const keyPtr  = module._rac_wasm_dev_config_get_supabase_key?.() ?? 0;
    const url  = urlPtr  ? module.UTF8ToString(urlPtr)  : '';
    const key  = keyPtr  ? module.UTF8ToString(keyPtr)  : '';

    if (url && key) {
      this._supabaseURL = url;
      this._supabaseKey = key;
      logger.info('Telemetry HTTP configured with WASM dev config (Supabase)');
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
