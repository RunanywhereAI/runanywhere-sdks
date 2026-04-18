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
import { SDKLogger } from '../Foundation/Logging';

/** Global promise that tracks NitroModules installation */
let _nitroInstallationPromise: Promise<any> | null = null;

/** Cached NitroModules proxy after successful installation */
let _nitroModulesProxy: any = null;

/** Track whether native install() has been invoked */
let _nitroInstallCalled = false;

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
      SDKLogger.core.debug('[NitroModulesGlobalInit] Starting global initialization...');

      // Try to get the proxy from the named import first (most reliable in Bridgeless)
      _nitroModulesProxy = NitroModulesNamed;

      // Always attempt native install() once to ensure JSI bindings are ready
      const nativeNitro = NativeModules?.NitroModules;
      if (!_nitroInstallCalled && nativeNitro && typeof nativeNitro.install === 'function') {
        try {
          SDKLogger.core.debug('[NitroModulesGlobalInit] Calling native NitroModules.install()...');
          nativeNitro.install();
          _nitroInstallCalled = true;
          SDKLogger.core.debug('[NitroModulesGlobalInit] Native install() completed');
        } catch (installError) {
          SDKLogger.core.warning('[NitroModulesGlobalInit] Native install() failed', { error: installError });
        }
      }

      // Try getting proxy again after install (if needed)
      if (!_nitroModulesProxy) {
        _nitroModulesProxy = NitroModulesNamed;
      }

      if (!_nitroModulesProxy) {
        throw new Error(
          'NitroModules is not available after initialization. ' +
          'Make sure react-native-nitro-modules is properly installed and linked.'
        );
      }

      SDKLogger.core.debug('[NitroModulesGlobalInit] Global initialization successful');
      return _nitroModulesProxy;
    } catch (error) {
      SDKLogger.core.error('[NitroModulesGlobalInit] Failed to initialize NitroModules', { error });
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
