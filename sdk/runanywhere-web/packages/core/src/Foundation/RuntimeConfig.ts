/**
 * RuntimeConfig.ts
 *
 * Uniform runtime configuration surface — `RunAnywhere.runtime`.
 *
 * Today the Web SDK exposes acceleration switching via
 * `LlamaCppBridge.shared.switchToAcceleration('cpu' | 'webgpu')` which leaks
 * the backend implementation into application code. This module hides that
 * detail behind `RunAnywhere.runtime.setAcceleration(mode)` (mirrored in spirit
 * by the Swift `RunAnywhere.runtime` static surface).
 *
 * The actual switch is performed by a registered acceleration switcher,
 * installed by the llamacpp backend on `LlamaCPP.register()`. If no switcher
 * is registered the call is a no-op (graceful degradation on backend-less
 * builds).
 *
 * This file also exposes `RunAnywhere.runtime.preferred` as a read/write
 * preference field that backends can consult during their own load paths
 * (e.g. lazily applying the preferred mode the first time a model loads).
 */

import { SDKLogger } from './SDKLogger.js';
import { EventBus } from './EventBus.js';
import { EventCategory } from '@runanywhere/proto-ts/component_types';
import { getBackendWorkerRuntimeDiagnostics } from '../runtime/BackendWorkerHost.js';
import { getBackendWorkerHost } from '../runtime/BackendWorkerHostRegistry.js';
import type {
  InferenceFramework,
  ModelCategory,
  ModelInfo,
} from '@runanywhere/proto-ts/model_types';

const logger = new SDKLogger('Runtime');

/** Acceleration mode — superset of the Web-only `'webgpu'` and the `'auto'` preference. */
export type RuntimeAccelerationMode = 'cpu' | 'webgpu' | 'auto';

/**
 * Streaming delivery mode (T6.1).
 *
 *   - `'auto'`   — use the Worker path when a `streamWorkerFactory` is
 *                  registered (`@runanywhere/web-llamacpp` / `@runanywhere/web-onnx`
 *                  install one during `register()`); fall back to the
 *                  main-thread `queueMicrotask` path otherwise.
 *   - `'worker'` — require the Worker path. If no factory is registered
 *                  the bridge still returns `null` and the main-thread
 *                  fallback is used; a warning is logged on first use.
 *   - `'main'`   — force the main-thread path even when a Worker factory
 *                  is registered. Useful for debugging perf regressions.
 *
 */
export type StreamingMode = 'auto' | 'worker' | 'main';

/**
 * Advisory per-module memory ceilings for the 32-bit WebAssembly address
 * space. They are diagnostics, not reservations or hard runtime limits:
 * model metadata and browser memory pressure remain the source of truth.
 *
 * Keep every limit below WASM32's 4 GiB address space so a single module has
 * headroom for Emscripten allocations, JavaScript views, and stack growth.
 */
export interface RuntimeMemoryBudget {
  readonly wasm32AddressSpaceBytes: number;
  readonly perModuleSoftLimitBytes: Readonly<{
    core: number;
    llamacppCpu: number;
    llamacppWebGPU: number;
    onnxSherpa: number;
  }>;
}

const gibibyte = 1024 ** 3;
const memoryBudget: RuntimeMemoryBudget = Object.freeze({
  wasm32AddressSpaceBytes: 4 * gibibyte,
  perModuleSoftLimitBytes: Object.freeze({
    core: 512 * 1024 ** 2,
    llamacppCpu: 3 * gibibyte,
    llamacppWebGPU: 3 * gibibyte,
    onnxSherpa: 1536 * 1024 ** 2,
  }),
});

/**
 * Function installed by a backend (typically the llamacpp bridge) to perform
 * the acceleration switch. Should be idempotent and must report the mode it
 * actually loaded through `setActiveAccelerationMode(...)` before resolving.
 */
