/**
 * Bundler-neutral registration point for the production worker RPC path.
 *
 * @internal
 *
 * A backend may register a factory from its `register()` method once it ships
 * a Worker bootstrap. Leaving this unset is intentional: all current
 * modality adapters retain their established main-thread inference path.
 */

import type { BackendWorkerFactory } from './BackendWorkerHost.js';

let factory: BackendWorkerFactory | null = null;

export function setBackendWorkerFactory(value: BackendWorkerFactory | null): void {
  factory = value;
}

export function getBackendWorkerFactory(): BackendWorkerFactory | null {
  return factory;
}

export function hasBackendWorkerFactory(): boolean {
  return factory !== null;
}
