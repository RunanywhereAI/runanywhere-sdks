/**
 * NativeRunAnywhereONNX.ts
 *
 * Exports the native RunAnywhereONNX Hybrid Object from Nitro Modules.
 * This module provides ONNX backend registration hooks.
 */

import type { RunAnywhereONNX } from '../specs/RunAnywhereONNX.nitro';
import { getNitroModulesProxySync, type NitroProxy } from '@runanywhere/core/internal';

// Use the global NitroModules initialization
function getNitroModulesProxy(): NitroProxy | null {
  return getNitroModulesProxySync();
}

/**
 * The native RunAnywhereONNX module type
 */
export type NativeRunAnywhereONNXModule = RunAnywhereONNX;

/**
 * Get the native RunAnywhereONNX Hybrid Object
 */
export function requireNativeONNXModule(): NativeRunAnywhereONNXModule {
  const NitroProxy = getNitroModulesProxy();
  if (!NitroProxy) {
    throw new Error(
      'NitroModules is not available. This can happen in Bridgeless mode if ' +
      'react-native-nitro-modules is not properly linked.'
    );
  }
  return NitroProxy.createHybridObject('RunAnywhereONNX') as RunAnywhereONNX;
}

/**
 * Check if the native ONNX module is available.
 * Uses the singleton getter to avoid creating throwaway HybridObject instances
 * whose C++ destructors could tear down shared bridge state.
 */
export function isNativeONNXModuleAvailable(): boolean {
  try {
    getNativeONNXModule();
    return true;
  } catch {
    return false;
  }
}

/**
 * Singleton instance of the native module (lazy initialized)
 */
let _nativeModule: NativeRunAnywhereONNXModule | undefined;

/**
 * Get the singleton native module instance
 */
export function getNativeONNXModule(): NativeRunAnywhereONNXModule {
  if (!_nativeModule) {
    _nativeModule = requireNativeONNXModule();
  }
  return _nativeModule;
}

/**
 * Default export - the native module getter
 */
export const NativeRunAnywhereONNX = {
  get: getNativeONNXModule,
  isAvailable: isNativeONNXModuleAvailable,
};

export default NativeRunAnywhereONNX;
