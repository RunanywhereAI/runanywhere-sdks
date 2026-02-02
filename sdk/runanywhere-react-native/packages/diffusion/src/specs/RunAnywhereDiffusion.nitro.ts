/**
 * RunAnywhereDiffusion Nitrogen Spec
 *
 * Diffusion backend interface for image generation:
 * - Backend Registration
 * - Model Loading/Unloading
 * - Text-to-Image generation
 * - Image-to-Image generation
 * - Inpainting
 *
 * Matches Swift SDK: CppBridge+Diffusion.swift + RunAnywhere+Diffusion.swift
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * Diffusion image generation native interface
 *
 * This interface provides Diffusion (Stable Diffusion) image generation capabilities.
 * Supports both ONNX (cross-platform) and CoreML (iOS only) backends.
 * Requires @runanywhere/core to be initialized first.
 */
export interface RunAnywhereDiffusion
  extends HybridObject<{
    ios: 'c++';
    android: 'c++';
  }> {
  // ============================================================================
  // Backend Registration
  // ============================================================================

  /**
   * Register the Diffusion backend with the C++ service registry.
   * Safe to call multiple times - subsequent calls are no-ops.
   * @returns true if registered successfully (or already registered)
   */
  registerBackend(): Promise<boolean>;

  /**
   * Unregister the Diffusion backend from the C++ service registry.
   * @returns true if unregistered successfully
   */
  unregisterBackend(): Promise<boolean>;

  /**
   * Check if the Diffusion backend is registered
   * @returns true if backend is registered
   */
  isBackendRegistered(): Promise<boolean>;

  // ============================================================================
  // Configuration
  // ============================================================================

  /**
   * Configure the diffusion component
   * @param configJson JSON configuration with model_variant, tokenizer settings, etc.
   * @returns true if configured successfully
   */
  configure(configJson: string): Promise<boolean>;

  // ============================================================================
  // Model Loading
  // ============================================================================

  /**
   * Load a Diffusion model
   * @param path Path to the model directory
   * @param modelId Unique identifier for the model
   * @param modelName Human-readable model name
   * @param configJson Optional JSON configuration
   * @returns true if loaded successfully
   */
  loadModel(
    path: string,
    modelId: string,
    modelName?: string,
    configJson?: string
  ): Promise<boolean>;

  /**
   * Check if a Diffusion model is loaded
   */
  isModelLoaded(): Promise<boolean>;

  /**
   * Unload the current Diffusion model
   */
  unloadModel(): Promise<boolean>;

  /**
   * Get the currently loaded model ID
   * @returns Model ID or null if no model is loaded
   */
  getLoadedModelId(): Promise<string | undefined>;

  // ============================================================================
  // Image Generation
  // ============================================================================

  /**
   * Generate an image from a text prompt
   * @param prompt Text description of the desired image
   * @param optionsJson JSON options (width, height, steps, guidance_scale, seed, etc.)
   * @returns JSON string with generation result:
   *   - image_data: Base64-encoded PNG image data
   *   - width: Image width in pixels
   *   - height: Image height in pixels
   *   - seed_used: Seed used for generation
   *   - generation_time_ms: Time taken in milliseconds
   *   - safety_flagged: Whether safety checker flagged the image
   */
  generateImage(prompt: string, optionsJson: string): Promise<string>;

  /**
   * Transform an image using image-to-image mode
   * @param prompt Text description of the transformation
   * @param inputImageBase64 Base64-encoded input image (PNG/JPEG)
   * @param optionsJson JSON options (denoise_strength, steps, etc.)
   * @returns JSON string with generation result
   */
  imageToImage(
    prompt: string,
    inputImageBase64: string,
    optionsJson: string
  ): Promise<string>;

  /**
   * Inpaint a region of an image
   * @param prompt Text description of what to paint
   * @param inputImageBase64 Base64-encoded input image
   * @param maskImageBase64 Base64-encoded mask image (white = paint)
   * @param optionsJson JSON options
   * @returns JSON string with generation result
   */
  inpaint(
    prompt: string,
    inputImageBase64: string,
    maskImageBase64: string,
    optionsJson: string
  ): Promise<string>;

  /**
   * Cancel ongoing image generation
   */
  cancelGeneration(): Promise<void>;

  // ============================================================================
  // Progress & State
  // ============================================================================

  /**
   * Check if generation is in progress
   */
  isGenerating(): Promise<boolean>;

  /**
   * Get current generation progress
   * @returns JSON with progress, currentStep, totalSteps, stage
   */
  getProgress(): Promise<string>;

  // ============================================================================
  // Model Information
  // ============================================================================

  /**
   * Get supported schedulers for the loaded model
   * @returns JSON array of scheduler names
   */
  getSupportedSchedulers(): Promise<string>;

  /**
   * Get model capabilities
   * @returns JSON with supports_txt2img, supports_img2img, supports_inpainting, etc.
   */
  getModelCapabilities(): Promise<string>;

  // ============================================================================
  // Utilities
  // ============================================================================

  /**
   * Get the last error message from the Diffusion backend
   */
  getLastError(): Promise<string>;

  /**
   * Get current memory usage of the Diffusion backend
   * @returns Memory usage in bytes
   */
  getMemoryUsage(): Promise<number>;
}
