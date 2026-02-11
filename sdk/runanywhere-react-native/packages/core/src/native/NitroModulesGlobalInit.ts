/**
 * NitroModulesGlobalInit.ts
 *
 * Global singleton for NitroModules initialization.
 * Ensures NitroModules.install() is called exactly ONCE globally,
 * preventing "global.__nitroDispatcher already exists" errors.
 *
 * All packages should import and use this for safe NitroModules access.
 */

import { NitroModules as NitroModulesNamed } from 'react-native-nitro-modules';
import { NativeModules } from 'react-native';

/** Global promise that tracks NitroModules installation */
let _nitroInstallationPromise: Promise<any> | null = null;

/** Cached NitroModules proxy after successful installation */
let _nitroModulesProxy: any = null;

/**
 * Initialize NitroModules globally, ensuring install() is called exactly once.
 * This MUST be called before any other modules try to access NitroModules.
 *
 * @returns Promise resolving to NitroModules proxy
 */
export async function initializeNitroModulesGlobally(): Promise<any> {
  // If already initialized, return cached proxy
  if (_nitroModulesProxy !== null) {
    return _nitroModulesProxy;
  }

  // If initialization is in progress, return the existing promise
  if (_nitroInstallationPromise !== null) {
    return _nitroInstallationPromise;
  }

  // Create the initialization promise
  _nitroInstallationPromise = (async () => {
    try {
      console.debug('[NitroModulesGlobalInit] Starting global initialization...');

      // Try to get the proxy from the named import first (most reliable in Bridgeless)
      _nitroModulesProxy = NitroModulesNamed;

      if (!_nitroModulesProxy) {
        // Fallback: Try to call install() on the native module if named import failed
        const nativeNitro = NativeModules?.NitroModules;
        if (nativeNitro && typeof nativeNitro.install === 'function') {
          try {
            console.debug('[NitroModulesGlobalInit] Calling native NitroModules.install()...');
            nativeNitro.install();
            console.debug('[NitroModulesGlobalInit] Native install() completed');
            
            // Try getting proxy again after install
            _nitroModulesProxy = NitroModulesNamed;
          } catch (installError) {
            console.warn('[NitroModulesGlobalInit] Native install() failed:', installError);
          }
        }
      }

      if (!_nitroModulesProxy) {
        throw new Error(
          'NitroModules is not available after initialization. ' +
          'Make sure react-native-nitro-modules is properly installed and linked.'
        );
      }

      console.debug('[NitroModulesGlobalInit] Global initialization successful');
      return _nitroModulesProxy;
    } catch (error) {
      console.error('[NitroModulesGlobalInit] Failed to initialize NitroModules:', error);
      _nitroInstallationPromise = null; // Reset on error to allow retry
      throw error;
    }
  })();

  return _nitroInstallationPromise;
}

/**
 * Get the NitroModules proxy synchronously (only after initialization).
 * For guaranteed initialization, use initializeNitroModulesGlobally() first.
 *
 * @returns NitroModules proxy or null if not yet initialized
 */
export function getNitroModulesProxySync(): any {
  return _nitroModulesProxy;
}

/**
 * Check if NitroModules has been initialized
 */
export function isNitroModulesInitialized(): boolean {
  return _nitroModulesProxy !== null;
}
