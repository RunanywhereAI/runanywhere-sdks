import { SDKLogger } from './SDKLogger';

const logger = new SDKLogger('Runtime');

export type RuntimeAccelerationMode = 'cpu' | 'webgpu' | 'auto';

export type RuntimeAccelerationSwitcher = (mode: 'cpu' | 'webgpu') => Promise<void>;
export type RuntimeModelLoadPreparation = (context: { request: unknown; model: unknown | null }) => Promise<void>;
export type RuntimeModelLoadFailureRecovery = (context: { request: unknown; error: unknown }) => Promise<boolean>;

let _preferred: RuntimeAccelerationMode = 'auto';
let _activeMode: 'cpu' | 'webgpu' | null = null;
let _switcher: RuntimeAccelerationSwitcher | null = null;
let _modelLoadPreparation: RuntimeModelLoadPreparation | null = null;
let _modelLoadFailureRecovery: RuntimeModelLoadFailureRecovery | null = null;

export const Runtime = {
  get preferred(): RuntimeAccelerationMode {
    return _preferred;
  },
  set preferred(mode: RuntimeAccelerationMode) {
    _preferred = mode;
  },

  get active(): 'cpu' | 'webgpu' | null {
    return _activeMode;
  },

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

export function setAccelerationSwitcher(fn: RuntimeAccelerationSwitcher | null): void {
  _switcher = fn;
}

export function setActiveAccelerationMode(mode: 'cpu' | 'webgpu' | null): void {
  _activeMode = mode;
}

export function setModelLoadPreparation(fn: RuntimeModelLoadPreparation | null): void {
  _modelLoadPreparation = fn;
}

export async function prepareModelLoad(context: { request: unknown; model: unknown | null }): Promise<void> {
  if (!_modelLoadPreparation) return;
  try {
    await _modelLoadPreparation(context);
  } catch (error) {
    logger.warning(`model-load preparation failed: ${error instanceof Error ? error.message : String(error)}`);
  }
}

export function setModelLoadFailureRecovery(fn: RuntimeModelLoadFailureRecovery | null): void {
  _modelLoadFailureRecovery = fn;
}

export async function recoverModelLoadFailure(context: { request: unknown; error: unknown }): Promise<boolean> {
  if (!_modelLoadFailureRecovery) return false;
  try {
    return await _modelLoadFailureRecovery(context);
  } catch (error) {
    logger.warning(`model-load recovery failed: ${error instanceof Error ? error.message : String(error)}`);
    return false;
  }
}
