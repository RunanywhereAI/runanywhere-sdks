/**
 * TelemetryBridge.ts (Web / WASM)
 *
 * Wires the C++ commons telemetry manager into an Emscripten WASM module so SDK
 * telemetry events actually reach the backend. This is the Web port of the
 * per-platform telemetry bridges every other SDK already ships:
 *   - iOS:     CppBridge+Telemetry.swift  (source of truth)
 *   - Kotlin:  CppBridgeTelemetry.kt
 *   - RN:      TelemetryBridge.cpp
 *   - Flutter: dart_bridge_telemetry.dart
 *
 * Commons owns ALL telemetry logic (queue, batch, group-by-modality, JSON,
 * endpoint selection: `/api/v2/sdk/telemetry/{modality}`). The SDK only has to:
 *   1. create a telemetry manager,
 *   2. give it device info,
 *   3. register an HTTP callback that POSTs the commons-built JSON, and
 *   4. attach the manager as the event router's telemetry sink.
 * The router (`rac::events::route`) then feeds every TELEMETRY-bit event into
 * the manager via `rac_telemetry_manager_track_proto` — there is no per-event
 * JS translation.
 *
 * Web specifics
 * -------------
 * Unlike the single-commons native SDKs, the Web SDK loads THREE independent
 * WASM modules (core racommons + llamacpp + onnx-sherpa), each with its own
 * commons instance, event router, and telemetry sink. Telemetry is therefore
 * wired PER MODULE (from `completeNativePhase1ForModule`), so each module's own
 * events (core: system/model/download; llamacpp: LLM/VLM; onnx: STT/TTS/VAD)
 * are captured by a sink living in that same module.
 *
 * HTTP / auth
 * -----------
 * The telemetry manager invokes its HTTP callback synchronously when it flushes;
 * the callback reads the endpoint + JSON out of the WASM heap (commons frees
 * them immediately after the call returns) and then fires a fire-and-forget
 * POST. `rac_telemetry_manager_http_complete` is intentionally NOT called back —
 * it is a no-op in commons and Swift skips it too.
 *   - Development: no JWT required (`rac_env_requires_auth(DEVELOPMENT) == false`),
 *     so the request goes to the compiled-in dev endpoint
 *     (`rac_wasm_dev_config_get_supabase_*`) with the dev key — mirroring the RN
 *     dev branch (InitBridge.cpp).
 *   - Staging/Production: the V2 endpoints require the JWT from the apiKey->JWT
 *     exchange (the raw apiKey is rejected by the backend). The callback reads
 *     the access token from the authenticated `'commons'` module via
 *     `rac_auth_get_access_token` and POSTs `baseUrl + endpoint` with an
 *     `Authorization: Bearer` header. That export must be present in the WASM
 *     build (it is listed in wasm/CMakeLists.txt — requires a WASM rebuild); on
 *     an older artifact lacking it the POST is skipped (logged). NOTE: only the
 *     core 'commons' module authenticates, so backend modules (llamacpp/onnx)
 *     defer their flush in prod until per-module auth propagation lands — until
 *     then LLM/STT/TTS telemetry flows in development mode.
 */

