/**
 * LlamaCPP — public facade for the `@runanywhere/web-llamacpp` backend.
 *
 * V2 canonical: this package is a SHELL. It only loads the WASM module,
 * registers the platform adapter, calls `rac_init`, registers the unified
 * llama.cpp backend (LLM + VLM in a single call), then installs the module
 * only in its capability-scoped adapter slots via `registerWasmModule(...)`.
 *
 * After `LlamaCPP.register()` resolves, `RunAnywhere.textGeneration.*`,
 * tool calling, structured output, LoRA, and VLM all flow through
 * `@runanywhere/web` core's proto-byte adapters (`LLMProtoAdapter`,
 * `StructuredOutputProtoAdapter`, `VLMProtoAdapter`, etc.) without any
 * further per-package wiring. ONNX owns Web embeddings and cross-WASM RAG.
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
  BackendWorkerHost,
  clearLlamaBackendWorkerDead,
  setAccelerationSwitcher,
  setActiveAccelerationMode,
  setModelLoadPreparation,
  setModelLoadFailureRecovery,
  setRuntimeDegradedReason,
  setVisionLanguageProvider,
  getBackendWorkerFactory,
  setBackendWorkerFactory,
  setLlamaBackendWorkerRequired,
  setStreamWorkerFactory,
  setStreamWorkerInit,
  SDKLogger,
  type BackendRegistrationState,
  type BackendWorkerFactory,
  type RuntimeModelLoadRequest,
} from '@runanywhere/web/backend';
import {
  ModelCategory,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { LlamaCppBridge } from './Foundation/LlamaCppBridge.js';
import {
  LLAMACPP_STREAM_WORKER_FACTORY_ID,
  LLAMACPP_STREAM_WORKER_WEBGPU_FACTORY_ID,
} from './streamWorkerFactoryId.js';
import { LifecycleVLMProvider } from './Infrastructure/LifecycleVLMProvider.js';

const logger = new SDKLogger('LlamaCPP');
let _installedBackendWorkerFactory = false;
let _backendWorkerFactory: BackendWorkerFactory | null = null;
let _backendWorkerHost: BackendWorkerHost | null = null;
/** Acceleration used for LLM inference (worker when present, else bridge). */
let _inferenceAcceleration: 'cpu' | 'webgpu' = 'cpu';
let _installedStreamWorker = false;

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
  /**
   * Optional Stage 3 worker bootstrap. When omitted and `preferBackendWorker`
   * is enabled, LlamaCPP installs a Vite-friendly default factory that loads
   * `./backendWorker.ts`.
   */
  backendWorkerFactory?: BackendWorkerFactory;
  /**
   * Prefer the model-owning BackendWorker for LLM load/stream. Defaults to
   * `true` when `Worker` + `URL` are available. The worker prefers the
   * no-pthread WebGPU WASM when possible; CPU pthread artifacts set
   * `mainScriptUrlOrBlob` so nested `em-pthread` workers can boot.
   */
  preferBackendWorker?: boolean;
  /**
   * Fail registration when the BackendWorker handshake cannot complete.
   * Defaults to `true` in browser environments (Worker available); `false`
   * in Node/unit tests without Worker.
   */
  requireBackendWorker?: boolean;
  /**
   * Install the T6.1 stream-worker mirror. Opt-in only and mutually exclusive
   * with the model-owning BackendWorker path. Defaults to `false`.
   */
  enableStreamWorker?: boolean;
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

  /**
   * Acceleration used for LLM inference (cpu | webgpu).
   * When the BackendWorker owns the model, this is the worker's resolved mode
   * (WebGPU-first), not the main-thread bridge which may stay on CPU.
   */
  get accelerationMode(): 'cpu' | 'webgpu' {
    return _inferenceAcceleration;
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
   * 6. Registers the module for its actual LLM/VLM/structured/tool/LoRA
   *    capabilities while leaving ONNX embeddings and cross-WASM RAG intact.
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

        // When the BackendWorker owns LLM inference, keep the main-thread
        // bridge on CPU so we do not open a second WebGPU device (dual
        // WebGPU modules have been correlated with worker generate Abort()).
        // The worker still resolves auto → WebGPU when the adapter supports it.
        const workerAvailable = typeof Worker !== 'undefined' && typeof URL !== 'undefined';
        const preferWorker = options.preferBackendWorker !== false && workerAvailable;
        const requested = options.acceleration ?? 'auto';
        const bridgeAcceleration = preferWorker && requested !== 'cpu'
          ? 'cpu'
          : requested;
        await bridge.ensureLoaded(bridgeAcceleration);
        await installLlamaCppBackendWorker(options, bridge.accelerationMode);
        const enableStreamWorker = options.enableStreamWorker === true
          && typeof Worker !== 'undefined'
          && typeof URL !== 'undefined'
          && _backendWorkerHost == null;
        if (enableStreamWorker) {
          try {
            await installLlamaCppStreamWorker(bridge.accelerationMode === 'webgpu');
            _installedStreamWorker = true;
          } catch (error) {
            logger.warning(
              `Stream worker bootstrap failed; keeping main-thread streaming: ${
                error instanceof Error ? error.message : String(error)
              }`,
            );
          }
        }

        // Prefer the worker's resolved acceleration for runtime.active so the
        // UI badge matches where inference actually runs.
        let publishedMode: 'cpu' | 'webgpu' = bridge.accelerationMode;
        if (_backendWorkerHost) {
          try {
            const health = await _backendWorkerHost.health();
            const details = health.details as { acceleration?: string } | undefined;
            if (details?.acceleration === 'webgpu' || details?.acceleration === 'cpu') {
              publishedMode = details.acceleration;
            }
          } catch {
            /* keep bridge mode */
          }
        }
        _inferenceAcceleration = publishedMode;
        setActiveAccelerationMode(publishedMode);

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
        _isRegistered = true;
        _registrationState = 'registered';
        logger.info(
          `LlamaCpp backend registered (bridge=${bridge.accelerationMode}, inference=${publishedMode}`
          + `${_backendWorkerHost ? ', executionContext=worker' : ''})`,
        );
      } catch (error) {
        // Registration installs core hooks before deferred service startup.
        // A late failure must not leave those hooks pointing at a backend that
        // reports `isRegistered === false` or retain a partially loaded module.
        setAccelerationSwitcher(null);
        setActiveAccelerationMode(null);
        setModelLoadPreparation(null);
        setModelLoadFailureRecovery(null);
        setVisionLanguageProvider(null);
        clearLlamaCppBackendWorker();
        clearLlamaCppStreamWorker();
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
    clearLlamaCppBackendWorker();
    clearLlamaCppStreamWorker();
    LlamaCppBridge.shared.shutdown();
    _inferenceAcceleration = 'cpu';
    _isRegistered = false;
    _registrationState = 'unregistered';
    logger.info('LlamaCpp backend unregistered');
  },
};

