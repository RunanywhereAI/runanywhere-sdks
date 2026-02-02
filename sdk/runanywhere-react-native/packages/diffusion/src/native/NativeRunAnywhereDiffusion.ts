/**
 * Native Diffusion Module Accessor
 *
 * Provides access to the native RunAnywhereDiffusion HybridObject.
 */

import { NitroModules } from 'react-native-nitro-modules';
import type { RunAnywhereDiffusion } from '../specs/RunAnywhereDiffusion.nitro';

let cachedModule: RunAnywhereDiffusion | null = null;

/**
 * Get the native RunAnywhereDiffusion module
 * @throws Error if the module is not available
 */
export function requireNativeDiffusionModule(): RunAnywhereDiffusion {
  if (cachedModule !== null) {
    return cachedModule;
  }

  try {
    cachedModule =
      NitroModules.createHybridObject<RunAnywhereDiffusion>(
        'RunAnywhereDiffusion'
      );
    return cachedModule;
  } catch (error) {
    throw new Error(
      `[Diffusion] Failed to load native module. ` +
        `Make sure @runanywhere/diffusion is properly linked. ` +
        `Error: ${error}`
    );
  }
}

/**
 * Check if the native Diffusion module is available
 */
export function isNativeDiffusionModuleAvailable(): boolean {
  try {
    requireNativeDiffusionModule();
    return true;
  } catch {
    return false;
  }
}

/**
 * Clear the cached module (useful for testing)
 */
export function clearNativeDiffusionModuleCache(): void {
  cachedModule = null;
}
