/**
 * RunAnywhere+Diffusion.ts
 *
 * Image diffusion namespace — mirrors Swift's `RunAnywhere+Diffusion.swift`.
 * Provides `RunAnywhere.diffusion.*` capability surface and the canonical §8
 * flat verbs on `RunAnywhere.*` for image generation.
 */

import type {
  DiffusionGenerationOptions,
  DiffusionResult,
  DiffusionConfiguration,
  DiffusionCapabilities,
  DiffusionProgress,
} from '@runanywhere/proto-ts/diffusion_options';
export type { DiffusionGenerationOptions, DiffusionResult, DiffusionConfiguration, DiffusionCapabilities, DiffusionProgress };

import { ExtensionPoint, ServiceKey } from '../../Infrastructure/ExtensionPoint';
import { SDKException } from '../../Foundation/SDKException';

/** Backend-supplied diffusion provider interface. */
interface DiffusionProvider {
  generateImage?(prompt: string, options?: Partial<DiffusionGenerationOptions>): Promise<DiffusionResult>;
  generateImageStream?(prompt: string, options?: Partial<DiffusionGenerationOptions>): AsyncIterable<DiffusionProgress>;
  loadDiffusionModel?(config: DiffusionConfiguration): Promise<void>;
  unloadDiffusionModel?(): Promise<void>;
  isDiffusionModelLoaded?: boolean;
  cancelImageGeneration?(): void;
  getDiffusionCapabilities?(): DiffusionCapabilities;
}

function getDiffusionProvider(): DiffusionProvider | null {
  // Try the dedicated diffusion service registry first, then fall back to the
  // LLM provider which may also expose diffusion methods (llamacpp backend).
  const diffService = ExtensionPoint.getService<DiffusionProvider>(ServiceKey.Diffusion);
  if (diffService != null) return diffService;
  const llmProvider = ExtensionPoint.getProvider('llm') as DiffusionProvider | null | undefined;
  return llmProvider ?? null;
}

// ---------------------------------------------------------------------------
// §8 Canonical flat verbs — exposed both on `RunAnywhere.*` and via the
// `Diffusion` namespace object below.
// ---------------------------------------------------------------------------

/**
 * Generate an image from a text prompt (§8 `generateImage`).
 * Delegates to the diffusion provider registered by a backend package.
 */
export async function generateImage(
  prompt: string,
  options?: Partial<DiffusionGenerationOptions>,
): Promise<DiffusionResult> {
  const provider = getDiffusionProvider();
  if (typeof provider?.generateImage === 'function') {
    return provider.generateImage(prompt, options);
  }
  throw SDKException.backendNotAvailable(
    'generateImage',
    'No diffusion backend registered. Install @runanywhere/web-llamacpp and call LlamaCPP.register().',
  );
}

/**
 * Stream image generation progress (§8 `generateImageStream`).
 * Returns an AsyncIterable of DiffusionProgress events.
 */
export function generateImageStream(
  prompt: string,
  options?: Partial<DiffusionGenerationOptions>,
): AsyncIterable<DiffusionProgress> {
  const provider = getDiffusionProvider();
  if (typeof provider?.generateImageStream === 'function') {
    return provider.generateImageStream(prompt, options);
  }
  throw SDKException.backendNotAvailable(
    'generateImageStream',
    'No diffusion backend registered. Install @runanywhere/web-llamacpp and call LlamaCPP.register().',
  );
}

/**
 * Load a diffusion model by configuration (§8 `loadDiffusionModel`).
 */
export async function loadDiffusionModel(config: DiffusionConfiguration): Promise<void> {
  const provider = getDiffusionProvider();
  if (typeof provider?.loadDiffusionModel === 'function') {
    return provider.loadDiffusionModel(config);
  }
  throw SDKException.backendNotAvailable(
    'loadDiffusionModel',
    'No diffusion backend registered. Install @runanywhere/web-llamacpp and call LlamaCPP.register().',
  );
}

/**
 * Unload the active diffusion model (§8 `unloadDiffusionModel`).
 */
export async function unloadDiffusionModel(): Promise<void> {
  const provider = getDiffusionProvider();
  if (typeof provider?.unloadDiffusionModel === 'function') {
    return provider.unloadDiffusionModel();
  }
}

/**
 * Whether a diffusion model is currently loaded (§8 `isDiffusionModelLoaded`).
 */
export function getIsDiffusionModelLoaded(): boolean {
  return getDiffusionProvider()?.isDiffusionModelLoaded ?? false;
}

/**
 * Cancel any in-progress image generation (§8 `cancelImageGeneration`).
 */
export function cancelImageGeneration(): void {
  const provider = getDiffusionProvider();
  if (typeof provider?.cancelImageGeneration === 'function') {
    provider.cancelImageGeneration();
  }
}

/**
 * Return the capability descriptor for the loaded diffusion backend (§8).
 */
export function getDiffusionCapabilities(): DiffusionCapabilities {
  const provider = getDiffusionProvider();
  if (typeof provider?.getDiffusionCapabilities === 'function') {
    return provider.getDiffusionCapabilities();
  }
  // Return a minimal zero-capability descriptor when no backend is registered.
  return {
    supportedVariants: [],
    supportedSchedulers: [],
    maxResolutionPx: 0,
  };
}

export const Diffusion = {
  /** Legacy namespace entry kept for backward compat; prefer the flat verb. */
  async generate(options: DiffusionGenerationOptions): Promise<DiffusionResult> {
    return generateImage(options.prompt ?? '', options);
  },

  generateImage,
  generateImageStream,
  loadDiffusionModel,
  unloadDiffusionModel,
  cancelImageGeneration,
  getDiffusionCapabilities,

  get isDiffusionModelLoaded(): boolean {
    return getIsDiffusionModelLoaded();
  },
};
