/**
 * NativeRunAnywhereQHexRT.ts
 *
 * Exports the native RunAnywhereQHexRT Hybrid Object from Nitro Modules.
 * This module provides QHexRT backend registration hooks and the NPU probe.
 */

import type { RunAnywhereQHexRT } from '../specs/RunAnywhereQHexRT.nitro';
import { getNitroModulesProxySync, type NitroProxy } from '@runanywhere/core/internal';

// Use the global NitroModules initialization
function getNitroModulesProxy(): NitroProxy | null {
  return getNitroModulesProxySync();
}

/**
 * The native RunAnywhereQHexRT module type
 */
export type NativeRunAnywhereQHexRTModule = RunAnywhereQHexRT;

/**
 * Get the native RunAnywhereQHexRT Hybrid Object
 */
export function requireNativeQHexRTModule(): NativeRunAnywhereQHexRTModule {
  const NitroProxy = getNitroModulesProxy();
  if (!NitroProxy) {
    throw new Error(
      'NitroModules is not available. This can happen in Bridgeless mode if ' +
      'react-native-nitro-modules is not properly linked.'
    );
  }
  return NitroProxy.createHybridObject('RunAnywhereQHexRT') as RunAnywhereQHexRT;
}

/**
 * Check if the native QHexRT module is available.
 * Uses the singleton getter to avoid creating throwaway HybridObject instances
 * whose C++ destructors could tear down shared bridge state.
 */
export function isNativeQHexRTModuleAvailable(): boolean {
  try {
    getNativeQHexRTModule();
    return true;
  } catch {
    return false;
  }
}

/**
 * Singleton instance of the native module (lazy initialized)
 */
let _nativeModule: NativeRunAnywhereQHexRTModule | undefined;

/**
 * Get the singleton native module instance
 */
export function getNativeQHexRTModule(): NativeRunAnywhereQHexRTModule {
  if (!_nativeModule) {
    _nativeModule = requireNativeQHexRTModule();
  }
  return _nativeModule;
}

/**
 * Default export - the native module getter
 */
export const NativeRunAnywhereQHexRT = {
  get: getNativeQHexRTModule,
  isAvailable: isNativeQHexRTModuleAvailable,
};

export default NativeRunAnywhereQHexRT;
