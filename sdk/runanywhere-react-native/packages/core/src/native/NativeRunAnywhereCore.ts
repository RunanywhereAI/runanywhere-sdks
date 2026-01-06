/**
 * NativeRunAnywhereCore.ts
 *
 * Exports the native RunAnywhereCore Hybrid Object from Nitro Modules.
 * This module provides core SDK functionality without any inference backends.
 *
 * For LLM, STT, TTS, VAD capabilities, use the separate packages:
 * - @runanywhere/llamacpp for text generation
 * - @runanywhere/onnx for speech processing
 */

import { NitroModules } from 'react-native-nitro-modules';
import type { RunAnywhereCore } from '../specs/RunAnywhereCore.nitro';
import type { NativeRunAnywhereModule } from './NativeRunAnywhereModule';

export type { NativeRunAnywhereModule } from './NativeRunAnywhereModule';
export { hasNativeMethod } from './NativeRunAnywhereModule';

/**
 * The native RunAnywhereCore module type
 */
export type NativeRunAnywhereCoreModule = RunAnywhereCore;

/**
 * Get the native RunAnywhereCore Hybrid Object
 *
 * This provides direct access to the native module.
 * Most users should use the RunAnywhere facade class instead.
 */
export function requireNativeCoreModule(): NativeRunAnywhereCoreModule {
  return NitroModules.createHybridObject<RunAnywhereCore>('RunAnywhereCore');
}

/**
 * Check if the native core module is available
 */
export function isNativeCoreModuleAvailable(): boolean {
  try {
    requireNativeCoreModule();
    return true;
  } catch {
    return false;
  }
}

/**
 * Singleton instance of the native module (lazy initialized)
 */
let _nativeModule: NativeRunAnywhereModule | undefined;

/**
 * Get the singleton native module instance
 * Returns the full module type for backwards compatibility
 */
export function getNativeCoreModule(): NativeRunAnywhereModule {
  if (!_nativeModule) {
    // Cast to full module type - optional methods may not be available
    _nativeModule = requireNativeCoreModule() as unknown as NativeRunAnywhereModule;
  }
  return _nativeModule;
}

// =============================================================================
// Backwards compatibility exports
// These match the old @runanywhere/native exports
// =============================================================================

/**
 * Get the native module with full API type
 * Some methods may not be available unless backend packages are installed
 */
export function requireNativeModule(): NativeRunAnywhereModule {
  return getNativeCoreModule();
}

/**
 * Check if native module is available
 */
export function isNativeModuleAvailable(): boolean {
  return isNativeCoreModuleAvailable();
}

/**
 * Device info module stub - returns empty device info
 * @deprecated Device info is now available via native.getDeviceCapabilities()
 */
export function requireDeviceInfoModule(): Record<string, unknown> {
  return {
    deviceId: '',
    getDeviceIdSync: () => '',
    uniqueId: '',
  };
}

/**
 * File system module interface
 */
export interface FileSystemModule {
  getAvailableDiskSpace(): Promise<number>;
  getTotalDiskSpace(): Promise<number>;
  downloadModel(
    fileName: string,
    url: string,
    onProgress?: (progress: number) => void
  ): Promise<boolean>;
  getModelPath(fileName: string): Promise<string>;
  modelExists(fileName: string): Promise<boolean>;
  deleteModel(fileName: string): Promise<boolean>;
}

/**
 * File system module stub
 * @deprecated File operations should use native.extractArchive() or platform APIs
 */
export function requireFileSystemModule(): FileSystemModule {
  return {
    // Stub implementations that will be called by extensions
    getAvailableDiskSpace: async () => 0,
    getTotalDiskSpace: async () => 0,
    downloadModel: async () => false,
    getModelPath: async () => '',
    modelExists: async () => false,
    deleteModel: async () => false,
  };
}

/**
 * Default export - the native module getter
 */
export const NativeRunAnywhereCore = {
  get: getNativeCoreModule,
  isAvailable: isNativeCoreModuleAvailable,
};

export default NativeRunAnywhereCore;
