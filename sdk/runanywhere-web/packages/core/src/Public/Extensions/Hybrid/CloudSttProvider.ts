/**
 * CloudSttProvider.ts
 *
 * Web binding for the cross-SDK named cloud STT provider table
 * (rac_cloud_stt_provider.h). The `cloud` engine ships static adapters for
 * built-in providers (e.g. "sarvam"). For any other vendor, register a
 * handler by name via `CloudSTT.registerProvider` and tie a model to it with
 * `CloudSTT.register({ id, provider, ... })` (same `provider` string). The
 * cloud engine then delegates the ENTIRE request — build, HTTP, and response
 * parse — to the handler, so a developer supports any cloud STT API (key,
 * URL, request and response shape) without a native adapter or a recompile.
 *
 * Mirrors Swift `CloudSttProvider.swift` (`Cloud.registerProvider` /
 * `Cloud.unregisterProvider`, lines 145 / 209) and Kotlin's
 * `CloudSttProvider.kt`. The Swift handler may block on network; under
 * single-threaded WASM the trampoline is invoked synchronously, so the Web
 * handler must return its `CloudSttResult` synchronously. Thrown errors are
 * encoded as `{"error_code":1,...}` and surface to the router as a transcribe
 * failure (so the cascade policy can fall back) — never as a JS exception
 * crossing the C boundary.
 */

import { SDKLogger } from '../../../Foundation/SDKLogger';
import {
  RAC_OK,
  RAC_ERROR_NULL_POINTER,
  RAC_ERROR_OUT_OF_MEMORY,
} from '../../../Foundation/RACErrors';
import { CloudSTT, cloudCapableModule } from './CloudSTT';
import type { EmscriptenRunanywhereModule } from '../../../runtime/EmscriptenModule';

const logger = new SDKLogger('Cloud.SttProvider');

/**
 * Audio container of the bytes handed to a cloud STT handler. Values mirror
 * the native `rac_audio_format_enum_t` (and Swift `CloudAudioFormat`).
 */
export enum CloudAudioFormat {
  PCM = 0,
  WAV = 1,
  MP3 = 2,
  OPUS = 3,
  AAC = 4,
  FLAC = 5,
  UNKNOWN = -1,
}

/** One cloud transcribe request handed to a registered provider handler. */
export interface CloudSttRequest {
  /** The provider name this entry was registered under. */
  provider: string;
  /** The provider model id from `CloudSTT.register`. */
  model: string;
  /** The API key from registration. Sensitive; never log. */
  apiKey: string;
  /** Optional base-URL override from registration, if set. */
  baseUrl?: string;
  /** Optional BCP-47 language hint, if set. */
  languageCode?: string;
  /** Audio bytes for this utterance. */
  audio: Uint8Array;
  /** Container/encoding of `audio`. */
  audioFormat: CloudAudioFormat;
  /** The full registered config as JSON, for any extra keys a provider needs
   * beyond the typed fields above. */
  configJson: string;
}

/** Result of a cloud transcribe. */
export interface CloudSttResult {
  /** The transcript (empty if the provider found no speech). */
  text: string;
  /** Detected/echoed BCP-47 language, if the provider reports one. */
  languageCode?: string;
  /** Optional 0..1 confidence; omit when the provider returns no score
   * (Swift's `.nan` default). The hybrid router treats "no signal" as
   * never-cascade. */
  confidence?: number;
}

/**
 * Performs a complete cloud STT request host-side for one utterance.
 * Implementations build and send the HTTP request and parse the response.
 * Must be synchronous on Web (the C engine consumes the result inline).
 */
export type SttProviderHandler = (request: CloudSttRequest) => CloudSttResult;

/** WASM exports for the cloud provider table (rac_cloud_stt_provider.h).
 * Optional at the type level — current Web WASM builds do not export them
 * yet (see HybridWasmModule.ts BUILD DELTA for the export-list mechanics). */
interface CloudProviderModule extends EmscriptenRunanywhereModule {
  /** `rac_result_t rac_cloud_register_stt_provider(name, transcribe, user_data)`. */
  _rac_cloud_register_stt_provider?(
    namePtr: number,
    transcribeFnIdx: number,
    userData: number,
  ): number;
  /** `rac_result_t rac_cloud_unregister_stt_provider(const char* name)`. */
  _rac_cloud_unregister_stt_provider?(namePtr: number): number;
}

