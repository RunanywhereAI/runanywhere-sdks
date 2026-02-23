/**
 * NativeRunAnywhereLlama.ts
 *
 * Exports the native RunAnywhereLlama Hybrid Object from Nitro Modules.
 * This module provides Llama-based text generation capabilities.
 */

import type { RunAnywhereLlama } from '../specs/RunAnywhereLlama.nitro';
import { getNitroModulesProxySync } from '@runanywhere/core';

// Use the global NitroModules initialization
function getNitroModulesProxy(): any {
  return getNitroModulesProxySync();
}

/**
 * The native RunAnywhereLlama module type
 */
export type NativeRunAnywhereLlamaModule = RunAnywhereLlama;

/**
 * Get the native RunAnywhereLlama Hybrid Object
 */
export function requireNativeLlamaModule(): NativeRunAnywhereLlamaModule {
  const NitroProxy = getNitroModulesProxy();
  if (!NitroProxy) {
    throw new Error(
      'NitroModules is not available. This can happen in Bridgeless mode if ' +
      'react-native-nitro-modules is not properly linked.'
    );
  }
  return NitroProxy.createHybridObject<RunAnywhereLlama>('RunAnywhereLlama');
}

/**
 * Check if the native Llama module is available.
 * Uses the singleton getter to avoid creating throwaway HybridObject instances
 * whose C++ destructors could tear down shared bridge state.
 */
export function isNativeLlamaModuleAvailable(): boolean {
  try {
    getNativeLlamaModule();
    return true;
  } catch {
    return false;
  }
}

/**
 * Singleton instance of the native module (lazy initialized)
 */
let _nativeModule: NativeRunAnywhereLlamaModule | undefined;

/**
 * Get the singleton native module instance
 */
export function getNativeLlamaModule(): NativeRunAnywhereLlamaModule {
  if (!_nativeModule) {
    _nativeModule = requireNativeLlamaModule();
  }
  return _nativeModule;
}

/**
 * Default export - the native module getter
 */
export const NativeRunAnywhereLlama = {
  get: getNativeLlamaModule,
  isAvailable: isNativeLlamaModuleAvailable,
};

export default NativeRunAnywhereLlama;
