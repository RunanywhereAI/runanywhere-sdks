/**
 * NativeRunAnywhereLlama.ts
 *
 * Exports the native RunAnywhereLlama Hybrid Object from Nitro Modules.
 * This module provides Llama-based text generation capabilities.
 */

import { NitroModules } from 'react-native-nitro-modules';
import type { RunAnywhereLlama } from '../specs/RunAnywhereLlama.nitro';

/**
 * The native RunAnywhereLlama module type
 */
export type NativeRunAnywhereLlamaModule = RunAnywhereLlama;

/**
 * Get the native RunAnywhereLlama Hybrid Object
 */
export function requireNativeLlamaModule(): NativeRunAnywhereLlamaModule {
  return NitroModules.createHybridObject<RunAnywhereLlama>('RunAnywhereLlama');
}

/**
 * Check if the native Llama module is available
 */
export function isNativeLlamaModuleAvailable(): boolean {
  try {
    requireNativeLlamaModule();
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
