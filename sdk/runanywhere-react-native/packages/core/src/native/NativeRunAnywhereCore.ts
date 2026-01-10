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
import type { RunAnywhereDeviceInfo } from '../specs/RunAnywhereDeviceInfo.nitro';
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
 * Singleton for device info hybrid object
 */
let _deviceInfoModule: RunAnywhereDeviceInfo | null = null;

/**
 * Get the RunAnywhereDeviceInfo hybrid object
 * This provides real device info from native iOS/Android code
 */
function getDeviceInfoHybridObject(): RunAnywhereDeviceInfo | null {
  if (_deviceInfoModule) {
    return _deviceInfoModule;
  }
  try {
    _deviceInfoModule = NitroModules.createHybridObject<RunAnywhereDeviceInfo>('RunAnywhereDeviceInfo');
    return _deviceInfoModule;
  } catch (error) {
    console.warn('[NativeRunAnywhereCore] Failed to create RunAnywhereDeviceInfo:', error);
    return null;
  }
}

/**
 * Device info module - provides device information
 *
 * Uses the RunAnywhereDeviceInfo NitroModule for real device info
 * from native iOS (Swift) and Android (Kotlin) implementations.
 */
export function requireDeviceInfoModule(): DeviceInfoModule {
  const deviceInfo = getDeviceInfoHybridObject();

  return {
    deviceId: '',
    getDeviceIdSync: () => '',
    uniqueId: '',

    getDeviceModel: async () => {
      if (deviceInfo) {
        try {
          return await deviceInfo.getDeviceModel();
        } catch (error) {
          console.warn('[DeviceInfo] getDeviceModel failed:', error);
        }
      }
      return 'Unknown Device';
    },

    getChipName: async () => {
      if (deviceInfo) {
        try {
          return await deviceInfo.getChipName();
        } catch (error) {
          console.warn('[DeviceInfo] getChipName failed:', error);
        }
      }
      return 'Unknown';
    },

    getTotalRAM: async () => {
      if (deviceInfo) {
        try {
          return await deviceInfo.getTotalRAM();
        } catch (error) {
          console.warn('[DeviceInfo] getTotalRAM failed:', error);
        }
      }
      return 0;
    },

    getAvailableRAM: async () => {
      if (deviceInfo) {
        try {
          return await deviceInfo.getAvailableRAM();
        } catch (error) {
          console.warn('[DeviceInfo] getAvailableRAM failed:', error);
        }
      }
      return 0;
    },

    hasNPU: async () => {
      if (deviceInfo) {
        try {
          return await deviceInfo.hasNPU();
        } catch (error) {
          console.warn('[DeviceInfo] hasNPU failed:', error);
        }
      }
      return false;
    },

    getOSVersion: async () => {
      if (deviceInfo) {
        try {
          return await deviceInfo.getOSVersion();
        } catch (error) {
          console.warn('[DeviceInfo] getOSVersion failed:', error);
        }
      }
      return 'Unknown';
    },

    hasGPU: async () => {
      if (deviceInfo) {
        try {
          return await deviceInfo.hasGPU();
        } catch (error) {
          console.warn('[DeviceInfo] hasGPU failed:', error);
        }
      }
      return false;
    },

    getCPUCores: async () => {
      if (deviceInfo) {
        try {
          return await deviceInfo.getCPUCores();
        } catch (error) {
          console.warn('[DeviceInfo] getCPUCores failed:', error);
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
        console.error('[RunAnywhere] Download failed:', error);
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