import { SDKLogger } from '../Foundation/SDKLogger';
import {
  getAllRegisteredModules,
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../runtime/EmscriptenModule';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

const logger = new SDKLogger('TelemetryBridge');

// rac_environment_t (rac_environment.h) — kept in sync with the C enum.
const RAC_ENV_DEVELOPMENT = 0;
const RAC_ENV_STAGING = 1;
const RAC_ENV_PRODUCTION = 2;

/**
 * Telemetry + dev-config exports consumed by this bridge. All optional: an
 * older WASM artifact without them degrades gracefully (a warning, no throw),
 * matching FetchHttpTransport / CloudSttProvider.
 */
interface TelemetryModule extends EmscriptenRunanywhereModule {
  _rac_telemetry_manager_create?(
    env: number,
    deviceIdPtr: number,
    platformPtr: number,
    sdkVersionPtr: number,
  ): number;
  _rac_telemetry_manager_set_device_info?(
    manager: number,
    deviceModelPtr: number,
    osVersionPtr: number,
  ): void;
  _rac_telemetry_manager_set_http_callback?(
    manager: number,
    callbackPtr: number,
    userData: number,
  ): void;
  _rac_telemetry_manager_flush?(manager: number): number;
  _rac_telemetry_manager_destroy?(manager: number): void;
  _rac_events_set_telemetry_sink?(manager: number): void;

  // Access token (JWT) accessor for the staging/prod Authorization header.
  _rac_auth_get_access_token?(): number;
  // Session accessors + setter used to replay the core module's auth session
  // into backend modules so their commons authenticates and telemetry flushes.
  _rac_auth_is_authenticated?(): number;
  _rac_auth_get_refresh_token?(): number;
  _rac_auth_get_token_expires_at?(): number | bigint;
  _rac_auth_handle_authenticate_response?(jsonPtr: number): number;

  // Dev-mode endpoint config (EMSCRIPTEN_KEEPALIVE wrappers in wasm_exports.cpp).
  _rac_wasm_dev_config_is_available?(): number;
  _rac_wasm_dev_config_get_supabase_url?(): number;
  _rac_wasm_dev_config_get_supabase_key?(): number;
}

export interface TelemetryInstallParams {
  /** SDK environment — selects dev vs staging/prod HTTP behavior + JSON shape. */
  environment: SDKEnvironment;
  /** Backend base URL (init option) — POST target for staging/prod telemetry. */
  baseUrl: string;
  /** Persistent device UUID (same value passed to native Phase 1). */
  deviceId: string;
  /** Device model string for telemetry attribution (Web: "Browser"). */
  deviceModel: string;
  /** OS string for telemetry attribution (Web: derived from userAgent). */
  osVersion: string;
  /** SDK version string. */
  sdkVersion: string;
}

interface InstalledTelemetry {
  manager: number;
  callbackPtr: number;
}

/** One telemetry manager + callback per WASM module. */
const installed = new WeakMap<EmscriptenRunanywhereModule, InstalledTelemetry>();

/**
 * Cached development endpoint config. The compiled-in dev config is identical
 * across all three artifacts, so it is resolved once (from whichever module
 * exports the KEEPALIVE getters — the core 'commons' module always does) and
 * reused by every module's callback, including backend modules whose own build
 * may not export the dev-config wrappers.
 */
let devEndpoint: { baseUrl: string; key: string } | null = null;

function allocCString(module: EmscriptenRunanywhereModule, value: string): number {
  const size = module.lengthBytesUTF8(value) + 1;
  const ptr = module._malloc(size);
  module.stringToUTF8(value, ptr, size);
  return ptr;
}

function toRacEnvironment(env: SDKEnvironment): number {
  switch (env) {
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return RAC_ENV_PRODUCTION;
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return RAC_ENV_STAGING;
    default:
      // UNSPECIFIED / DEVELOPMENT both map to the no-auth dev path.
      return RAC_ENV_DEVELOPMENT;
  }
}

function joinUrl(baseUrl: string, path: string): string {
  const base = baseUrl.replace(/\/+$/, '');
  const suffix = path.startsWith('/') ? path : `/${path}`;
  return base + suffix;
}

/** Resolve (and cache) the dev endpoint config from the 'commons' module. */
function resolveDevEndpoint(): { baseUrl: string; key: string } | null {
  if (devEndpoint) return devEndpoint;
  const commons = getModuleForCapability('commons') as TelemetryModule | null;
  if (
    !commons ||
    typeof commons._rac_wasm_dev_config_is_available !== 'function' ||
    typeof commons._rac_wasm_dev_config_get_supabase_url !== 'function' ||
    typeof commons._rac_wasm_dev_config_get_supabase_key !== 'function'
  ) {
    return null;
  }
  if (commons._rac_wasm_dev_config_is_available() === 0) return null;
  const urlPtr = commons._rac_wasm_dev_config_get_supabase_url();
  const keyPtr = commons._rac_wasm_dev_config_get_supabase_key();
  const baseUrl = urlPtr ? commons.UTF8ToString(urlPtr) : '';
  const key = keyPtr ? commons.UTF8ToString(keyPtr) : '';
  if (!baseUrl || !key) return null;
  devEndpoint = { baseUrl, key };
  return devEndpoint;
}

/** Fire-and-forget development telemetry POST (mirrors RN InitBridge headers). */
function postDevTelemetry(endpoint: string, json: string): void {
  const cfg = resolveDevEndpoint();
  if (!cfg) {
    logger.debug(`Skipping telemetry POST ${endpoint}: no usable dev config`);
    return;
  }
  const url = joinUrl(cfg.baseUrl, endpoint);
  void fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: cfg.key,
      Authorization: `Bearer ${cfg.key}`,
    },
    body: json,
  })
    .then((res) => {
      logger.debug(`Telemetry POST ${endpoint} -> ${res.status}`);
    })
    .catch((err) => {
      logger.debug(
        `Telemetry POST ${endpoint} error: ${err instanceof Error ? err.message : String(err)}`,
      );
    });
}