export type RuntimeAccelerationSwitcher = (mode: 'cpu' | 'webgpu') => Promise<void>;
export interface RuntimeModelLoadRequest {
  modelId: string;
  category?: ModelCategory;
  framework?: InferenceFramework;
}
export interface RuntimeModelLoadContext {
  request: RuntimeModelLoadRequest;
  model: ModelInfo | null;
}
export interface RuntimeModelLoadFailureContext extends RuntimeModelLoadContext {
  error: unknown;
}
export type RuntimeModelLoadPreparation = (
  context: RuntimeModelLoadContext,
) => Promise<void>;
export type RuntimeModelLoadFailureRecovery = (
  context: RuntimeModelLoadFailureContext,
) => Promise<boolean>;

let _preferred: RuntimeAccelerationMode = 'auto';
let _activeMode: 'cpu' | 'webgpu' | null = null;
let _streamingMode: StreamingMode = 'auto';
let _switcher: RuntimeAccelerationSwitcher | null = null;
let _modelLoadPreparation: RuntimeModelLoadPreparation | null = null;
let _modelLoadFailureRecovery: RuntimeModelLoadFailureRecovery | null = null;
let _degradedReason: string | null = null;
/** Speech (ONNX/Sherpa) acceleration — independent of LLM `active`. */
let _speechAcceleration: 'cpu' | 'webgpu' | null = null;
let _speechThreads = 1;
let _speechExecutionContext: 'main' | 'worker' = 'main';

export interface SpeechRuntimeDiagnostics {
  acceleration: 'cpu' | 'webgpu' | null;
  threads: number;
  executionContext: 'main' | 'worker';
}

/** Per-modality execution status for UI / diagnostics. */
export type ModalityRuntimeStatus =
  | 'worker'
  | 'main'
  | 'composed'
  | 'unavailable';

export interface ModalityRuntimeEntry {
  /** Short product name. */
  label: string;
  /** Owning backend package id, or null when no engine ships. */
  backend: 'llamacpp' | 'onnx' | null;
  status: ModalityRuntimeStatus;
  acceleration: 'cpu' | 'webgpu' | null;
  note?: string;
}

export type ModalityRuntimeId =
  | 'llm'
  | 'vlm'
  | 'lora'
  | 'tools'
  | 'structured'
  | 'embeddings'
  | 'stt'
  | 'tts'
  | 'vad'
  | 'rag'
  | 'voiceAgent'
  | 'rerank'
  | 'segmentation'
  | 'diarization'
  | 'diffusion';

/**
 * Public `RunAnywhere.runtime` capability object.
 */
export const Runtime = {
  /**
   * Preferred acceleration mode. Apps set this once during init; the actual
   * switch happens on the next `setAcceleration(mode)` call or backend load.
   */
  get preferred(): RuntimeAccelerationMode {
    return _preferred;
  },

  set preferred(mode: RuntimeAccelerationMode) {
    _preferred = mode;
  },

  /**
   * Currently-active acceleration mode (null until a backend is loaded).
   */
  get active(): 'cpu' | 'webgpu' | null {
    return _activeMode;
  },

  /**
   * Switch the active acceleration mode. Requires a backend (the llamacpp
   * package) to have registered a switcher via `setAccelerationSwitcher`.
   * If no switcher is installed, this becomes a no-op.
   *
   * @param mode 'cpu' | 'webgpu' (no-op if same as active)
   */
  async setAcceleration(mode: 'cpu' | 'webgpu'): Promise<void> {
    _preferred = mode;
    if (_switcher == null) {
      logger.debug(`runtime.setAcceleration(${mode}): no switcher registered yet — recorded preference only`);
      return;
    }
    await _switcher(mode);
    // The requested mode is only a preference. A backend may resolve WebGPU
    // to CPU after capability detection or fallback, and the switcher reports
    // that actual result via setActiveAccelerationMode(). Never overwrite it
    // with the request after the switch completes.
  },

  /**
   * Preferred streaming delivery mode (T6.1).
   *
   * Adapters consult this on every `*Stream` invocation; switching it
   * between calls is supported. Default `'auto'` resolves to the Worker
   * path when a backend has registered a `streamWorkerFactory`, else
   * the existing main-thread `queueMicrotask` path.
   */
  get streamingMode(): StreamingMode {
    return _streamingMode;
  },

  set streamingMode(mode: StreamingMode) {
    _streamingMode = mode;
  },

  /**
   * Actual execution context of the active BackendWorkerHost. Until a backend
   * wires a worker factory and successfully completes its handshake, this
   * remains `'main'` and existing inference continues on the main thread.
   */
  get executionContext(): 'main' | 'worker' {
    return getBackendWorkerRuntimeDiagnostics().executionContext;
  },

  /** Number of outstanding RPC calls on the active backend worker. */
  get workerQueueDepth(): number {
    return getBackendWorkerRuntimeDiagnostics().queueDepth;
  },

  /**
   * When the preferred BackendWorker path could not be established, explains
   * why inference remains on the main thread (missing Worker, COI, handshake).
   */
  get degradedReason(): string | null {
    return _degradedReason;
  },

  /**
   * Speech (ONNX/Sherpa) acceleration diagnostics. Independent of LLM
   * `active` / `setAcceleration` — do not use those for STT/TTS/VAD.
   */
  get speech(): SpeechRuntimeDiagnostics {
    return {
      acceleration: _speechAcceleration,
      threads: _speechThreads,
      executionContext: _speechExecutionContext,
    };
  },

  /**
   * Snapshot of every public modality: worker vs main vs composed vs
   * unavailable (no browser engine yet). Prefer this over assuming the LLM
   * badge applies to speech/embeddings/diffusion.
   */
  get modalities(): Readonly<Record<ModalityRuntimeId, ModalityRuntimeEntry>> {
    return buildModalityRuntimeSnapshot();
  },

  /**
   * Advisory WASM32 memory limits for diagnostics and preflight UI. These
   * numbers do not allocate memory or override browser/device quota checks.
   */
  get memoryBudget(): RuntimeMemoryBudget {
    return memoryBudget;
  },
};

