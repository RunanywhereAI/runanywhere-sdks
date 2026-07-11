/**
 * LlamaCPP — public facade for the `@runanywhere/web-llamacpp` backend.
 *
 * V2 canonical: this package is a SHELL. It only loads the WASM module,
 * registers the platform adapter, calls `rac_init`, registers the unified
 * llama.cpp backend (LLM + VLM in a single call), then installs the module
 * on every core proto-byte adapter via `setRunanywhereModule(...)`.
 *
 * After `LlamaCPP.register()` resolves, `RunAnywhere.textGeneration.*`,
 * tool calling, structured output,
 * embeddings, and diffusion all flow through `@runanywhere/web` core's
 * proto-byte adapters (`LLMProtoAdapter`, `EmbeddingsProtoAdapter`,
 * `DiffusionProtoAdapter`, `StructuredOutputProtoAdapter`,
 * `VLMProtoAdapter`, etc.) without any further per-package wiring.
 *
 * Usage:
 *
 *     import { RunAnywhere } from '@runanywhere/web';
 *     import { LlamaCPP } from '@runanywhere/web-llamacpp';
 *
 *     await RunAnywhere.initialize({ environment: 'development' });
 *     await LlamaCPP.register({ acceleration: 'auto' });
 *
 *     const stream = await RunAnywhere.textGeneration.generateStream({
 *       prompt: 'Hello!',
 *       maxTokens: 256,
 *     });
 *     for await (const token of stream.stream) {
 *       process.stdout.write(token);
 *     }
 *     const result = await stream.result;
 */

