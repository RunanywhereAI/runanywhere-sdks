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
const vlmLog = new SDKLogger('VLM.LlamaCppProvider');

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
  private static isVLMRegistered = false;

  /**
   * Register LlamaCPP backend with the C++ service registry.
   * Calls rac_backend_llamacpp_register() to register the
   * LlamaCPP service provider with the C++ commons layer.
   * Also registers the VLM backend (matching iOS SDK pattern).
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

        // Register VLM backend (matches iOS: LlamaCPP.register() also registers VLM)
        await this.registerVLM();
      }
      return success;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      log.warning(`LlamaCPP registration failed: ${msg}`);
      return false;
    }
  }

  /**
   * Register VLM (Vision Language Model) backend.
   * Called automatically by register() to match iOS SDK pattern.
   * Matches iOS: LlamaCPP.registerVLM()
   */
  private static async registerVLM(): Promise<void> {
    if (this.isVLMRegistered) {
      return;
    }

    if (!isNativeLlamaModuleAvailable()) {
      return;
    }

    vlmLog.info('Registering LlamaCPP VLM backend...');

    try {
      const native = requireNativeLlamaModule();
      const success = await native.registerVLMBackend();
      if (success) {
        this.isVLMRegistered = true;
        vlmLog.info('LlamaCPP VLM backend registered successfully');
      } else {
        vlmLog.warning('LlamaCPP VLM registration returned false (VLM features may not be available)');
      }
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      vlmLog.warning(`LlamaCPP VLM registration failed: ${msg} (VLM features may not be available)`);
    }
  }

  /**
   * Unregister the LlamaCPP backend from C++ registry.
   * Also unregisters the VLM backend (matching iOS SDK pattern).
   * @returns Promise<boolean> true if unregistered successfully
   */
  static async unregister(): Promise<boolean> {
    if (!isNativeLlamaModuleAvailable()) {
      return false;
    }

    const native = requireNativeLlamaModule();

    // Unregister VLM first (matches iOS: unregister VLM before LLM)
    if (this.isVLMRegistered) {
      try {
        await native.unloadVLMModel();
        this.isVLMRegistered = false;
        vlmLog.info('LlamaCPP VLM backend unregistered');
      } catch (error) {
        vlmLog.error(`LlamaCPP VLM unregistration failed: ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    if (!this.isRegistered) {
      return true;
    }

    try {
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
