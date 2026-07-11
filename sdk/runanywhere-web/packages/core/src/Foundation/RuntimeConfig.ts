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
 * See `docs/STREAM_DELIVERY_DESIGN.md` for the architectural framing.
 */
export type StreamingMode = 'auto' | 'worker' | 'main';

/**
 * Function installed by a backend (typically the llamacpp bridge) to perform
 * the acceleration switch. Should be idempotent.
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
    _activeMode = mode;
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
};

/**
 * Backend hook: install the acceleration switcher.
 * Called by `LlamaCPP.register()` after the bridge is wired.
 */
export function setAccelerationSwitcher(fn: RuntimeAccelerationSwitcher | null): void {
  _switcher = fn;
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
