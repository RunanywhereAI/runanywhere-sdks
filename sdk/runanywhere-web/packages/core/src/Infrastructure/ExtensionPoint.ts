/**
 * ExtensionPoint - Backend registration API
 *
 * Follows the React Native SDK's Provider pattern. Backend packages
 * (e.g. @runanywhere/web-llamacpp, @runanywhere/web-onnx) register
 * themselves with the core SDK via this API, declaring what capabilities
 * they provide.
 *
 * Usage:
 *   // In @runanywhere/web-llamacpp:
 *   import { ExtensionPoint, BackendCapability } from '@runanywhere/web';
 *
 *   ExtensionPoint.registerBackend({
 *     id: 'llamacpp',
 *     capabilities: [BackendCapability.LLM, BackendCapability.VLM, ...],
 *     cleanup() { ... },
 *   });
 *
 *   // In core (VoicePipeline, etc.) — runtime lookup:
 *   const stt = ExtensionPoint.getExtensionForCapability(BackendCapability.STT);
 */

import { SDKLogger } from '../Foundation/SDKLogger';

const logger = new SDKLogger('ExtensionPoint');

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Capabilities that a backend can provide. */
export enum BackendCapability {
  LLM = 'llm',
  VLM = 'vlm',
  STT = 'stt',
  TTS = 'tts',
  VAD = 'vad',
  Embeddings = 'embeddings',
  Diffusion = 'diffusion',
  ToolCalling = 'toolCalling',
  StructuredOutput = 'structuredOutput',
}

/**
 * Interface that every backend package must implement to register
 * itself with the core SDK.
 */
export interface BackendExtension {
  /** Unique backend identifier (e.g. 'llamacpp', 'onnx'). */
  readonly id: string;

  /** Capabilities this backend provides. */
  readonly capabilities: BackendCapability[];

  /**
   * Release all resources held by this backend.
   * Called during SDK shutdown in reverse registration order.
   */
  cleanup(): void;
}

// ---------------------------------------------------------------------------
// ExtensionPoint Singleton
// ---------------------------------------------------------------------------

class ExtensionPointImpl {
  private backends: Map<string, BackendExtension> = new Map();
  private capabilityMap: Map<BackendCapability, BackendExtension> = new Map();

  /**
   * Register a backend extension.
   * Idempotent — re-registering the same id is a no-op.
   */
  registerBackend(extension: BackendExtension): void {
    if (this.backends.has(extension.id)) {
      logger.debug(`Backend '${extension.id}' already registered, skipping`);
      return;
    }

    this.backends.set(extension.id, extension);

    for (const cap of extension.capabilities) {
      if (this.capabilityMap.has(cap)) {
        logger.warning(
          `Capability '${cap}' already provided by '${this.capabilityMap.get(cap)!.id}', ` +
          `overriding with '${extension.id}'`,
        );
      }
      this.capabilityMap.set(cap, extension);
    }

    logger.info(`Backend '${extension.id}' registered — capabilities: [${extension.capabilities.join(', ')}]`);
  }

  /** Get a backend by its id. */
  getBackend(id: string): BackendExtension | undefined {
    return this.backends.get(id);
  }

  /** Check if a capability is available (i.e. a backend providing it is registered). */
  hasCapability(capability: BackendCapability): boolean {
    return this.capabilityMap.has(capability);
  }

  /** Get the backend extension providing a given capability. */
  getExtensionForCapability(capability: BackendCapability): BackendExtension | undefined {
    return this.capabilityMap.get(capability);
  }

  /**
   * Require that a capability is available. Throws a clear error if not.
   * Use in extension methods that depend on a backend being registered.
   */
  requireCapability(capability: BackendCapability): void {
    if (!this.capabilityMap.has(capability)) {
      const packageHint = capability === BackendCapability.LLM ||
        capability === BackendCapability.VLM ||
        capability === BackendCapability.Embeddings ||
        capability === BackendCapability.Diffusion ||
        capability === BackendCapability.ToolCalling ||
        capability === BackendCapability.StructuredOutput
        ? '@runanywhere/web-llamacpp'
        : '@runanywhere/web-onnx';

      throw new Error(
        `Capability '${capability}' not available. ` +
        `Install and register the ${packageHint} package.`,
      );
    }
  }

  /**
   * Cleanup all registered backends in reverse registration order.
   * Called during SDK shutdown.
   */
  cleanupAll(): void {
    const entries = [...this.backends.entries()].reverse();
    for (const [id, backend] of entries) {
      try {
        backend.cleanup();
        logger.debug(`Backend '${id}' cleaned up`);
      } catch {
        // Ignore errors during shutdown
      }
    }
  }

  /** Reset the registry (call after full shutdown). */
  reset(): void {
    this.backends.clear();
    this.capabilityMap.clear();
  }
}

export const ExtensionPoint = new ExtensionPointImpl();
