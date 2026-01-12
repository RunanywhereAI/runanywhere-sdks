/**
 * NativeRunAnywhereONNX.ts
 *
 * Exports the native RunAnywhereONNX Hybrid Object from Nitro Modules.
 * This module provides ONNX-based STT, TTS, and VAD capabilities.
 */

import { NitroModules } from 'react-native-nitro-modules';
import type { RunAnywhereONNX } from '../specs/RunAnywhereONNX.nitro';

/**
 * The native RunAnywhereONNX module type
 */
export type NativeRunAnywhereONNXModule = RunAnywhereONNX;

/**
 * Get the native RunAnywhereONNX Hybrid Object
 */
export function requireNativeONNXModule(): NativeRunAnywhereONNXModule {
  return NitroModules.createHybridObject<RunAnywhereONNX>('RunAnywhereONNX');
}

/**
 * Check if the native ONNX module is available
 */
export function isNativeONNXModuleAvailable(): boolean {
  try {
    requireNativeONNXModule();
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
