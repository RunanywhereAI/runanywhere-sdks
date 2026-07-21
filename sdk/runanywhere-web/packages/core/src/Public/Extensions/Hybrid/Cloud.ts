/**
 * Cloud.ts
 *
 * Generic cloud-STT backend registration + credential/model registry for the
 * Web SDK. Mirrors Swift's `Cloud.swift` and Kotlin's `BACKEND.CLOUD`.
 *
 * `Cloud.register({ id, provider, model, apiKey })` records a cloud-STT
 * model under an app-chosen id; the hybrid router refers to it by id from the
 * ONLINE side (`onlineCloud(id)`). The concrete HTTP provider (Sarvam first)
 * is data carried in the entry — there is no provider-specific TS type; it is
 * forwarded to the unified "cloud" engine via `config_json["provider"]`.
 *
 * `Cloud.registerBackend()` folds the cloud engine plugin into the
 * WASM module's plugin registry by calling `rac_backend_cloud_register`
 * (the mirror of ONNX.register() / LlamaCPP.register()). The Web build exports
 * this from hybrid-capable targets. The call remains tolerated-when-absent so
 * a host with an older or capability-incomplete artifact still boots (a later
 * transcribe surfaces a clear backendNotAvailable instead).
 *
 * HTTP under WASM: the cloud engine does its HTTP through the commons
 * `rac_http_client`, which on Emscripten routes through the registered
 * emscripten_fetch transport (rac_http_client_emscripten.cpp). So cloud STT
 * works in the browser without bespoke JavaScript HTTP orchestration: the WASM
 * router calls cloud → rac_http_client → the native Web transport.
 */

import { SDKLogger } from '../../../Foundation/SDKLogger.js';
import { RAC_OK, RAC_ERROR_MODULE_ALREADY_REGISTERED } from '../../../Foundation/RACErrors.js';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../../runtime/EmscriptenModule.js';
import type { HybridWasmModule } from './HybridWasmModule.js';
import { DEFAULT_CLOUD_PROVIDER } from './HybridTypes.js';
import { CloudSttBackendConfig } from '@runanywhere/proto-ts/hybrid_router';
import {
  registerCloudSttProvider,
  unregisterCloudSttProvider,
} from './CloudSttProvider.js';

const logger = new SDKLogger('Cloud');

/** A registered cloud-STT model entry: the app-chosen registry `id` plus the
 * generated `CloudSttBackendConfig` (provider/model/apiKey/languageCode/baseUrl/
 * timeoutMs). The backend config carries exactly the fields the cloud engine
 * reads out of `config_json`, so it is reused directly instead of re-declaring
 * those fields here. Mirrors Swift's `Cloud.ModelEntry` / Kotlin's
 * `CloudModelEntry`. */
export interface CloudModelEntry {
  /** App-chosen registry id (becomes the online HybridModel id). */
  id: string;
  /** The cloud backend registration config handed to the cloud engine. */
  backend: CloudSttBackendConfig;
}

/** Options accepted by `Cloud.register` / the `cloud({...})` config helper. */
export interface CloudSTTConfig {
  /** App-chosen registry id (becomes the online HybridModel id). */
  id: string;
  /** Provider model id (e.g. "saaras:v2.5" for Sarvam). */
  model: string;
  /** Provider API subscription key. */
  apiKey: string;
  /** Concrete cloud provider; defaults to "sarvam". */
  provider?: string;
  /** Optional BCP-47 language hint ("en-IN"…). */
  languageCode?: string;
  /** Optional endpoint override. */
  baseURL?: string;
  /** Optional request timeout (ms). */
  timeoutMs?: number;
}

const registry = new Map<string, CloudModelEntry>();
let backendRegistered = false;

/**
 * Build a cloud-STT registry entry from a generic provider config. The
 * `cloud({ provider, apiKey, model })` ergonomic shape — provider as DATA, not
 * a distinct backend. Does NOT register it; pair with `Cloud.register`.
 */
export function cloud(config: CloudSTTConfig): CloudModelEntry {
  if (!config.id) throw new Error('Cloud cloud(): id must be non-empty');
  if (!config.model) throw new Error('Cloud cloud(): model must be non-empty');
  if (!config.apiKey) throw new Error('Cloud cloud(): apiKey must be non-empty');
  const provider = config.provider ?? DEFAULT_CLOUD_PROVIDER;
  if (!provider) throw new Error('Cloud cloud(): provider must be non-empty');
  return {
    id: config.id,
    backend: CloudSttBackendConfig.fromPartial({
      provider,
      model: config.model,
      apiKey: config.apiKey,
      languageCode: config.languageCode ?? '',
      baseUrl: config.baseURL ?? '',
      timeoutMs: config.timeoutMs ?? 0,
    }),
  };
}

