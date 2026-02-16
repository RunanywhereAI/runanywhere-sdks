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
  WASMBridge,
  SDKLogger,
  ModelManager,
  ExtensionPoint,
  BackendCapability,
  ExtensionRegistry,
  loadLlamaCppOffsetsInto,
} from '@runanywhere/web';

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
   * 1. Calls rac_backend_llamacpp_register() via WASMBridge (if available)
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

    const bridge = WASMBridge.shared;
    if (!bridge.isLoaded) {
      throw new Error('WASM module not loaded — call RunAnywhere.initialize() first.');
    }

    // Register the C++ backend (if compiled in)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const m = bridge.module as any;
    if (typeof m['_rac_backend_llamacpp_register'] === 'function') {
      const regResult = await bridge.callFunction<number | Promise<number>>(
        'rac_backend_llamacpp_register', 'number', [], [], { async: true },
      ) as number;
      if (regResult === 0) {
        logger.info('llama.cpp C++ backend registered');
      } else {
        logger.warning(`llama.cpp backend registration returned: ${regResult}`);
      }
    }

    // Load llama.cpp struct offsets
    loadLlamaCppOffsetsInto(bridge.module);

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

    // Register singletons on globalThis so VoicePipeline (in core) can
    // access them at runtime without importing from this package directly.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (globalThis as any).__runanywhere_textgeneration = TextGeneration;

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
