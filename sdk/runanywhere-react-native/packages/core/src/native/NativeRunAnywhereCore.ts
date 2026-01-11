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
import { SDKLogger } from '../Foundation/Logging';

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
 * Device info module interface
 */
export interface DeviceInfoModule {
  deviceId: string;
  getDeviceIdSync: () => string;
  uniqueId: string;
  getDeviceModel: () => Promise<string>;
  getChipName: () => Promise<string>;
  getTotalRAM: () => Promise<number>;
  getAvailableRAM: () => Promise<number>;
  hasNPU: () => Promise<boolean>;
  getOSVersion: () => Promise<string>;
  hasGPU: () => Promise<boolean>;
  getCPUCores: () => Promise<number>;
}

/**
 * Device info module - provides device information
 *
 * Note: Full device info requires platform-specific APIs.
 * This provides basic info from native.getDeviceCapabilities() and
 * platform defaults for values not yet implemented in C++.
 */
export function requireDeviceInfoModule(): DeviceInfoModule {
  const native = isNativeCoreModuleAvailable() ? getNativeCoreModule() : null;

  return {
    deviceId: '',
    getDeviceIdSync: () => '',
    uniqueId: '',

    getDeviceModel: async () => {
      // Try to get from native capabilities
      if (native) {
        try {
          const capsJson = await native.getDeviceCapabilities();
          const caps = JSON.parse(capsJson);
          return caps.device_model || caps.platform || 'Unknown Device';
        } catch {
          // Fallback
        }
      }
      return 'Unknown Device';
    },

    getChipName: async () => {
      if (native) {
        try {
          const capsJson = await native.getDeviceCapabilities();
          const caps = JSON.parse(capsJson);
          return caps.chip_name || caps.processor || 'Unknown';
        } catch {
          // Fallback
        }
      }
      return 'Unknown';
    },

    getTotalRAM: async () => {
      if (native) {
        try {
          const capsJson = await native.getDeviceCapabilities();
          const caps = JSON.parse(capsJson);
          return caps.total_memory || 0;
        } catch {
          // Fallback
        }
      }
      return 0;
    },

    getAvailableRAM: async () => {
      if (native) {
        try {
          const capsJson = await native.getDeviceCapabilities();
          const caps = JSON.parse(capsJson);
          return caps.available_memory || 0;
        } catch {
          // Fallback
        }
      }
      return 0;
    },

    hasNPU: async () => {
      if (native) {
        try {
          const capsJson = await native.getDeviceCapabilities();
          const caps = JSON.parse(capsJson);
          return caps.has_npu || caps.supports_metal || false;
        } catch {
          // Fallback
        }
      }
      return false;
    },

    getOSVersion: async () => {
      if (native) {
        try {
          const capsJson = await native.getDeviceCapabilities();
          const caps = JSON.parse(capsJson);
          return caps.os_version || caps.platform || 'Unknown';
        } catch {
          // Fallback
        }
      }
      return 'Unknown';
    },

    hasGPU: async () => {
      if (native) {
        try {
          const capsJson = await native.getDeviceCapabilities();
          const caps = JSON.parse(capsJson);
          return caps.has_gpu || caps.supports_vulkan || caps.supports_metal || false;
        } catch {
          // Fallback
        }
      }
      return false;
    },

    getCPUCores: async () => {
      if (native) {
        try {
          const capsJson = await native.getDeviceCapabilities();
          const caps = JSON.parse(capsJson);
          return caps.cpu_cores || caps.core_count || 0;
        } catch {
          // Fallback
        }
      }
      return 0;
    },
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
  getDataDirectory(): Promise<string>;
  getModelsDirectory(): Promise<string>;
}

/**
 * Get the file system module for model downloads and file operations
 * Uses react-native-fs for cross-platform file operations
 */
export function requireFileSystemModule(): FileSystemModule {
  // Import the FileSystem service
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { FileSystem } = require('../services/FileSystem');

  return {
    getAvailableDiskSpace: () => FileSystem.getAvailableDiskSpace(),
    getTotalDiskSpace: () => FileSystem.getTotalDiskSpace(),
    downloadModel: async (
      fileName: string,
      url: string,
      onProgress?: (progress: number) => void
    ): Promise<boolean> => {
      try {
        await FileSystem.downloadModel(fileName, url, (progress: { progress: number }) => {
          if (onProgress) {
            onProgress(progress.progress);
          }
        });
        return true;
      } catch (error) {
        SDKLogger.download.logError(error as Error, 'Download failed');
        return false;
      }
    },
    getModelPath: (fileName: string) => FileSystem.getModelPath(fileName),
    modelExists: (fileName: string) => FileSystem.modelExists(fileName),
    deleteModel: (fileName: string) => FileSystem.deleteModel(fileName),
    getDataDirectory: () => Promise.resolve(FileSystem.getRunAnywhereDirectory()),
    getModelsDirectory: () => Promise.resolve(FileSystem.getModelsDirectory()),
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