export const Cloud = {
  /** Default cloud STT provider when a caller omits one. */
  defaultProvider: DEFAULT_CLOUD_PROVIDER,

  /** cloud engine module version (binding side) — Swift parity: Cloud.swift:36. */
  version: '2.0.0',

  /**
   * Register the cloud backend plugin with the WASM module's registry.
   * Idempotent; safe to call multiple times. Returns true when the engine is
   * routable (registered now or already), false when the WASM build does not
   * export `rac_backend_cloud_register` (the engine is absent from that
   * artifact).
   *
   * The cloud plugin serves RAC_PRIMITIVE_TRANSCRIBE; once registered the
   * hybrid router can route the ONLINE side via engine hint "cloud".
   */
  registerBackend(): boolean {
    if (backendRegistered) return true;
    // Prefer the STT-capable module (cloud engine lives alongside sherpa STT);
    // fall back to commons for the rare core-only host.
    const module = (getModuleForCapability('stt') ??
      getModuleForCapability('commons')) as HybridWasmModule | null;
    const registerFn = module?._rac_backend_cloud_register;
    if (typeof registerFn !== 'function') {
      logger.warning(
        'WASM module does not export _rac_backend_cloud_register; the ' +
          'cloud engine is not linked into this build. Cloud STT routing ' +
          'will be unavailable. Rebuild a hybrid-capable Web WASM artifact.',
      );
      return false;
    }
    const rc = registerFn();
    if (rc !== RAC_OK && rc !== RAC_ERROR_MODULE_ALREADY_REGISTERED) {
      logger.error(`rac_backend_cloud_register failed: rc=${rc}`);
      return false;
    }
    backendRegistered = true;
    logger.info(
      `cloud backend registered (cloud STT, default provider ${DEFAULT_CLOUD_PROVIDER})`,
    );
    return true;
  },

  /**
   * Unregister the cloud backend from the WASM module's plugin registry.
   * Swift parity: `Cloud.unregister()` (Cloud.swift:84-94). No-op when the
   * backend was never registered or the export is absent.
   */
  unregister(): void {
    if (!backendRegistered) return;
    backendRegistered = false;
    const module = (getModuleForCapability('stt') ??
      getModuleForCapability('commons')) as HybridWasmModule | null;
    const unregisterFn = module?._rac_backend_cloud_unregister;
    if (typeof unregisterFn !== 'function') return;
    unregisterFn();
    logger.info('cloud backend unregistered');
  },

  /** Register a cloud-STT model under `id` so the router can refer to it by id
   * from `onlineCloud(id)`. Accepts either a `CloudSTTConfig` or a pre-built
   * `CloudModelEntry` from `cloud(...)`. */
  register(config: CloudSTTConfig | CloudModelEntry): void {
    // A pre-built CloudModelEntry already carries the typed `backend` config;
    // a CloudSTTConfig is the ergonomic input shape that `cloud(...)` validates.
    const entry: CloudModelEntry =
      'backend' in config ? config : cloud(config);
    registry.set(entry.id, entry);
    // Best-effort: ensure the engine plugin is registered at the same point
    // the app records credentials (symmetric to Kotlin's ensurePluginRegistered).
    this.registerBackend();
  },

  /** Look up a previously registered model by id. */
  lookup(id: string): CloudModelEntry | undefined {
    return registry.get(id);
  },

  /** True iff a model is registered under `id`. */
  isRegistered(id: string): boolean {
    return registry.has(id);
  },

  /** Remove a model registration. Returns true if one was removed. */
  unregisterModel(id: string): boolean {
    return registry.delete(id);
  },

  /**
   * Register (or replace) a developer-defined cloud STT provider handler
   * under `name`. The handler performs the whole request host-side; tie a
   * model to it with `Cloud.register({ provider: name, ... })`. Mirrors
   * Swift `Cloud.registerProvider(_:_:)` (CloudSttProvider.swift:145).
   */
  registerProvider: registerCloudSttProvider,

  /**
   * Remove a developer-defined provider previously registered via
   * `registerProvider`. Idempotent for unknown names. Mirrors Swift
   * `Cloud.unregisterProvider(_:)` (CloudSttProvider.swift:209).
   */
  unregisterProvider: unregisterCloudSttProvider,

  /** Clear the in-memory credential/model registry. */
  clear(): void {
    registry.clear();
  },

  /**
   * Build the config JSON the routed "cloud" plugin's `create` expects
   * from a registered entry. Carries `provider` so the engine selects the
   * right HTTP backend. Throws when `id` is not registered.
   */
  configJSON(id: string): string {
    const entry = registry.get(id);
    if (!entry) {
      throw new Error(
        `Cloud model id '${id}' not registered. Call ` +
          `Cloud.register({ id, provider, model, apiKey }) at app startup.`,
      );
    }
    // The cloud engine parses snake_case keys out of config_json
    // (config_json["api_key"], ["language_code"], ["base_url"], ["timeout_ms"];
    // see engines/cloud/rac_stt_cloud.cpp). The generated CloudSttBackendConfig
    // .toJSON() emits camelCase, so the snake_case wire object is projected from
    // the typed proto message rather than hand-assembled from loose strings.
    // Sorted/conditional keys keep the JSON byte-stable across SDKs (matches
    // Swift's JSONSerialization .sortedKeys), which keeps cache keys / logs
    // aligned.
    const cfg = entry.backend;
    const json: Record<string, string | number> = {
      api_key: cfg.apiKey,
      model: cfg.model,
      provider: cfg.provider,
    };
    if (cfg.languageCode) json.language_code = cfg.languageCode;
    if (cfg.baseUrl) json.base_url = cfg.baseUrl;
    if (cfg.timeoutMs) json.timeout_ms = cfg.timeoutMs;
    return JSON.stringify(json);
  },
};

/** Internal: typed accessor used by the router to reach the cloud-aware module. */
export function cloudCapableModule(): EmscriptenRunanywhereModule | null {
  return getModuleForCapability('stt') ?? getModuleForCapability('commons');
}