function buildModalityRuntimeSnapshot(): Record<ModalityRuntimeId, ModalityRuntimeEntry> {
  const llamaCtx = getBackendWorkerHost('llamacpp')?.diagnostics.executionContext ?? 'main';
  const onnxCtx = getBackendWorkerHost('onnx')?.diagnostics.executionContext ?? 'main';
  const llmAccel = _activeMode;
  const speechAccel = _speechAcceleration;
  const llamaWorker = llamaCtx === 'worker';
  const onnxWorker = onnxCtx === 'worker' || _speechExecutionContext === 'worker';

  return {
    llm: {
      label: 'LLM',
      backend: 'llamacpp',
      status: llamaWorker ? 'worker' : 'main',
      acceleration: llmAccel,
    },
    vlm: {
      label: 'VLM',
      backend: 'llamacpp',
      status: llamaWorker ? 'worker' : 'main',
      acceleration: llmAccel,
    },
    lora: {
      label: 'LoRA',
      backend: 'llamacpp',
      status: llamaWorker ? 'worker' : 'main',
      acceleration: llmAccel,
      note: 'Shares LLM BackendWorker',
    },
    tools: {
      label: 'Tool calling',
      backend: 'llamacpp',
      status: llamaWorker ? 'worker' : 'main',
      acceleration: llmAccel,
    },
    structured: {
      label: 'Structured output',
      backend: 'llamacpp',
      status: llamaWorker ? 'worker' : 'main',
      acceleration: llmAccel,
      note: 'Use parseAsync under BackendWorker',
    },
    embeddings: {
      label: 'Embeddings',
      backend: null,
      status: llamaWorker || onnxWorker ? 'worker' : 'main',
      acceleration: onnxWorker ? speechAccel : llmAccel,
      note: 'GGUF → llamacpp worker; ONNX → onnx worker',
    },
    stt: {
      label: 'STT',
      backend: 'onnx',
      status: onnxWorker ? 'worker' : 'main',
      acceleration: speechAccel,
    },
    tts: {
      label: 'TTS',
      backend: 'onnx',
      status: onnxWorker ? 'worker' : 'main',
      acceleration: speechAccel,
    },
    vad: {
      label: 'VAD',
      backend: 'onnx',
      status: onnxWorker ? 'worker' : 'main',
      acceleration: speechAccel,
      note: 'Stream uses per-chunk vad.process on the worker',
    },
    rag: {
      label: 'RAG',
      backend: 'onnx',
      status: onnxWorker || llamaWorker ? 'composed' : 'main',
      acceleration: speechAccel,
      note: 'Embeddings/index on onnx; answers on llama when composed',
    },
    voiceAgent: {
      label: 'Voice agent',
      backend: null,
      status: onnxWorker && llamaWorker ? 'composed' : 'main',
      acceleration: null,
      note: 'CrossWasm STT + LLM + TTS',
    },
    rerank: {
      label: 'Rerank',
      backend: 'llamacpp',
      status: 'main',
      acceleration: llmAccel,
      note: 'Handle-scoped ABI on main llama bridge (not BackendWorker RPC yet)',
    },
    segmentation: {
      label: 'Segmentation',
      backend: null,
      status: 'unavailable',
      acceleration: null,
      note: 'No browser WASM engine shipped',
    },
    diarization: {
      label: 'Diarization',
      backend: null,
      status: 'unavailable',
      acceleration: null,
      note: 'No browser WASM engine shipped',
    },
    diffusion: {
      label: 'Diffusion',
      backend: null,
      status: 'unavailable',
      acceleration: null,
      note: 'API stub only — no @runanywhere/web-diffusion artifact',
    },
  };
}

