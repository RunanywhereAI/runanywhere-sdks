/**
 * LlamaCppProvider - Backend registration for @runanywhere/web-llamacpp
 *
 * Registers the llama.cpp backend with the RunAnywhere core SDK.
 * Follows the React Native SDK's Provider pattern.
 *
 * Usage:
 *   import { LlamaCppProvider } from '@runanywhere/web-llamacpp';
 *   await LlamaCppProvider.register();
 */

import {
  SDKLogger,
  ModelManager,
  ExtensionPoint,
  BackendCapability,
  ExtensionRegistry,
  ServiceKey,
} from '@runanywhere/web';

import { LlamaCppBridge } from './Foundation/LlamaCppBridge';
import { loadOffsets } from './Foundation/LlamaCppOffsets';

import { TextGeneration } from './Extensions/RunAnywhere+TextGeneration';
import { VLM } from './Extensions/RunAnywhere+VLM';
import { ToolCalling } from './Extensions/RunAnywhere+ToolCalling';
import { Embeddings } from './Extensions/RunAnywhere+Embeddings';
import { Diffusion } from './Extensions/RunAnywhere+Diffusion';

import type { BackendExtension } from '@runanywhere/web';

const logger = new SDKLogger('LlamaCppProvider');

let _isRegistered = false;

const llamacppExtension: BackendExtension = {
  id: 'llamacpp',
  capabilities: [
    BackendCapability.LLM,
    BackendCapability.VLM,
    BackendCapability.ToolCalling,
    BackendCapability.StructuredOutput,
    BackendCapability.Embeddings,
    BackendCapability.Diffusion,
  ],
  cleanup() {
    // Cleanup all extension singletons
    TextGeneration.cleanup();
    VLM.cleanup();
    ToolCalling.cleanup();
    Embeddings.cleanup();
    Diffusion.cleanup();
    // Remove service registrations
    ExtensionPoint.removeService(ServiceKey.TextGeneration);
    _isRegistered = false;
    logger.info('LlamaCpp backend cleaned up');
  },
};

export const LlamaCppProvider = {
  /** Whether the backend is currently registered. */
  get isRegistered(): boolean {
    return _isRegistered;
  },

  /**
   * Register the llama.cpp backend with the RunAnywhere SDK.
   *
   * This:
   * 1. Ensures LlamaCppBridge WASM is loaded (which registers the C++ backend)
   * 2. Loads llama.cpp-specific struct offsets
   * 3. Registers LLM model loader with ModelManager
   * 4. Registers all extension singletons with ExtensionRegistry
   * 5. Registers this backend with ExtensionPoint
   */
  async register(): Promise<void> {
    if (_isRegistered) {
      logger.debug('LlamaCpp backend already registered, skipping');
      return;
    }

    const bridge = LlamaCppBridge.shared;
    await bridge.ensureLoaded();

    // Load llama.cpp struct offsets from the WASM module
    loadOffsets();

    // Register model loaders with ModelManager
    ModelManager.setLLMLoader(TextGeneration);

    // Register extensions with lifecycle registry
    // Register extensions with lifecycle registry (only those with cleanup)
    ExtensionRegistry.register(TextGeneration);
    ExtensionRegistry.register(VLM);
    ExtensionRegistry.register(ToolCalling);
    ExtensionRegistry.register(Embeddings);
    ExtensionRegistry.register(Diffusion);

    // Register with ExtensionPoint for capability lookups
    ExtensionPoint.registerBackend(llamacppExtension);

    // Register service singletons with ExtensionPoint so VoicePipeline
    // (in core) can access them via typed keys at runtime.
    ExtensionPoint.registerService(ServiceKey.TextGeneration, TextGeneration);

    _isRegistered = true;
    logger.info('LlamaCpp backend registered successfully');
  },

  /**
   * Unregister the backend and clean up resources.
   */
  unregister(): void {
    llamacppExtension.cleanup();
  },
};
