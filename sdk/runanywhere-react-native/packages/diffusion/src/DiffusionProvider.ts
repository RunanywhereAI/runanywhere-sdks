/**
 * Diffusion Provider - Native Bridge Integration
 *
 * Diffusion is iOS-only (CoreML/ANE). On Android, all methods throw or return false.
 */

import { Platform } from 'react-native';
import {
  requireNativeDiffusionModule,
  isNativeDiffusionModuleAvailable,
} from './native/NativeRunAnywhereDiffusion';
import type {
  DiffusionConfiguration,
  DiffusionGenerationOptions,
  DiffusionResult,
  DiffusionTokenizerSource,
} from './types';

const DIFFUSION_IOS_ONLY_MSG =
  'Diffusion is only supported on iOS (CoreML/ANE). It is not available on Android.';

function assertIOS(): void {
  if (Platform.OS !== 'ios') {
    throw new Error(DIFFUSION_IOS_ONLY_MSG);
  }
}

/**
 * Convert tokenizer source to C++ enum value
 */
function tokenizerSourceToCValue(source: DiffusionTokenizerSource): number {
  switch (source.type) {
    case 'sd15':
      return 0;
    case 'sd2':
      return 1;
    case 'sdxl':
      return 2;
    case 'custom':
      return 99;
  }
}

/**
 * Diffusion Provider class
 */
export class DiffusionProvider {
  private static _isRegistered = false;

  /**
   * Register the Diffusion backend
   */
  static async register(): Promise<boolean> {
    if (Platform.OS !== 'ios') {
      return false;
    }
    if (this._isRegistered) return true;
    if (!isNativeDiffusionModuleAvailable()) {
      console.warn(
        '[Diffusion] Native module not available. Ensure the native library is bundled.'
      );
      return false;
    }

    try {
      const native = requireNativeDiffusionModule();
      const success = await native.registerBackend();
      if (success) {
        this._isRegistered = true;
      }
      return success;
    } catch (error) {
      console.error('[Diffusion] Failed to register backend:', error);
      return false;
    }
  }

  /**
   * Unregister the Diffusion backend
   */
  static async unregister(): Promise<boolean> {
    if (Platform.OS !== 'ios') return true;
    if (!this._isRegistered) return true;

    try {
      const native = requireNativeDiffusionModule();
      const success = await native.unregisterBackend();
      if (success) {
        this._isRegistered = false;
      }
      return success;
    } catch (error) {
      console.error('[Diffusion] Failed to unregister backend:', error);
      return false;
    }
  }

  /**
   * Check if registered
   */
  static async isRegistered(): Promise<boolean> {
    return this._isRegistered;
  }

  /**
   * Configure the diffusion component
   */
  static async configure(config: DiffusionConfiguration): Promise<void> {
    assertIOS();
    const native = requireNativeDiffusionModule();

    const configJson = JSON.stringify({
      model_id: config.modelId,
      preferred_framework: config.preferredFramework,
      model_variant: config.modelVariant,
      enable_safety_checker: config.enableSafetyChecker ?? true,
      reduce_memory: config.reduceMemory ?? false,
      tokenizer_source: config.tokenizerSource
        ? tokenizerSourceToCValue(config.tokenizerSource)
        : undefined,
      tokenizer_custom_url:
        config.tokenizerSource?.type === 'custom'
          ? config.tokenizerSource.baseURL
          : undefined,
    });

    const success = await native.configure(configJson);
    if (!success) {
      throw new Error('Failed to configure Diffusion component');
    }
  }

  /**
   * Load a diffusion model
   */
  static async loadModel(
    path: string,
    modelId: string,
    modelName?: string
  ): Promise<void> {
    assertIOS();
    const native = requireNativeDiffusionModule();
    const success = await native.loadModel(path, modelId, modelName);
    if (!success) {
      throw new Error(`Failed to load Diffusion model: ${modelId}`);
    }
  }

