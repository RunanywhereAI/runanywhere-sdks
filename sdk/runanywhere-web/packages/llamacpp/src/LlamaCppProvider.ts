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
let _registeringPromise: Promise<void> | null = null;

async function _doRegister(acceleration?: 'auto' | 'webgpu' | 'cpu'): Promise<void> {
  const bridge = LlamaCppBridge.shared;
  await bridge.ensureLoaded(acceleration);

  // Load llama.cpp struct offsets from the WASM module
  loadOffsets();

  // Register model loaders with ModelManager
  ModelManager.setLLMLoader(TextGeneration);

  // Register extensions with lifecycle registry (only those with cleanup)
  ExtensionRegistry.register(TextGeneration);
  ExtensionRegistry.register(VLM);
  ExtensionRegistry.register(ToolCalling);
  ExtensionRegistry.register(Embeddings);
  ExtensionRegistry.register(Diffusion);

  // Register with ExtensionPoint for capability lookups
  ExtensionPoint.registerBackend(llamacppExtension);

  // Register typed provider so VoicePipeline (in core) can access
  // the LLM via ExtensionPoint.getProvider('llm') at runtime.
  ExtensionPoint.registerProvider('llm', TextGeneration);

  _isRegistered = true;
  logger.info('LlamaCpp backend registered successfully');
}

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
    TextGeneration.cleanup();
    VLM.cleanup();
    ToolCalling.cleanup();
    Embeddings.cleanup();
    Diffusion.cleanup();
    ExtensionPoint.removeProvider('llm');
    _isRegistered = false;
    _registeringPromise = null;
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
   *
   * @param acceleration - Hardware acceleration strategy (default: 'auto').
   */
  async register(acceleration?: 'auto' | 'webgpu' | 'cpu'): Promise<void> {
    if (_isRegistered) {
      logger.debug('LlamaCpp backend already registered, skipping');
      return;
    }

    if (_registeringPromise) {
      logger.debug('LlamaCpp registration in progress, awaiting...');
      return _registeringPromise;
    }

    _registeringPromise = _doRegister(acceleration);
    try {
      await _registeringPromise;
    } finally {
      _registeringPromise = null;
    }
  },

  /**
   * Unregister the backend and clean up resources.
   */
  unregister(): void {
    llamacppExtension.cleanup();
  },
};