/** name → installed trampoline. An entry stays installed from register until
 * the matching unregister (after `rac_cloud_unregister_stt_provider`), so
 * commons never calls a removed function-table slot. */
const registeredProviders = new Map<string, { module: CloudProviderModule; fnPtr: number }>();

function allocCString(module: CloudProviderModule, value: string): number {
  const len = module.lengthBytesUTF8(value) + 1;
  const ptr = module._malloc(len);
  module.stringToUTF8(value, ptr, len);
  return ptr;
}

function audioFormatFromNative(value: number): CloudAudioFormat {
  switch (value) {
    case CloudAudioFormat.PCM:
    case CloudAudioFormat.WAV:
    case CloudAudioFormat.MP3:
    case CloudAudioFormat.OPUS:
    case CloudAudioFormat.AAC:
    case CloudAudioFormat.FLAC:
      return value;
    default:
      return CloudAudioFormat.UNKNOWN;
  }
}

function nonBlank(value: string | undefined): string | undefined {
  return value && value.length > 0 ? value : undefined;
}

/**
 * Decodes the registered config into a `CloudSttRequest`, runs the handler,
 * and encodes the engine-facing result JSON. Never throws — failures are
 * encoded as `{"error_code": 1, "error_message": "…"}`, which the engine
 * surfaces as a transcribe failure (mirrors Swift `invokeProviderHandler` /
 * Kotlin `NativeCloudSttProvider.invoke`).
 */
function invokeProviderHandler(
  handler: SttProviderHandler,
  configJson: string,
  audio: Uint8Array,
  audioFormat: CloudAudioFormat,
): string {
  /** Typed view of the registered cloud entry JSON (snake_case wire keys). */
  let config: {
    provider?: string;
    model?: string;
    api_key?: string;
    base_url?: string;
    language_code?: string;
  } = {};
  try {
    config = JSON.parse(configJson) as typeof config;
  } catch {
    config = {};
  }

  const request: CloudSttRequest = {
    provider: config.provider ?? '',
    model: config.model ?? '',
    apiKey: config.api_key ?? '',
    baseUrl: nonBlank(config.base_url),
    languageCode: nonBlank(config.language_code),
    audio,
    audioFormat,
    configJson,
  };

  try {
    const result = handler(request);
    return serializeResultJSON({
      text: result.text,
      languageCode: result.languageCode,
      confidence:
        result.confidence !== undefined && !Number.isNaN(result.confidence)
          ? result.confidence
          : undefined,
      errorCode: 0,
    });
  } catch (error) {
    return serializeResultJSON({
      errorCode: 1,
      errorMessage: error instanceof Error ? error.message : String(error),
    });
  }
}

/** Engine-facing result JSON parsed by the cloud engine's
 * parse_host_result_json (snake_case wire keys; absent fields omitted;
 * alphabetical key order matches Swift's `.sortedKeys`). */
function serializeResultJSON(result: {
  text?: string;
  languageCode?: string;
  confidence?: number;
  errorCode: number;
  errorMessage?: string;
}): string {
  const json: Record<string, string | number> = {};
  if (result.confidence !== undefined) json.confidence = result.confidence;
  json.error_code = result.errorCode;
  if (result.errorMessage !== undefined) json.error_message = result.errorMessage;
  if (result.languageCode !== undefined) json.language_code = result.languageCode;
  if (result.text !== undefined) json.text = result.text;
  return JSON.stringify(json);
}

/**
 * Register (or replace) a developer-defined cloud STT provider handler. The
 * handler performs the whole request host-side (build + HTTP + parse), so any
 * vendor works without a native adapter. Tie a model to it by calling
 * `CloudSTT.register` with the same `provider` string. Built-in providers
 * (e.g. "sarvam") cannot be shadowed — a static adapter always wins over a
 * host callback of the same name.
 *
 * Returns `false` (with an actionable log) when the loaded WASM build does
 * not export the provider-table ABI — same degradation contract as
 * `CloudSTT.registerBackend()`.
 *
 * Mirrors Swift `Cloud.registerProvider(_:_:)` (CloudSttProvider.swift:145).
 */
