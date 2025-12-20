/**
 * NitroModules.ts
 *
 * TypeScript wrappers for Nitrogen HybridObjects.
 * This provides type-safe access to native modules.
 */

import { NitroModules } from 'react-native-nitro-modules';
import type { RunAnywhere } from '../specs/RunAnywhere.nitro';
import type { RunAnywhereFileSystem } from '../specs/RunAnywhereFileSystem.nitro';
import type { RunAnywhereDeviceInfo } from '../specs/RunAnywhereDeviceInfo.nitro';

// ============================================================================
// Lazy-loaded Nitrogen HybridObjects
// ============================================================================

let _runAnywhere: RunAnywhere | null = null;
let _fileSystem: RunAnywhereFileSystem | null = null;
let _deviceInfo: RunAnywhereDeviceInfo | null = null;

/**
 * Get the main RunAnywhere native module
 */
export function getRunAnywhere(): RunAnywhere {
  if (!_runAnywhere) {
    _runAnywhere = NitroModules.createHybridObject<RunAnywhere>('RunAnywhere');
  }
  return _runAnywhere;
}

/**
 * Get the FileSystem utility module
 */
export function getFileSystem(): RunAnywhereFileSystem {
  if (!_fileSystem) {
    _fileSystem = NitroModules.createHybridObject<RunAnywhereFileSystem>(
      'RunAnywhereFileSystem'
    );
  }
  return _fileSystem;
}

/**
 * Get the DeviceInfo utility module
 */
export function getDeviceInfo(): RunAnywhereDeviceInfo {
  if (!_deviceInfo) {
    _deviceInfo = NitroModules.createHybridObject<RunAnywhereDeviceInfo>(
      'RunAnywhereDeviceInfo'
    );
  }
  return _deviceInfo;
}

/**
 * Check if Nitrogen modules are available
 */
export function isNitroAvailable(): boolean {
  try {
    const ra = getRunAnywhere();
    return ra !== null;
  } catch {
    return false;
  }
}

// ============================================================================
// Exports
// ============================================================================

export type { RunAnywhere, RunAnywhereFileSystem, RunAnywhereDeviceInfo };