/**
 * Fire-and-forget staging/production telemetry POST. Resolves the JWT from the
 * authenticated `'commons'` module (`rac_auth_get_access_token`) and attaches
 * it as a Bearer header. The raw apiKey is never sent — the backend rejects it.
 */
function postProdTelemetry(endpoint: string, json: string, baseUrl: string): void {
  if (!baseUrl) {
    logger.debug(`Skipping telemetry POST ${endpoint}: no base URL configured`);
    return;
  }
  const commons = getModuleForCapability('commons') as TelemetryModule | null;
  if (!commons || typeof commons._rac_auth_get_access_token !== 'function') {
    logger.debug(
      `Skipping telemetry POST ${endpoint}: rac_auth_get_access_token unavailable (rebuild WASM)`,
    );
    return;
  }
  const tokenPtr = commons._rac_auth_get_access_token();
  const token = tokenPtr ? commons.UTF8ToString(tokenPtr) : '';
  if (!token) {
    logger.debug(`Skipping telemetry POST ${endpoint}: not authenticated yet`);
    return;
  }
  const url = joinUrl(baseUrl, endpoint);
  void fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: json,
  })
    .then((res) => {
      logger.debug(`Telemetry POST ${endpoint} -> ${res.status}`);
    })
    .catch((err) => {
      logger.debug(
        `Telemetry POST ${endpoint} error: ${err instanceof Error ? err.message : String(err)}`,
      );
    });
}

/**
 * Replay the core module's auth session into a backend WASM module.
 *
 * Web loads three independent commons instances; only the core 'commons' module
 * runs the apiKey->JWT exchange (Phase 2). The backend modules (llamacpp/onnx)
 * stay unauthenticated, so in staging/prod their telemetry flush defers on the
 * `rac_auth_is_authenticated()` gate in `rac_telemetry_manager_flush` —
 * LLM/VLM/STT/TTS/VAD telemetry never sends. This copies the core's access +
 * refresh token and expiry into `target` via `rac_auth_handle_authenticate_response`,
 * which both marks the target authenticated AND drains the telemetry it deferred
 * while waiting. Idempotent + best-effort: a no-op if the target is already
 * authenticated, is the core module itself, or the exports are absent (older
 * WASM). The raw apiKey is never used — only the real JWT.
 */
function syncCoreAuthToModule(target: EmscriptenRunanywhereModule): void {
  const t = target as TelemetryModule;
  if (typeof t._rac_auth_handle_authenticate_response !== 'function') return;
  // Already authenticated (or core re-applying its own session) — skip so we
  // don't re-publish auth events / re-flush on every call.
  if (typeof t._rac_auth_is_authenticated === 'function' && t._rac_auth_is_authenticated() !== 0) {
    return;
  }

  const core = getModuleForCapability('commons') as TelemetryModule | null;
  if (!core || core === target) return;
  if (typeof core._rac_auth_is_authenticated !== 'function' || core._rac_auth_is_authenticated() === 0) {
    return;
  }
  if (typeof core._rac_auth_get_access_token !== 'function') return;

  const tokenPtr = core._rac_auth_get_access_token();
  const token = tokenPtr ? core.UTF8ToString(tokenPtr) : '';
  if (!token) return;

  const refreshPtr =
    typeof core._rac_auth_get_refresh_token === 'function' ? core._rac_auth_get_refresh_token() : 0;
  const refresh = refreshPtr ? core.UTF8ToString(refreshPtr) : '';
  const expiresAt =
    typeof core._rac_auth_get_token_expires_at === 'function'
      ? Number(core._rac_auth_get_token_expires_at())
      : 0;
  const nowSec = Math.floor(Date.now() / 1000);
  const expiresIn = expiresAt > nowSec ? expiresAt - nowSec : 3600;

  // rac_auth_response_from_json (api_types.cpp) requires access_token +
  // refresh_token. Backend modules never refresh (their only HTTP is the
  // fire-and-forget telemetry POST), so when the core has no refresh token we
  // reuse the access token purely to satisfy the parser's non-null check.
  const json = JSON.stringify({
    access_token: token,
    refresh_token: refresh || token,
    expires_in: expiresIn,
  });
  const ptr = allocCString(target, json);
  try {
    t._rac_auth_handle_authenticate_response(ptr);
    logger.debug('Propagated core auth session into backend module; telemetry flush enabled');
  } finally {
    target._free(ptr);
  }
}

