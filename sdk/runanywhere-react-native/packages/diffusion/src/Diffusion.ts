/**
 * Diffusion Module for React Native SDK
 *
 * Image generation using Stable Diffusion models. iOS only (CoreML/ANE).
 * On Android, register() returns false and other operations throw.
 */

import { DiffusionProvider } from './DiffusionProvider';
import type {
  DiffusionConfiguration,
  DiffusionGenerationOptions,
  DiffusionResult,
  DiffusionModelVariant,
} from './types';

/**
 * Diffusion module for image generation
 */
export const Diffusion = {
  /**
   * Module identifier
   */
  moduleId: 'diffusion' as const,

  /**
   * Human-readable module name
   */
  moduleName: 'Diffusion' as const,

  /**
   * Capabilities provided by this module
   */
  capabilities: ['image-generation'] as const,

  /**
   * Register the Diffusion backend
   */
  async register(): Promise<boolean> {
    return DiffusionProvider.register();
  },

  /**
   * Unregister the Diffusion backend
   */
  async unregister(): Promise<boolean> {
    return DiffusionProvider.unregister();
  },

  /**
   * Check if the backend is registered
   */
  async isRegistered(): Promise<boolean> {
    return DiffusionProvider.isRegistered();
  },

  /**
   * Configure the diffusion component
   */
  async configure(config: DiffusionConfiguration): Promise<void> {
    await DiffusionProvider.configure(config);
  },

  /**
   * Load a diffusion model
   */
  async loadModel(
    path: string,
    modelId: string,
    modelName?: string
  ): Promise<void> {
    await DiffusionProvider.loadModel(path, modelId, modelName);
  },

  /**
   * Unload the current model
   */
  async unloadModel(): Promise<void> {
    await DiffusionProvider.unloadModel();
  },

  /**
   * Check if a model is loaded
   */
  async isModelLoaded(): Promise<boolean> {
    return DiffusionProvider.isModelLoaded();
  },

  /**
   * Generate an image from a text prompt
   */
  async generateImage(
    prompt: string,
    options?: Partial<DiffusionGenerationOptions>
  ): Promise<DiffusionResult> {
    return DiffusionProvider.generateImage(prompt, options);
  },

  /**
   * Transform an image using image-to-image
   */
  async imageToImage(
    prompt: string,
    inputImageBase64: string,
    options?: Partial<DiffusionGenerationOptions>
  ): Promise<DiffusionResult> {
    return DiffusionProvider.imageToImage(prompt, inputImageBase64, options);
  },

  /**
   * Inpaint a region of an image
   */
  async inpaint(
    prompt: string,
    inputImageBase64: string,
    maskImageBase64: string,
    options?: Partial<DiffusionGenerationOptions>
  ): Promise<DiffusionResult> {
    return DiffusionProvider.inpaint(
      prompt,
      inputImageBase64,
      maskImageBase64,
      options
    );
  },

  /**
   * Cancel ongoing generation
   */
  async cancel(): Promise<void> {
    await DiffusionProvider.cancel();
  },

  /**
   * Add a model to the model registry (for model management)
   */
  addModel(options: {
    name: string;
    url: string;
    variant?: DiffusionModelVariant;
    memoryRequirement?: number;
  }): void {
    // This would integrate with the core model registry
    // For now, we just validate the options
    if (!options.name || !options.url) {
      throw new Error('Model name and URL are required');
    }
  },
};

export type { DiffusionProvider };
