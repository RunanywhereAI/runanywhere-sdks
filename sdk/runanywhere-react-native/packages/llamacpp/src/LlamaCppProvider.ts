/**
 * @runanywhere/llamacpp - LlamaCPP Provider
 *
 * LlamaCPP module registration for React Native SDK.
 * Thin wrapper that triggers C++ backend registration.
 *
 * Reference: sdk/runanywhere-swift/Sources/LlamaCPPRuntime/LlamaCPP.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '@runanywhere/native';

// Simple logger for this package
const DEBUG = typeof __DEV__ !== 'undefined' ? __DEV__ : false;
const log = {
  info: (msg: string) => DEBUG && console.log(`[LlamaCppProvider] ${msg}`),
  debug: (msg: string) => DEBUG && console.log(`[LlamaCppProvider] ${msg}`),
  warning: (msg: string) => console.warn(`[LlamaCppProvider] ${msg}`),
};

/**
 * LlamaCPP Module
 *
 * Provides LLM capabilities using llama.cpp with GGUF models.
 * The actual service is provided by the C++ backend.
 *
 * ## Registration
 *
 * ```typescript
 * import { LlamaCppProvider } from '@runanywhere/llamacpp';
 *
 * // Register the backend
 * await LlamaCppProvider.register();
 * ```
 */
export class LlamaCppProvider {
  static readonly moduleId = 'llamacpp';
  static readonly moduleName = 'LlamaCPP';
  static readonly version = '2.0.0';

  private static isRegistered = false;

  /**
   * Register LlamaCPP backend with the C++ service registry.
   * Calls rac_backend_llamacpp_register() to register the
   * LlamaCPP service provider with the C++ commons layer.
   * Safe to call multiple times - subsequent calls are no-ops.
   * @returns Promise<boolean> true if registered successfully
   */
  static async register(): Promise<boolean> {
    if (this.isRegistered) {
      log.debug('LlamaCPP already registered, returning');
      return true;
    }

    if (!isNativeModuleAvailable()) {
      log.warning('Native module not available');
      return false;
    }

    log.info('Registering LlamaCPP backend with C++ registry...');

    try {
      const native = requireNativeModule();
      // Call native registration function (matches Swift pattern)
      const success = await native.registerLlamaCppBackend();
      if (success) {
        this.isRegistered = true;
        log.info('✅ LlamaCPP backend registered successfully');
      }
      return success;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      log.warning(`LlamaCPP registration failed: ${msg}`);
      return false;
    }
  }

  /**
   * Unregister the LlamaCPP backend from C++ registry.
   * @returns Promise<boolean> true if unregistered successfully
   */
  static async unregister(): Promise<boolean> {
    if (!this.isRegistered) {
      return true;
    }

    if (!isNativeModuleAvailable()) {
      return false;
    }

    try {
      const native = requireNativeModule();
      const success = await native.unregisterLlamaCppBackend();
      if (success) {
        this.isRegistered = false;
        log.info('LlamaCPP backend unregistered');
      }
      return success;
    } catch (error) {
      return false;
    }
  }

  /**
   * Check if LlamaCPP can handle a given model
   */
  static canHandle(modelId: string | null | undefined): boolean {
    if (!modelId) {
      return false;
    }
    const lowercased = modelId.toLowerCase();
    return lowercased.includes('gguf') || lowercased.endsWith('.gguf');
  }
}

/**
 * Auto-register when module is imported
 */
export function autoRegister(): void {
  LlamaCppProvider.register().catch(() => {
    // Silently handle registration failure during auto-registration
  });
}
