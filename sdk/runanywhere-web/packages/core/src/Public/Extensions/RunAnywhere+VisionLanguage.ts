/**
 * RunAnywhere+VisionLanguage.ts
 *
 * Vision-language model namespace — mirrors Swift's `RunAnywhere+VisionLanguage.swift`.
 * Provides `RunAnywhere.visionLanguage.*` capability surface for VLM inference.
 * Implements all canonical §7 methods.
 */

import type {
  VLMImage,
  VLMGenerationOptions,
  VLMResult,
  VLMConfiguration,
} from '@runanywhere/proto-ts/vlm_options';
export { VLMImageFormat, VLMErrorCode } from '@runanywhere/proto-ts/vlm_options';
export type { VLMImage, VLMGenerationOptions, VLMResult, VLMConfiguration };

import { ExtensionPoint, ServiceKey } from '../../Infrastructure/ExtensionPoint';
import { SDKException } from '../../Foundation/SDKException';

/** Extended VLM provider interface covering all canonical §7 methods. */
interface VLMProvider {
  generateVLM?(opts: VLMGenerationOptions): Promise<VLMResult>;
  processImageStream?(image: VLMImage, prompt: string, options?: VLMGenerationOptions): AsyncIterable<string>;
  cancelVLMGeneration?(): void;
  loadVLMModel?(modelId: string): Promise<void>;
  unloadVLMModel?(): Promise<void>;
  isVLMModelLoaded?: boolean;
  describeImage?(image: VLMImage, prompt?: string): Promise<string>;
  askAboutImage?(question: string, image: VLMImage): Promise<string>;
}

function getVLMProvider(): VLMProvider | null {
  const service = ExtensionPoint.getService<VLMProvider>(ServiceKey.VLM);
  if (service != null) return service;
  return ExtensionPoint.getProvider('llm') as VLMProvider | null;
}

export const VisionLanguage = {
  /** Generate a VLM response (full options form). */
  async generate(options: VLMGenerationOptions): Promise<VLMResult> {
    const provider = getVLMProvider();
    if (provider?.generateVLM) {
      return provider.generateVLM(options);
    }
    throw SDKException.backendNotAvailable('VisionLanguage.generate', 'Install @runanywhere/web-llamacpp and call LlamaCPP.register().');
  },

  /**
   * Describe an image (§7 `describeImage`).
   * Returns a text description of the image.
   */
  async describeImage(image: VLMImage, prompt?: string): Promise<string> {
    const provider = getVLMProvider();
    if (typeof provider?.describeImage === 'function') {
      return provider.describeImage(image, prompt);
    }
    throw SDKException.backendNotAvailable(
      'describeImage',
      'Install @runanywhere/web-llamacpp and call LlamaCPP.register().',
    );
  },

  /**
   * Ask a question about an image (§7 `askAboutImage`).
   */
  async askAboutImage(question: string, image: VLMImage): Promise<string> {
    const provider = getVLMProvider();
    if (typeof provider?.askAboutImage === 'function') {
      return provider.askAboutImage(question, image);
    }
    throw SDKException.backendNotAvailable(
      'askAboutImage',
      'Install @runanywhere/web-llamacpp and call LlamaCPP.register().',
    );
  },

  /**
   * Process an image and stream the response token-by-token (§7 `processImageStream`).
   */
  processImageStream(
    image: VLMImage,
    prompt: string,
    options?: VLMGenerationOptions,
  ): AsyncIterable<string> {
    const provider = getVLMProvider();
    if (typeof provider?.processImageStream === 'function') {
      return provider.processImageStream(image, prompt, options);
    }
    throw SDKException.backendNotAvailable(
      'processImageStream',
      'Install @runanywhere/web-llamacpp and call LlamaCPP.register().',
    );
  },

  /** Cancel an in-flight VLM generation (§7). */
  cancelVLMGeneration(): void {
    getVLMProvider()?.cancelVLMGeneration?.();
  },

  /** Load a VLM model by ID (§7). */
  async loadVLMModel(modelId: string): Promise<void> {
    const provider = getVLMProvider();
    if (typeof provider?.loadVLMModel === 'function') {
      return provider.loadVLMModel(modelId);
    }
    throw SDKException.backendNotAvailable(
      'loadVLMModel',
      'Install @runanywhere/web-llamacpp and call LlamaCPP.register().',
    );
  },

  /** Unload the active VLM model (§7). */
  async unloadVLMModel(): Promise<void> {
    const provider = getVLMProvider();
    if (typeof provider?.unloadVLMModel === 'function') {
      return provider.unloadVLMModel();
    }
  },

  /** Whether a VLM model is currently loaded (§7). */
  get isVLMModelLoaded(): boolean {
    return getVLMProvider()?.isVLMModelLoaded ?? false;
  },
};
