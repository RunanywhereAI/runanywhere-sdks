/**
 * @runanywhere/llamacpp - LlamaCPP Provider
 *
 * LlamaCPP module registration for React Native SDK.
 * Thin wrapper that triggers C++ backend registration.
 *
 * Reference: sdk/runanywhere-swift/Sources/LlamaCPPRuntime/LlamaCPP.swift
 */

import { requireNativeLlamaModule, isNativeLlamaModuleAvailable } from './native/NativeRunAnywhereLlama';
import { SDKLogger } from '@runanywhere/core';

// SDKLogger instance for this module
const log = new SDKLogger('LLM.LlamaCppProvider');

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

    if (!isNativeLlamaModuleAvailable()) {
      log.warning('LlamaCPP native module not available');
      return false;
    }

    log.debug('Registering LlamaCPP backend with C++ registry');

    try {
      const native = requireNativeLlamaModule();
      // Call the native registration method from the Llama module
      const success = await native.registerBackend();
      if (success) {
        this.isRegistered = true;
        log.info('LlamaCPP backend registered successfully');
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

    if (!isNativeLlamaModuleAvailable()) {
      return false;
    }

    try {
      const native = requireNativeLlamaModule();
      const success = await native.unregisterBackend();
      if (success) {
        this.isRegistered = false;
        log.debug('LlamaCPP backend unregistered');
      }
      return success;
    } catch (error) {
      log.error(`LlamaCPP unregistration failed: ${error instanceof Error ? error.message : String(error)}`);
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