async function installLlamaCppBackendWorker(
  options: LlamaCPPRegisterOptions,
  accelerationMode: 'cpu' | 'webgpu',
): Promise<void> {
  const workerAvailable = typeof Worker !== 'undefined' && typeof URL !== 'undefined';
  const prefer = options.preferBackendWorker !== false && workerAvailable;
  if (!prefer) {
    const reason = !workerAvailable
      ? 'Web Worker API unavailable; LLM inference stays on the main thread.'
      : 'BackendWorker disabled via LlamaCPP.register({ preferBackendWorker: false }).';
    setRuntimeDegradedReason(reason);
    if (options.requireBackendWorker) {
      throw new Error(reason);
    }
    return;
  }

  if (!globalThis.crossOriginIsolated) {
    logger.warning(
      'crossOriginIsolated is false; pthread-backed BackendWorker WASM may fail. '
      + 'Serve with COOP/COEP headers for production worker inference.',
    );
  }

  const factory = options.backendWorkerFactory
    ?? (() => new Worker(new URL('./backendWorker.ts', import.meta.url), {
      type: 'module',
      name: 'runanywhere-llamacpp-backend',
    }));
  setBackendWorkerFactory(factory);
  _installedBackendWorkerFactory = true;
  _backendWorkerFactory = factory;

  const requireWorker = options.requireBackendWorker
    ?? (typeof Worker !== 'undefined' && typeof URL !== 'undefined');
  setLlamaBackendWorkerRequired(requireWorker);
  const host = new BackendWorkerHost(factory, {
    initTimeoutMs: 120_000,
    backendId: 'llamacpp',
  });
  _backendWorkerHost = host;
  try {
    // WebGPU-first inside the worker; CPU WASM only when WebGPU/shader-f16
    // is unavailable (WorkerLlamaRuntime resolves auto → cpu). If a later
    // generate Abort()s the worker, BackendWorkerHost retries next init on CPU.
    await host.init({
      acceleration: options.acceleration === 'cpu' ? 'cpu' : 'auto',
    });
    clearLlamaBackendWorkerDead();
    setRuntimeDegradedReason(null);
    logger.info(
      `BackendWorker ready (executionContext=worker; main bridge=${accelerationMode})`,
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    host.dispose();
    _backendWorkerHost = null;
    if (_installedBackendWorkerFactory && getBackendWorkerFactory() === _backendWorkerFactory) {
      setBackendWorkerFactory(null);
    }
    _installedBackendWorkerFactory = false;
    _backendWorkerFactory = null;
    const reason = `BackendWorker handshake failed: ${message}`;
    setRuntimeDegradedReason(reason);
    if (requireWorker) {
      logger.error(`${reason}; main-thread LLM inference is disabled`);
      throw error instanceof Error ? error : new Error(reason);
    }
    setLlamaBackendWorkerRequired(false);
    logger.warning(`${reason}; continuing without BackendWorker (requireBackendWorker=false)`);
  }
}

function clearLlamaCppBackendWorker(): void {
  if (_backendWorkerHost) {
    try {
      _backendWorkerHost.dispose();
    } catch {
      /* ignore */
    }
    _backendWorkerHost = null;
  }
  if (_installedBackendWorkerFactory && getBackendWorkerFactory() === _backendWorkerFactory) {
    setBackendWorkerFactory(null);
  }
  _installedBackendWorkerFactory = false;
  _backendWorkerFactory = null;
  setRuntimeDegradedReason(null);
}

async function installLlamaCppStreamWorker(useWebGPU: boolean): Promise<void> {
  const wasmName = useWebGPU
    ? 'racommons-llamacpp-webgpu.wasm'
    : 'racommons-llamacpp.wasm';
  const wasmUrl = new URL(`../wasm/${wasmName}`, import.meta.url).href;
  const wasmResponse = await fetch(wasmUrl);
  if (!wasmResponse.ok) {
    throw new Error(`Failed to fetch stream-worker WASM (${wasmResponse.status}): ${wasmName}`);
  }
  const wasmBytes = await wasmResponse.arrayBuffer();
  setStreamWorkerFactory(() => new Worker(new URL('./streamWorker.ts', import.meta.url), {
    type: 'module',
    name: 'runanywhere-llamacpp-stream',
  }));
  setStreamWorkerInit({
    wasmBytes,
    moduleFactoryId: useWebGPU
      ? LLAMACPP_STREAM_WORKER_WEBGPU_FACTORY_ID
      : LLAMACPP_STREAM_WORKER_FACTORY_ID,
  });
  logger.info(`Stream worker installed (${useWebGPU ? 'webgpu' : 'cpu'})`);
}

function clearLlamaCppStreamWorker(): void {
  if (!_installedStreamWorker) return;
  setStreamWorkerFactory(null);
  setStreamWorkerInit(null);
  _installedStreamWorker = false;
}

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