import {
  completeDeferredServicesInitialization,
  setAccelerationSwitcher,
  setActiveAccelerationMode,
  setModelLoadPreparation,
  setModelLoadFailureRecovery,
  setVisionLanguageProvider,
  SDKLogger,
  type BackendRegistrationState,
  type RuntimeModelLoadRequest,
} from '@runanywhere/web/backend';
import {
  ModelCategory,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { LlamaCppBridge } from './Foundation/LlamaCppBridge.js';
import { LifecycleVLMProvider } from './Infrastructure/LifecycleVLMProvider.js';

const logger = new SDKLogger('LlamaCPP');

const MODULE_ID = 'llamacpp';

let _isRegistered = false;
let _registeringPromise: Promise<void> | null = null;
let _registrationState: BackendRegistrationState = 'unregistered';
const lifecycleVLMProvider = new LifecycleVLMProvider();

function modelLoadCategory(
  request: RuntimeModelLoadRequest,
  model: ModelInfo | null,
): ModelCategory | undefined {
  const requestCategory = request.category;
  if (requestCategory !== undefined) return requestCategory;
  return model?.category;
}

function isVisionModelCategory(category: ModelCategory | undefined): boolean {
  return category === ModelCategory.MODEL_CATEGORY_MULTIMODAL ||
    category === ModelCategory.MODEL_CATEGORY_VISION;
}

function modelIdFromLoadRequest(request: RuntimeModelLoadRequest): string {
  return request.modelId.toLowerCase();
}

function shouldPrepareCpuForModelLoad(
  bridge: LlamaCppBridge,
  request: RuntimeModelLoadRequest,
  model: ModelInfo | null,
): boolean {
  if (bridge.accelerationMode !== 'webgpu') return false;
  const modelId = modelIdFromLoadRequest(request);
  if (!modelId) return false;
  if (!isVisionModelCategory(modelLoadCategory(request, model))) return false;
  return modelId.includes('qwen');
}

// Categories the LlamaCpp backend actually services. STT/TTS/VAD/embedding
// requests are owned by other backends (Sherpa, ONNX, ...) and must never
// trigger LlamaCpp's WebGPU→CPU fallback path — otherwise unrelated load
// failures (e.g. a Sherpa whisper signature mismatch) surface to the user
// as a misleading "WebGPU model load failed" log + bogus CPU retry.
const LLAMACPP_ELIGIBLE_CATEGORIES: ReadonlySet<ModelCategory> = new Set([
  ModelCategory.MODEL_CATEGORY_LANGUAGE,
  ModelCategory.MODEL_CATEGORY_VISION,
  ModelCategory.MODEL_CATEGORY_MULTIMODAL,
]);

function shouldFallbackWebGPUModelLoad(
  bridge: LlamaCppBridge,
  request: RuntimeModelLoadRequest,
  error: unknown,
): boolean {
  if (bridge.accelerationMode !== 'webgpu') return false;
  if (!request.modelId) return false;
  // Require an explicit, LlamaCpp-eligible category. An undefined/unknown
  // category is treated as "not ours" so STT/TTS requests that bubble up
  // load failures don't get incorrectly retried through this hook.
  if (
    request.category === undefined ||
    !LLAMACPP_ELIGIBLE_CATEGORIES.has(request.category)
  ) {
    return false;
  }
  // Emscripten can throw either Error instances, RuntimeError instances, or
  // opaque C++ exception objects depending on how the wasm trap crosses JSPI.
  // Once we know the failed request is a WebGPU model load for an LLM/VLM
  // request, retrying on CPU is the safest recovery path.
  return Boolean(error);
}

export interface LlamaCPPRegisterOptions {
  /** Hardware acceleration strategy. Defaults to `'auto'` (WebGPU if available, otherwise CPU). */
  acceleration?: 'auto' | 'webgpu' | 'cpu';
  /** Override the URL to the racommons-llamacpp.js glue file (CPU). */
  wasmUrl?: string;
  /** Override the URL to the racommons-llamacpp-webgpu.js glue file. */
  webgpuWasmUrl?: string;
}

export const LlamaCPP = {
  /** Unique module identifier. */
  get moduleId(): string {
    return MODULE_ID;
  },

  /** Whether the backend is registered. */
  get isRegistered(): boolean {
    return _isRegistered;
  },

  /** Typed registration lifecycle for UI and diagnostics. */
  get registrationState(): BackendRegistrationState {
    return _registrationState;
  },

  /** Active hardware acceleration mode (cpu | webgpu). Available after `register()`. */
  get accelerationMode(): 'cpu' | 'webgpu' {
    return LlamaCppBridge.shared.accelerationMode;
  },

  /**
   * Register the llama.cpp backend with the RunAnywhere SDK.
   *
   * Must be called after `RunAnywhere.initialize(...)`.
   *
   * 1. Loads the appropriate WASM variant (CPU or WebGPU).
   * 2. Verifies via `_rac_wasm_ping()` smoke check.
   * 3. Registers the 11-callback `rac_platform_adapter_t` browser vtable.
   * 4. Calls `rac_init()` (async, may suspend through ASYNCIFY).
   * 5. Calls `rac_backend_llamacpp_register()` — the unified entry point
   *    that wires both LLM and VLM modalities in a single call.
   * 6. Installs the module on `setRunanywhereModule()` so every core
   *    proto-byte adapter (LLM/VLM/embeddings/diffusion/structured/tool/
   *    model-registry/lifecycle/download/hardware/storage/SDKEvent/HTTP)
   *    can find it.
   * 7. Wires `RunAnywhere.runtime.setAcceleration(mode)` to the bridge's
   *    acceleration switcher.
   *
   * Idempotent — concurrent callers share the same in-flight promise.
   */
  async register(options: LlamaCPPRegisterOptions = {}): Promise<void> {
    if (_isRegistered) {
      logger.debug('LlamaCpp backend already registered, skipping');
      return;
    }
    if (_registeringPromise) {
      logger.debug('LlamaCpp registration in progress, awaiting...');
      return _registeringPromise;
    }

    _registeringPromise = (async () => {
      _registrationState = 'registering';
      const bridge = LlamaCppBridge.shared;
      try {
        if (options.wasmUrl) bridge.wasmUrl = options.wasmUrl;
        if (options.webgpuWasmUrl) bridge.webgpuWasmUrl = options.webgpuWasmUrl;

        // Wire `RunAnywhere.runtime.setAcceleration(mode)` into the bridge.
        // Cleared on `unregister()`. Mirrors the previous public surface so
        // the core's `RuntimeConfig.setAcceleration` actually works.
        setAccelerationSwitcher(async (mode) => {
          await bridge.switchToAcceleration(mode);
          setActiveAccelerationMode(bridge.accelerationMode);
        });
        setModelLoadPreparation(async ({ request, model }) => {
          if (!shouldPrepareCpuForModelLoad(bridge, request, model)) return;
          logger.warning(
            `WebGPU VLM load is not stable for ${request.modelId}; loading with the CPU WASM artifact.`,
          );
          await bridge.switchToAcceleration('cpu');
          setActiveAccelerationMode(bridge.accelerationMode);
        });
        setModelLoadFailureRecovery(async ({ request, error }) => {
          if (!shouldFallbackWebGPUModelLoad(bridge, request, error)) return false;
          logger.warning(
            `WebGPU model load failed for ${request.modelId}; retrying with the CPU WASM artifact.`,
          );
          await bridge.switchToAcceleration('cpu');
          setActiveAccelerationMode(bridge.accelerationMode);
          return true;
        });

        await bridge.ensureLoaded(options.acceleration ?? 'auto');

        // Publish the active mode so `RunAnywhere.runtime.active` reflects
        // what the bridge actually picked (auto → webgpu/cpu resolution).
        setActiveAccelerationMode(bridge.accelerationMode);

        // VLM is wired alongside LLM by the unified
        // `rac_backend_llamacpp_register()` call, so once `ensureLoaded()`
        // resolves successfully the VLM provider is always installable.
        // The `bridge.isVLMRegistered` gate is retained for parity with
        // Swift's `isVLMRegistered` field; under the unified C++ layer it
        // simply reflects that the backend module is loaded.
        if (bridge.isVLMRegistered) {
          setVisionLanguageProvider(lifecycleVLMProvider);
        } else {
          logger.info(
            'VLM backend not registered — RunAnywhere.visionLanguage will report as unavailable.',
          );
        }
        await completeDeferredServicesInitialization();

        _isRegistered = true;
        _registrationState = 'registered';
        logger.info(`LlamaCpp backend registered (${bridge.accelerationMode})`);
      } catch (error) {
        // Registration installs core hooks before deferred service startup.
        // A late failure must not leave those hooks pointing at a backend that
        // reports `isRegistered === false` or retain a partially loaded module.
        setAccelerationSwitcher(null);
        setActiveAccelerationMode(null);
        setModelLoadPreparation(null);
        setModelLoadFailureRecovery(null);
        setVisionLanguageProvider(null);
        bridge.shutdown();
        _isRegistered = false;
        _registrationState = 'failed';
        throw error;
      } finally {
        _registeringPromise = null;
      }
    })();

    return _registeringPromise;
  },

  /**
   * Unregister the backend and release its WASM module.
   */
  unregister(): void {
    if (!_isRegistered) {
      _registrationState = 'unregistered';
      return;
    }
    setAccelerationSwitcher(null);
    setActiveAccelerationMode(null);
    setModelLoadPreparation(null);
    setModelLoadFailureRecovery(null);
    setVisionLanguageProvider(null);
    LlamaCppBridge.shared.shutdown();
    _isRegistered = false;
    _registrationState = 'unregistered';
    logger.info('LlamaCpp backend unregistered');
  },
};

/**
 * Auto-register the llama.cpp backend.
 *
 * Convenience helper for app boot scripts that don't care about catching
 * the registration error (e.g. when Vite tries to load the WASM but the
 * file isn't present yet during a dev cold start).
 */
export function autoRegister(
  options: LlamaCPPRegisterOptions = {},
): Promise<void> {
  return LlamaCPP.register(options).catch((err: unknown) => {
    logger.warning(
      `LlamaCpp auto-registration failed: ${err instanceof Error ? err.message : String(err)}`,
    );
  });
}