/**
 * Backend hook: install the acceleration switcher.
 * Called by `LlamaCPP.register()` after the bridge is wired.
 */
export function setAccelerationSwitcher(fn: RuntimeAccelerationSwitcher | null): void {
  _switcher = fn;
}

/** Backend hook: record why the preferred worker inference path is unavailable. */
export function setRuntimeDegradedReason(reason: string | null): void {
  _degradedReason = reason;
}

/**
 * Backend hook: report the mode the bridge actually loaded with so
 * `Runtime.active` reflects reality.
 */
export function setActiveAccelerationMode(mode: 'cpu' | 'webgpu' | null): void {
  if (_activeMode === mode) return;
  _activeMode = mode;
  if (mode !== null) {
    EventBus.shared.publish(
      'sdk.accelerationMode',
      EventCategory.EVENT_CATEGORY_HARDWARE,
      { mode },
    );
  }
}

/**
 * Backend hook: report ONNX/Sherpa speech compute mode for UI and diagnostics.
 * Does not mutate LLM `Runtime.active`.
 */
export function setSpeechAccelerationMode(diagnostics: {
  acceleration: 'cpu' | 'webgpu' | null;
  threads?: number;
  executionContext?: 'main' | 'worker';
}): void {
  const nextAccel = diagnostics.acceleration;
  const nextThreads = diagnostics.threads ?? _speechThreads;
  const nextCtx = diagnostics.executionContext ?? _speechExecutionContext;
  const changed =
    _speechAcceleration !== nextAccel
    || _speechThreads !== nextThreads
    || _speechExecutionContext !== nextCtx;
  _speechAcceleration = nextAccel;
  _speechThreads = nextThreads;
  _speechExecutionContext = nextCtx;
  if (!changed || nextAccel === null) return;
  EventBus.shared.publish(
    'sdk.speechAcceleration',
    EventCategory.EVENT_CATEGORY_HARDWARE,
    {
      acceleration: nextAccel,
      threads: nextThreads,
      executionContext: nextCtx,
    },
  );
}

export function setModelLoadPreparation(fn: RuntimeModelLoadPreparation | null): void {
  _modelLoadPreparation = fn;
}

export async function prepareModelLoad(context: RuntimeModelLoadContext): Promise<void> {
  if (!_modelLoadPreparation) return;
  try {
    await _modelLoadPreparation(context);
  } catch (error) {
    logger.warning(
      `model-load preparation failed: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

export function setModelLoadFailureRecovery(fn: RuntimeModelLoadFailureRecovery | null): void {
  _modelLoadFailureRecovery = fn;
}

export async function recoverModelLoadFailure(
  context: RuntimeModelLoadFailureContext,
): Promise<boolean> {
  if (!_modelLoadFailureRecovery) return false;
  try {
    return await _modelLoadFailureRecovery(context);
  } catch (error) {
    logger.warning(
      `model-load recovery failed: ${error instanceof Error ? error.message : String(error)}`,
    );
    return false;
  }
}
