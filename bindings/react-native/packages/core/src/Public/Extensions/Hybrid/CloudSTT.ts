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
import { isJsonObject } from '../../../services/JSONValidation';

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

/**
 * One complete cloud STT request handed to a custom provider handler.
 * Mirrors Swift `CloudSttRequest` (CloudSttProvider.swift).
 */
export interface CloudSttProviderRequest {
  /**
   * The registered cloud entry, decoded from commons' config JSON
   * (keys: provider, api_key, model, base_url, language_code, timeout_ms).
   */
  config: {
    provider?: string;
    apiKey?: string;
    model?: string;
    baseUrl?: string;
    languageCode?: string;
    timeoutMs?: number;
  };
  /** Audio bytes for this utterance. */
  audio: ArrayBuffer;
  /** `rac_audio_format_enum_t` value describing the audio bytes. */
  audioFormat: number;
}

/**
 * A custom provider handler's transcription result.
 * Mirrors Swift `CloudSttResult` (CloudSttProvider.swift).
 */
export interface CloudSttProviderResult {
  text: string;
  languageCode?: string;
  confidence?: number;
}

/**
 * Performs a complete cloud STT request host-side for one utterance.
 * Implementations build and send the HTTP request and parse the response.
 * Mirrors Swift `Cloud.SttProviderHandler`.
 */
export type CloudSttProviderHandler = (
  request: CloudSttProviderRequest
) => Promise<CloudSttProviderResult>;

const registry = new Map<string, CloudModelEntry>();
const registeredProviders = new Set<string>();
let pluginRegistered = false;

/** Decode commons' snake_case config JSON into the typed request config. */
export function decodeCloudSttProviderConfigJSON(
  configJson: string
): CloudSttProviderRequest['config'] {
  let raw: unknown;
  try {
    raw = JSON.parse(configJson);
  } catch {
    return {};
  }
  if (!isJsonObject(raw)) return {};

  return {
    ...(typeof raw.provider === 'string' ? { provider: raw.provider } : {}),
    ...(typeof raw.api_key === 'string' ? { apiKey: raw.api_key } : {}),
    ...(typeof raw.model === 'string' ? { model: raw.model } : {}),
    ...(typeof raw.base_url === 'string' ? { baseUrl: raw.base_url } : {}),
    ...(typeof raw.language_code === 'string'
      ? { languageCode: raw.language_code }
      : {}),
    ...(typeof raw.timeout_ms === 'number' && Number.isFinite(raw.timeout_ms)
      ? { timeoutMs: raw.timeout_ms }
      : {}),
  };
}

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
  async registerModel(options: CloudRegisterOptions): Promise<void> {
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
   * Register (or replace) a developer-defined cloud STT provider handler.
   * The handler performs the whole request host-side (build + HTTP + parse),
   * so any vendor works without a native adapter. Tie a model to it by
   * calling `registerModel` with the same `provider` string:
   *
   *     await CloudSTT.registerProvider('deepgram', async ({ config, audio }) => {
   *       // build + POST with fetch, parse the JSON …
   *       return { text: transcript, confidence: score };
   *     });
   *     await CloudSTT.registerModel({
   *       id: 'dg-nova2', provider: 'deepgram', model: 'nova-2', apiKey: '…',
   *     });
   *
   * The handler may be invoked concurrently and may block on network.
   * Built-in providers (e.g. "sarvam") cannot be shadowed — a static adapter
   * always wins over a host callback of the same name.
   * Mirrors Swift `Cloud.registerProvider(_:_:)` (CloudSttProvider.swift:145).
   */
  async registerProvider(
    name: string,
    handler: CloudSttProviderHandler
  ): Promise<boolean> {
    if (!name) {
      throw SDKException.invalidInput('cloud provider name must be non-empty');
    }
    if (!isNativeModuleAvailable()) {
      throw SDKException.nativeModuleUnavailable();
    }
    const ok = await requireNativeModule().cloudRegisterSttProvider(
      name,
      async (configJson, audioBytes, audioFormat) => {
        try {
          const result = await handler({
            config: decodeCloudSttProviderConfigJSON(configJson),
            audio: audioBytes,
            audioFormat,
          });
          return JSON.stringify({
            text: result.text ?? '',
            ...(result.languageCode
              ? { language_code: result.languageCode }
              : {}),
            ...(typeof result.confidence === 'number' &&
            Number.isFinite(result.confidence)
              ? { confidence: result.confidence }
              : {}),
            error_code: 0,
            error_message: '',
          });
        } catch (error) {
          const message =
            error instanceof Error ? error.message : String(error);
          logger.error(`cloud provider '${name}' handler failed: ${message}`);
          return JSON.stringify({
            text: '',
            error_code: 1,
            error_message: message,
          });
        }
      }
    );
    if (ok) {
      registeredProviders.add(name);
    } else {
      logger.warning(`cloud provider '${name}' registration did not succeed`);
    }
    return ok;
  },

  /**
   * Remove a developer-defined provider previously registered via
   * `registerProvider`. Idempotent for unknown names.
   * Mirrors Swift `Cloud.unregisterProvider(_:)` (CloudSttProvider.swift:209).
   */
  async unregisterProvider(name: string): Promise<void> {
    if (!name || !isNativeModuleAvailable()) {
      return;
    }
    registeredProviders.delete(name);
    await requireNativeModule().cloudUnregisterSttProvider(name);
  },

  /** True iff a custom provider handler is registered under `name`. */
  isProviderRegistered(name: string): boolean {
    return registeredProviders.has(name);
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
          'Call CloudSTT.registerModel({ id, model, apiKey }) at app startup.'
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
