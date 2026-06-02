/**
 * CloudSTT.ts
 *
 * Generic cloud-STT backend registration + credential/model registry for the
 * Web SDK. Mirrors Swift's `CloudSTT.swift` and Kotlin's `BACKEND.CLOUD`.
 *
 * `CloudSTT.register({ id, provider, model, apiKey })` records a cloud-STT
 * model under an app-chosen id; the hybrid router refers to it by id from the
 * ONLINE side (`onlineCloud(id)`). The concrete HTTP provider (Sarvam first)
 * is data carried in the entry — there is no provider-specific TS type; it is
 * forwarded to the unified "cloud" engine via `config_json["provider"]`.
 *
 * `CloudSTT.registerBackend()` folds the cloud engine plugin into the
 * WASM module's plugin registry by calling `rac_backend_cloud_register`
 * (the mirror of ONNX.register() / LlamaCPP.register()). On WASM the cloud
 * engine is its own static library that must be linked + exported — see
 * HybridWasmModule.ts BUILD DELTA. The call is tolerated-when-absent so a host
 * whose WASM lacks the engine still boots (a later transcribe surfaces a clear
 * backendNotAvailable instead).
 *
 * HTTP under WASM: the cloud engine does its HTTP through the commons
 * `rac_http_client`, which on Emscripten routes through the registered
 * transport — either the emscripten_fetch shim (rac_http_client_emscripten.cpp)
 * or the JS XHR/fetch transport (FetchHttpTransport.ts, installed via
 * rac_http_transport_register_from_js). So cloud STT works in the browser
 * WITHOUT bespoke JS fetch orchestration: the WASM router calls cloud →
 * rac_http_client → the already-wired Web transport. No extra plumbing needed.
 */

import { SDKLogger } from '../../../Foundation/SDKLogger';
import { RAC_OK, RAC_ERROR_MODULE_ALREADY_REGISTERED } from '../../../Foundation/RACErrors';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../../runtime/EmscriptenModule';
import type { HybridWasmModule } from './HybridWasmModule';
import { DEFAULT_CLOUD_PROVIDER } from './HybridTypes';

const logger = new SDKLogger('CloudSTT');

/** A registered cloud-STT model entry. Mirrors Swift's `CloudSTT.ModelEntry`
 * / Kotlin's `CloudModelEntry`. */
export interface CloudModelEntry {
  id: string;
  /** Concrete cloud STT provider ("sarvam" by default). */
  provider: string;
  /** Provider model id (e.g. "saaras:v2.5"). */
  model: string;
  /** Provider API subscription key. Sensitive; never logged. */
  apiKey: string;
  /** Optional BCP-47 hint; omitted ⇒ engine auto-detects. */
  languageCode?: string;
  /** Optional endpoint override. */
  baseURL?: string;
  /** Optional request timeout in milliseconds. */
  timeoutMs?: number;
}

/** Options accepted by `CloudSTT.register` / the `cloud({...})` config helper. */
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
 * a distinct backend. Does NOT register it; pair with `CloudSTT.register`.
 */
export function cloud(config: CloudSTTConfig): CloudModelEntry {
  if (!config.id) throw new Error('CloudSTT cloud(): id must be non-empty');
  if (!config.model) throw new Error('CloudSTT cloud(): model must be non-empty');
  if (!config.apiKey) throw new Error('CloudSTT cloud(): apiKey must be non-empty');
  const provider = config.provider ?? DEFAULT_CLOUD_PROVIDER;
  if (!provider) throw new Error('CloudSTT cloud(): provider must be non-empty');
  return {
    id: config.id,
    provider,
    model: config.model,
    apiKey: config.apiKey,
    languageCode: config.languageCode,
    baseURL: config.baseURL,
    timeoutMs: config.timeoutMs,
  };
}

export const CloudSTT = {
  /** Default cloud STT provider when a caller omits one. */
  defaultProvider: DEFAULT_CLOUD_PROVIDER,

  /**
   * Register the cloud backend plugin with the WASM module's registry.
   * Idempotent; safe to call multiple times. Returns true when the engine is
   * routable (registered now or already), false when the WASM build does not
   * export `rac_backend_cloud_register` (the engine isn't linked — see
   * HybridWasmModule.ts BUILD DELTA).
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
          'will be unavailable. See HybridWasmModule.ts BUILD DELTA (item C).',
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

  /** Register a cloud-STT model under `id` so the router can refer to it by id
   * from `onlineCloud(id)`. Accepts either a `CloudSTTConfig` or a pre-built
   * `CloudModelEntry` from `cloud(...)`. */
  register(config: CloudSTTConfig | CloudModelEntry): void {
    const entry = 'provider' in config && typeof config.provider === 'string'
      ? cloud({
          id: config.id,
          model: config.model,
          apiKey: config.apiKey,
          provider: config.provider,
          languageCode: config.languageCode,
          baseURL: 'baseURL' in config ? config.baseURL : undefined,
          timeoutMs: config.timeoutMs,
        })
      : cloud(config as CloudSTTConfig);
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
        `CloudSTT model id '${id}' not registered. Call ` +
          `CloudSTT.register({ id, provider, model, apiKey }) at app startup.`,
      );
    }
    // Sorted keys so the JSON is byte-stable across SDKs (matches Swift's
    // JSONSerialization .sortedKeys), which keeps cache keys / logs aligned.
    const json: Record<string, string | number> = {
      api_key: entry.apiKey,
      model: entry.model,
      provider: entry.provider,
    };
    if (entry.languageCode) json.language_code = entry.languageCode;
    if (entry.baseURL) json.base_url = entry.baseURL;
    if (entry.timeoutMs !== undefined) json.timeout_ms = entry.timeoutMs;
    return JSON.stringify(json);
  },
};

/** Internal: typed accessor used by the router to reach the cloud-aware module. */
export function cloudCapableModule(): EmscriptenRunanywhereModule | null {
  return getModuleForCapability('stt') ?? getModuleForCapability('commons');
}
