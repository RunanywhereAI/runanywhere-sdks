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
 * Registers llama.cpp LLM and VLM providers. Core owns public model lifecycle
 * and inference surfaces.
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

  private static registered = false;
  private static isVLMRegistered = false;

  /**
   * Register LlamaCPP backend with the C++ service registry.
   * Calls rac_backend_llamacpp_register() to register the
   * LlamaCPP service provider with the C++ commons layer.
   * Also registers the VLM backend provider; core owns VLM model lifecycle.
   * Safe to call multiple times - subsequent calls are no-ops.
   * @returns Promise<boolean> true if registered successfully
   */
  static async register(): Promise<boolean> {
    if (this.registered) {
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
        this.registered = true;
        log.info('LlamaCPP backend registered successfully');

        // Register the VLM provider; core owns VLM lifecycle and proto calls.
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
   * Register VLM (Vision Language Model) backend provider.
   * Called automatically by register().
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
   * Also unregisters the VLM backend provider.
   * @returns Promise<boolean> true if unregistered successfully
   */
  static async unregister(): Promise<boolean> {
    if (!isNativeLlamaModuleAvailable()) {
      return false;
    }

    const native = requireNativeLlamaModule();

    // Unregister VLM first. VLM model handles are lifecycle-owned by core;
    // backend unregistration only removes the provider.
    if (this.isVLMRegistered) {
      try {
        await native.unregisterVLMBackend();
        this.isVLMRegistered = false;
        vlmLog.info('LlamaCPP VLM backend unregistered');
      } catch (error) {
        vlmLog.error(`LlamaCPP VLM unregistration failed: ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    if (!this.registered) {
      return true;
    }

    try {
      const success = await native.unregisterBackend();
      if (success) {
        this.registered = false;
        log.debug('LlamaCPP backend unregistered');
      }
      return success;
    } catch (error) {
      log.error(`LlamaCPP unregistration failed: ${error instanceof Error ? error.message : String(error)}`);
      return false;
    }
  }

  /**
   * Check native registration state. Falls back to JS state if the native
   * object cannot be created.
   */
  static async isRegistered(): Promise<boolean> {
    if (!isNativeLlamaModuleAvailable()) {
      return false;
    }

    try {
      const native = requireNativeLlamaModule();
      const registered = await native.isBackendRegistered();
      this.registered = registered;
      return registered;
    } catch {
      return this.registered;
    }
  }
}