export const TelemetryBridge = {
  /**
   * Create + wire a telemetry manager for `module` (idempotent per module).
   * Mirrors the 4-step Phase-1 wiring shared by every other SDK:
   * create -> set_device_info -> set_http_callback -> set_telemetry_sink.
   */
  install(module: EmscriptenRunanywhereModule, params: TelemetryInstallParams): void {
    if (installed.has(module)) return;

    const m = module as TelemetryModule;
    if (
      typeof m._rac_telemetry_manager_create !== 'function' ||
      typeof m._rac_telemetry_manager_set_http_callback !== 'function' ||
      typeof m._rac_events_set_telemetry_sink !== 'function'
    ) {
      logger.warning(
        'WASM module missing telemetry exports (_rac_telemetry_manager_* / ' +
          '_rac_events_set_telemetry_sink); telemetry not wired for this module. ' +
          'Rebuild the artifact from wasm/CMakeLists.txt.',
      );
      return;
    }

    const racEnv = toRacEnvironment(params.environment);
    const baseUrl = params.baseUrl;

    // Create the manager (alloc transient C strings for the value args).
    const deviceIdPtr = allocCString(m, params.deviceId);
    const platformPtr = allocCString(m, 'web');
    const sdkVersionPtr = allocCString(m, params.sdkVersion);
    let manager = 0;
    try {
      manager = m._rac_telemetry_manager_create(racEnv, deviceIdPtr, platformPtr, sdkVersionPtr);
    } finally {
      m._free(deviceIdPtr);
      m._free(platformPtr);
      m._free(sdkVersionPtr);
    }
    if (!manager) {
      logger.warning('rac_telemetry_manager_create returned null; telemetry not wired');
      return;
    }

    if (typeof m._rac_telemetry_manager_set_device_info === 'function') {
      const modelPtr = allocCString(m, params.deviceModel);
      const osPtr = allocCString(m, params.osVersion);
      try {
        m._rac_telemetry_manager_set_device_info(manager, modelPtr, osPtr);
      } finally {
        m._free(modelPtr);
        m._free(osPtr);
      }
    }

    // C HTTP callback (`rac_telemetry_http_callback_t`):
    //   void (*)(void* user_data, const char* endpoint, const char* json_body,
    //            size_t json_length, rac_bool_t requires_auth)  => 'viiiii'.
    // Read the heap strings synchronously (commons frees them right after the
    // call returns), then dispatch a fire-and-forget POST.
    const callbackPtr = m.addFunction(
      (
        _userData: number,
        endpointPtr: number,
        jsonBodyPtr: number,
        jsonLength: number,
        _requiresAuth: number,
      ): void => {
        if (!endpointPtr || !jsonBodyPtr) return;
        const endpoint = m.UTF8ToString(endpointPtr);
        const json = m.UTF8ToString(jsonBodyPtr, jsonLength);
        if (racEnv === RAC_ENV_DEVELOPMENT) {
          postDevTelemetry(endpoint, json);
        } else {
          postProdTelemetry(endpoint, json, baseUrl);
        }
      },
      'viiiii',
    );

    m._rac_telemetry_manager_set_http_callback(manager, callbackPtr, 0);
    m._rac_events_set_telemetry_sink(manager);

    installed.set(module, { manager, callbackPtr });
    // If the core module has already authenticated (a backend that loads after
    // Phase 2), replay its session now so this module's telemetry can flush.
    syncCoreAuthToModule(module);
    logger.debug('Telemetry manager created and attached as event sink');
  },

  /**
   * Detach + destroy the telemetry manager for `module`. Mirrors
   * TelemetryBridge.cpp::shutdown — detach the sink first so the router stops
   * feeding a manager we are about to destroy, then flush and destroy. Each
   * module's sink is independent (its own commons), so clearing it here only
   * affects this module.
   */
  uninstall(module: EmscriptenRunanywhereModule): void {
    const state = installed.get(module);
    if (!state) return;
    installed.delete(module);

    const m = module as TelemetryModule;
    try {
      m._rac_events_set_telemetry_sink?.(0);
      m._rac_telemetry_manager_flush?.(state.manager);
      m._rac_telemetry_manager_destroy?.(state.manager);
    } catch (err) {
      logger.debug(
        `Telemetry teardown error: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
    try {
      m.removeFunction(state.callbackPtr);
    } catch {
      /* table entry already retired */
    }
  },

  /**
   * Replay the core auth session into every registered module. Call after
   * Phase-2 auth completes so backend modules (llamacpp/onnx), which never
   * authenticate themselves, can flush their deferred LLM/VLM/STT/TTS/VAD
   * telemetry in staging/production.
   */
  syncAuthToBackendModules(): void {
    for (const m of getAllRegisteredModules()) {
      syncCoreAuthToModule(m);
    }
  },
};
