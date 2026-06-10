/**
 * @runanywhere/llamacpp - LlamaCPP Provider
 *
 * Internal LlamaCPP module registration for React Native SDK.
 * Thin wrapper that triggers C++ backend registration behind the LlamaCPP facade.
 *
 * Reference: sdk/runanywhere-swift/Sources/LlamaCPPRuntime/LlamaCPP.swift
 */

import { requireNativeLlamaModule, isNativeLlamaModuleAvailable } from './native/NativeRunAnywhereLlama';
import { SDKLogger } from '@runanywhere/core/internal';

// SDKLogger instance for this module
const log = new SDKLogger('LLM.LlamaCppProvider');

/**
 * Internal LlamaCPP provider implementation.
 *
 * Registers the llama.cpp backend provider; the single C++ registration call
 * covers both LLM and VLM modalities. Core owns public model lifecycle and
 * inference surfaces.
 *
 * @internal
 */
export class LlamaCppProvider {
  static readonly moduleId = 'llamacpp';
  static readonly moduleName = 'LlamaCPP';
  static readonly version = '2.0.0';

  private static registered = false;

  /**
   * Register LlamaCPP backend with the C++ service registry.
   * Calls rac_backend_llamacpp_register() to register the
   * LlamaCPP service provider with the C++ commons layer; the single call
   * covers both LLM and VLM modalities.
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
        log.info('LlamaCPP backend registered successfully (covers LLM and VLM)');
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
   * The single unregistration call covers both LLM and VLM modalities.
   * @returns Promise<boolean> true if unregistered successfully
   */
  static async unregister(): Promise<boolean> {
    if (!this.registered) {
      return true;
    }

    if (!isNativeLlamaModuleAvailable()) {
      return false;
    }

    const native = requireNativeLlamaModule();

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