export function registerCloudSttProvider(
  name: string,
  handler: SttProviderHandler,
): boolean {
  if (!name) {
    logger.error('cloud provider name must be non-empty');
    return false;
  }

  // Ensure the cloud engine plugin is in the registry (idempotent), mirroring
  // Swift's `register()` call (CloudSttProvider.swift:153).
  CloudSTT.registerBackend();

  const module = cloudCapableModule() as CloudProviderModule | null;
  if (!module || typeof module._rac_cloud_register_stt_provider !== 'function') {
    logger.warning(
      'WASM module does not export _rac_cloud_register_stt_provider; the ' +
        'cloud provider table is not exported by this build. Add ' +
        '_rac_cloud_register_stt_provider / _rac_cloud_unregister_stt_provider ' +
        'to RAC_EXPORTED_FUNCTIONS (see HybridWasmModule.ts BUILD DELTA).',
    );
    return false;
  }

  // C trampoline (`rac_cloud_stt_transcribe_fn_t`): decode the registered
  // config + audio, dispatch to the JS handler, and hand back a malloc'd
  // result-JSON string commons frees via rac_cloud_stt_result_free.
  const fnPtr = module.addFunction(
    (
      configJsonPtr: number,
      audioPtr: number,
      audioLen: number,
      audioFormat: number,
      outResultJsonPtr: number,
      // userData (unused)
    ): number => {
      if (!outResultJsonPtr) return RAC_ERROR_NULL_POINTER;
      module.HEAPU32[outResultJsonPtr >>> 2] = 0;

      const configJson = configJsonPtr ? module.UTF8ToString(configJsonPtr) : '{}';
      const audio = audioPtr && audioLen > 0
        ? module.HEAPU8.slice(audioPtr, audioPtr + audioLen)
        : new Uint8Array(0);

      const resultJSON = invokeProviderHandler(
        handler,
        configJson,
        audio,
        audioFormatFromNative(audioFormat),
      );
      const byteLength = module.lengthBytesUTF8(resultJSON) + 1;
      const resultPtr = module._malloc(byteLength);
      if (!resultPtr) return RAC_ERROR_OUT_OF_MEMORY;
      module.stringToUTF8(resultJSON, resultPtr, byteLength);
      module.HEAPU32[outResultJsonPtr >>> 2] = resultPtr;
      return RAC_OK;
    },
    'iiiiiii',
  );

  const namePtr = allocCString(module, name);
  let rc: number;
  try {
    rc = module._rac_cloud_register_stt_provider(namePtr, fnPtr, 0);
  } finally {
    module._free(namePtr);
  }

  if (rc !== RAC_OK) {
    module.removeFunction(fnPtr);
    logger.error(`rac_cloud_register_stt_provider('${name}') failed: rc=${rc}`);
    return false;
  }

  // Replace any prior trampoline registered under the same name and retire it.
  const previous = registeredProviders.get(name);
  registeredProviders.set(name, { module, fnPtr });
  if (previous) previous.module.removeFunction(previous.fnPtr);
  return true;
}

/**
 * Remove a developer-defined provider previously registered via
 * `registerCloudSttProvider`. Idempotent for unknown names.
 *
 * Mirrors Swift `Cloud.unregisterProvider(_:)` (CloudSttProvider.swift:209).
 */
export function unregisterCloudSttProvider(name: string): void {
  if (!name) return;

  const previous = registeredProviders.get(name);
  const module = previous?.module
    ?? (cloudCapableModule() as CloudProviderModule | null);
  if (module && typeof module._rac_cloud_unregister_stt_provider === 'function') {
    const namePtr = allocCString(module, name);
    try {
      const rc = module._rac_cloud_unregister_stt_provider(namePtr);
      if (rc !== RAC_OK) {
        logger.error(`rac_cloud_unregister_stt_provider('${name}') failed: rc=${rc}`);
      }
    } finally {
      module._free(namePtr);
    }
  }

  // Per rac_cloud_stt_provider.h, unregister retires the previous table
  // snapshot one generation later, so an in-flight call could still be
  // running. We release our trampoline here regardless — registration
  // brackets policy install/teardown, when the router is not concurrently
  // transcribing (same rationale as Swift).
  if (previous) {
    registeredProviders.delete(name);
    previous.module.removeFunction(previous.fnPtr);
  }
}
