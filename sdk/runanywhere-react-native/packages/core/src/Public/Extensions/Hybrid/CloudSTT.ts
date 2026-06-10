/**
 * CloudSTT.ts
 *
 * Generic cloud-STT backend registration + credential/model registry for the
 * hybrid router's online side.
 *
 * `CloudSTT.register()` folds the cloud engine plugin into the commons
 * plugin registry via the native `cloudRegister` bridge method
 * (`rac_backend_cloud_register`) — the exact mirror of `ONNX.register()` /
 * `LlamaCPP.register()`. Once registered, the unified "cloud" plugin serves
 * RAC_PRIMITIVE_TRANSCRIBE and is routable via the hybrid router's online side
 * (hint "cloud"). The concrete HTTP provider (Sarvam first) is selected per
 * model via the create config's `provider` field, not by a distinct plugin.
 *
 * The credential/model registry mirrors the Kotlin BACKEND.CLOUD table and the
 * Swift CloudSTT registry: the app pre-registers a provider + model string +
 * API key under an id at startup, and the router refers to it by id (the id is
 * the online HybridModel.id). Registration is process-lifetime, in-memory.
 *
 * Matches:
 *   - Swift  `Sources/RunAnywhere/Hybrid/CloudSTT.swift`
 *   - Kotlin `public/hybrid/Backend.kt` (object BACKEND.CLOUD)
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import { CloudSttBackendConfig } from '@runanywhere/proto-ts/hybrid_router';
import { DEFAULT_CLOUD_PROVIDER } from './HybridModel';

const logger = new SDKLogger('CloudSTT');

/**
 * A registered cloud-STT model: the generated `CloudSttBackendConfig`
 * (provider, wire model string + credentials) keyed by an app-chosen `id`.
 * The id becomes the online `HybridModel.id`; the rest is the exact wire
 * config the routed "cloud" plugin's `create` consumes.
 */
export type CloudModelEntry = CloudSttBackendConfig & {
  /** App-supplied registry id (becomes the online HybridModel.id). */
  readonly id: string;
};

/** Options for registering a cloud STT model. */
export interface CloudRegisterOptions {
  /** App-chosen registry id. */
  id: string;
  /** Provider model id (e.g. "saarika:v2.5"). */
  model: string;
  /** Provider API subscription key. */
  apiKey: string;
  /** Cloud provider; defaults to "sarvam". Forwarded via config_json.provider. */
  provider?: string;
  /** Optional BCP-47 language hint ("en-IN", "hi-IN", …). */
  languageCode?: string;
  /** Optional base URL override. */
  baseUrl?: string;
  /** Optional request timeout in milliseconds. */
  timeoutMs?: number;
}

const registry = new Map<string, CloudModelEntry>();
let pluginRegistered = false;

/**
 * Generic cloud speech-to-text backend. Fronts one or more HTTP STT providers
 * (Sarvam first); the provider is data carried in each registered model entry.
 */
export const CloudSTT = {
  /** Default cloud STT provider when a caller omits one. */
  defaultProvider: DEFAULT_CLOUD_PROVIDER,

  /**
   * Register the cloud backend with the commons plugin registry so the
   * unified "cloud" plugin becomes routable. Safe to call multiple times —
   * the native side treats already-registered as success. Mirrors
   * `ONNX.register()`.
   */
  async register(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      throw SDKException.nativeModuleUnavailable();
    }
    if (pluginRegistered) {
      return true;
    }
    logger.info('Registering cloud backend with commons registry...');
    const ok = await requireNativeModule().cloudRegister();
    if (ok) {
      pluginRegistered = true;
      logger.info(
        `cloud backend registered (default provider ${DEFAULT_CLOUD_PROVIDER})`
      );
    } else {
      logger.warning('cloud backend registration did not succeed');
    }
    return ok;
  },

  /** Unregister the cloud backend from the commons registry. */
  async unregister(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    pluginRegistered = false;
    return requireNativeModule().cloudUnregister();
  },

  /** Whether the cloud plugin is currently registered for TRANSCRIBE. */
  async isRegistered(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    return requireNativeModule().cloudIsRegistered();
  },

  /**
   * Register a cloud-STT model under `id` so the router can refer to it by id
   * from `onlineCloud(id)`. The registry is in-memory; entries live for the
   * process lifetime unless removed via {@link unregisterModel} / {@link clear}.
   *
   * Also fires the native plugin registration (idempotently) at the same
   * bootstrap point — symmetric to `ONNX.register()` seeding the on-device
   * backend.
   */
  async register_model(options: CloudRegisterOptions): Promise<void> {
    const provider = options.provider ?? DEFAULT_CLOUD_PROVIDER;
    if (!options.id) throw SDKException.invalidInput('CloudSTT registry id must be non-empty');
    if (!options.model) throw SDKException.invalidInput('CloudSTT model string must be non-empty');
    if (!options.apiKey) throw SDKException.invalidInput('CloudSTT apiKey must be non-empty');
    if (!provider) throw SDKException.invalidInput('CloudSTT provider must be non-empty');
    await this.register();
    registry.set(options.id, {
      id: options.id,
      ...CloudSttBackendConfig.fromPartial({
        provider,
        model: options.model,
        apiKey: options.apiKey,
        languageCode: options.languageCode,
        baseUrl: options.baseUrl,
        timeoutMs: options.timeoutMs,
      }),
    });
  },

  /** Look up a previously registered model by id. */
  lookup(id: string): CloudModelEntry | undefined {
    return registry.get(id);
  },

  /** True iff a model is registered under `id`. */
  isModelRegistered(id: string): boolean {
    return registry.has(id);
  },

  /** Remove a registered model. Returns true when an entry was removed. */
  unregisterModel(id: string): boolean {
    return registry.delete(id);
  },

  /** Clear the in-memory model registry. */
  clear(): void {
    registry.clear();
  },

  /**
   * Build the config JSON the routed "cloud" plugin's `create` consumes from
   * a registered entry. Carries `provider` so the engine selects the right HTTP
   * backend. Throws when `id` is not registered.
   */
  configJSON(id: string): string {
    const entry = registry.get(id);
    if (!entry) {
      throw SDKException.invalidInput(
        `CloudSTT model id '${id}' not registered. ` +
          'Call CloudSTT.register_model({ id, model, apiKey }) at app startup.'
      );
    }
    // The routed "cloud" plugin's create consumes snake_case keys
    // (rac_backend_cloud_create), so emit those explicitly from the typed
    // CloudSttBackendConfig rather than its camelCase proto-JSON. Omit
    // empty/zero optionals so the provider falls back to its own defaults.
    const json: Record<string, string | number> = {
      provider: entry.provider,
      api_key: entry.apiKey,
      model: entry.model,
    };
    if (entry.languageCode) json.language_code = entry.languageCode;
    if (entry.baseUrl) json.base_url = entry.baseUrl;
    if (entry.timeoutMs) json.timeout_ms = entry.timeoutMs;
    return JSON.stringify(json);
  },
};