  /**
   * Unload the current model
   */
  static async unloadModel(): Promise<void> {
    assertIOS();
    const native = requireNativeDiffusionModule();
    await native.unloadModel();
  }

  /**
   * Check if a model is loaded
   */
  static async isModelLoaded(): Promise<boolean> {
    if (Platform.OS !== 'ios') return false;
    const native = requireNativeDiffusionModule();
    return native.isModelLoaded();
  }

  /**
   * Generate an image
   */
  static async generateImage(
    prompt: string,
    options?: Partial<DiffusionGenerationOptions>
  ): Promise<DiffusionResult> {
    assertIOS();
    const native = requireNativeDiffusionModule();

    const optionsJson = JSON.stringify({
      prompt,
      negative_prompt: options?.negativePrompt ?? '',
      width: options?.width ?? 512,
      height: options?.height ?? 512,
      steps: options?.steps ?? 28,
      guidance_scale: options?.guidanceScale ?? 7.5,
      seed: options?.seed ?? -1,
      scheduler: options?.scheduler ?? 'dpm++_2m_karras',
      mode: 'txt2img',
      denoise_strength: options?.denoiseStrength ?? 0.75,
      report_intermediate_images: options?.reportIntermediateImages ?? false,
      progress_stride: options?.progressStride ?? 1,
    });

    const resultJson = await native.generateImage(prompt, optionsJson);
    const result = JSON.parse(resultJson);

    return {
      imageBase64: result.image_data,
      width: result.width,
      height: result.height,
      seedUsed: result.seed_used,
      generationTimeMs: result.generation_time_ms,
      safetyFlagged: result.safety_flagged ?? false,
    };
  }

  /**
   * Image-to-image transformation
   */
  static async imageToImage(
    prompt: string,
    inputImageBase64: string,
    options?: Partial<DiffusionGenerationOptions>
  ): Promise<DiffusionResult> {
    assertIOS();
    const native = requireNativeDiffusionModule();

    const optionsJson = JSON.stringify({
      negative_prompt: options?.negativePrompt ?? '',
      steps: options?.steps ?? 28,
      guidance_scale: options?.guidanceScale ?? 7.5,
      seed: options?.seed ?? -1,
      scheduler: options?.scheduler ?? 'dpm++_2m_karras',
      denoise_strength: options?.denoiseStrength ?? 0.75,
    });

    const resultJson = await native.imageToImage(
      prompt,
      inputImageBase64,
      optionsJson
    );
    const result = JSON.parse(resultJson);

    return {
      imageBase64: result.image_data,
      width: result.width,
      height: result.height,
      seedUsed: result.seed_used,
      generationTimeMs: result.generation_time_ms,
      safetyFlagged: result.safety_flagged ?? false,
    };
  }

  /**
   * Inpainting
   */
  static async inpaint(
    prompt: string,
    inputImageBase64: string,
    maskImageBase64: string,
    options?: Partial<DiffusionGenerationOptions>
  ): Promise<DiffusionResult> {
    assertIOS();
    const native = requireNativeDiffusionModule();

    const optionsJson = JSON.stringify({
      negative_prompt: options?.negativePrompt ?? '',
      steps: options?.steps ?? 28,
      guidance_scale: options?.guidanceScale ?? 7.5,
      seed: options?.seed ?? -1,
      scheduler: options?.scheduler ?? 'dpm++_2m_karras',
    });

    const resultJson = await native.inpaint(
      prompt,
      inputImageBase64,
      maskImageBase64,
      optionsJson
    );
    const result = JSON.parse(resultJson);

    return {
      imageBase64: result.image_data,
      width: result.width,
      height: result.height,
      seedUsed: result.seed_used,
      generationTimeMs: result.generation_time_ms,
      safetyFlagged: result.safety_flagged ?? false,
    };
  }

  /**
   * Cancel generation
   */
  static async cancel(): Promise<void> {
    assertIOS();
    const native = requireNativeDiffusionModule();
    await native.cancelGeneration();
  }
}
