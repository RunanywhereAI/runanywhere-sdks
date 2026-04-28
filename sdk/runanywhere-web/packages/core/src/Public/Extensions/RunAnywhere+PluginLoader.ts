/**
 * RunAnywhere+PluginLoader.ts
 *
 * Top-level plugin/extension management API — mirrors Swift's
 * `RunAnywhere+PluginLoader` extension. Exposes a stable namespace for
 * registering / inspecting installed backend extensions
 * (`@runanywhere/web-llamacpp`, `@runanywhere/web-onnx`, etc.) at runtime.
 *
 * Phase C-prime WEB: closes the gap where the Web SDK had backend
 * registration logic in `ExtensionRegistry` / `ExtensionPoint` but no
 * single `RunAnywhere.plugins.*` capability surface.
 *
 * Reference (Swift): `RunAnywhere+PluginLoader.swift`
 */

import { ExtensionRegistry, type SDKExtension } from '../../Infrastructure/ExtensionRegistry';
import { ExtensionPoint, BackendCapability } from '../../Infrastructure/ExtensionPoint';
import type { ProviderCapability } from '../../Infrastructure/ProviderTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';

const logger = new SDKLogger('PluginLoader');

/**
 * Free-function namespace mirroring Swift's `RunAnywhere.plugins` extension.
 */
export const PluginLoader = {
  /** Register a `SDKExtension` so its `cleanup()` runs during `RunAnywhere.shutdown()`. */
  register(extension: SDKExtension): void {
    ExtensionRegistry.register(extension);
    logger.info(`Plugin registered: ${extension.extensionName}`);
  },

  /**
   * Whether a provider for the given capability is currently registered.
   *
   * Provider capabilities are 'llm' | 'stt' | 'tts' | 'vad' (see ProviderTypes).
   */
  hasProvider(capability: ProviderCapability): boolean {
    return ExtensionPoint.getProvider(capability) != null;
  },

  /**
   * Whether a backend extension with the given capability is registered.
   *
   * Backend capabilities include LLM, VLM, Embeddings, Diffusion, etc. —
   * a coarser-grained classification than provider capabilities (see
   * `BackendCapability` in `ExtensionPoint`).
   */
  hasCapability(capability: BackendCapability): boolean {
    return ExtensionPoint.hasCapability(capability);
  },

  /**
   * Cleanup all registered extensions and reset the registry. Called by
   * `RunAnywhere.shutdown()` — exposed here for tests that want to tear
   * down extensions without a full shutdown.
   */
  cleanupAll(): void {
    ExtensionRegistry.cleanupAll();
    ExtensionPoint.cleanupAll();
    ExtensionRegistry.reset();
    ExtensionPoint.reset();
  },
};
