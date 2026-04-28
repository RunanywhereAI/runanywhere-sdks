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

import { SDKLogger } from './SDKLogger';

const logger = new SDKLogger('Runtime');

/** Acceleration mode — superset of the Web-only `'webgpu'` and the `'auto'` preference. */
export type RuntimeAccelerationMode = 'cpu' | 'webgpu' | 'auto';

/**
 * Function installed by a backend (typically the llamacpp bridge) to perform
 * the acceleration switch. Should be idempotent.
 */
export type RuntimeAccelerationSwitcher = (mode: 'cpu' | 'webgpu') => Promise<void>;

let _preferred: RuntimeAccelerationMode = 'auto';
let _activeMode: 'cpu' | 'webgpu' | null = null;
let _switcher: RuntimeAccelerationSwitcher | null = null;

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
  _activeMode = mode;
}
