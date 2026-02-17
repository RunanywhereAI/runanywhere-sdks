/**
 * RunAnywhere+VLM.ts
 *
 * Vision Language Model (VLM) extension for RunAnywhere SDK.
 * Uses backend-agnostic rac_vlm_component_* C++ APIs via the llamacpp native module.
 * The VLM backend must be registered by calling registerVLMBackend() first.
 *
 * Matches iOS: RunAnywhere+VisionLanguage.swift
 */

import {
  requireNativeLlamaModule,
  isNativeLlamaModuleAvailable,
} from './native/NativeRunAnywhereLlama';
import { SDKLogger } from '@runanywhere/core';
import type {
  VLMImage,
  VLMResult,
  VLMStreamingResult,
  VLMGenerationOptions,
} from '@runanywhere/core';
import { VLMImageFormat } from '@runanywhere/core';

const logger = new SDKLogger('RunAnywhere.VLM');

// ============================================================================
// VLM Extension - Backend Agnostic
// ============================================================================

/**
 * Register VLM backend
 *
 * Registers the LlamaCPP VLM backend with the native bridge.
 * Must be called before loading VLM models.
 *
 * Matches iOS: Backend is auto-registered, but we need explicit registration in RN
 *
 * @returns Promise resolving to true if successful
 */
export async function registerVLMBackend(): Promise<boolean> {
  if (!isNativeLlamaModuleAvailable()) {
    logger.warning('Native Llama module not available for registerVLMBackend');
    return false;
  }
  const native = requireNativeLlamaModule();
  try {
    const result = await native.registerVLMBackend();
    if (result) {
      logger.info('VLM backend registered successfully');
    } else {
      logger.error('Failed to register VLM backend');
    }
    return result;
  } catch (error) {
    logger.error('Error registering VLM backend', { error });
    return false;
  }
}

/**
 * Load a VLM model
 *
 * Matches iOS: RunAnywhere.loadVLMModel(_:mmprojPath:modelId:modelName:)
 *
 * @param modelPath - Path to the main VLM model file
 * @param mmprojPath - Optional path to mmproj vision projector (auto-detected if in same directory)
 * @param modelId - Optional model identifier
 * @param modelName - Optional model display name
 * @returns Promise resolving to true if successful
 */
export async function loadVLMModel(
  modelPath: string,
  mmprojPath?: string,
  modelId?: string,
  modelName?: string
): Promise<boolean> {
  if (!isNativeLlamaModuleAvailable()) {
    logger.warning('Native Llama module not available for loadVLMModel');
    return false;
  }
  const native = requireNativeLlamaModule();
  return native.loadVLMModel(
    modelPath,
    mmprojPath ?? '',
    modelId,
    modelName
  );
}

/**
 * Check if a VLM model is loaded
 *
 * Matches iOS: RunAnywhere.isVLMModelLoaded
 *
 * @returns Promise resolving to true if a VLM model is loaded
 */
export async function isVLMModelLoaded(): Promise<boolean> {
  if (!isNativeLlamaModuleAvailable()) {
    return false;
  }
  const native = requireNativeLlamaModule();
  return native.isVLMModelLoaded();
}

/**
 * Unload the currently loaded VLM model
 *
 * Matches iOS: RunAnywhere.unloadVLMModel()
 *
 * @returns Promise resolving to true if successful
 */
export async function unloadVLMModel(): Promise<boolean> {
  if (!isNativeLlamaModuleAvailable()) {
    return false;
  }
  const native = requireNativeLlamaModule();
  return native.unloadVLMModel();
}

/**
 * Simple API: Describe an image
 *
 * Matches iOS: RunAnywhere.describeImage(_:prompt:)
 *
 * @param image - VLM image input (filePath, rgbPixels, or base64)
 * @param prompt - Optional prompt (default: "What's in this image?")
 * @returns Promise resolving to description text
 */
export async function describeImage(
  image: VLMImage,
  prompt: string = "What's in this image?"
): Promise<string> {
  const result = await processImage(image, prompt);
  return result.text;
}

/**
 * Simple API: Ask a question about an image
 *
 * Matches iOS: RunAnywhere.askAboutImage(_:image:)
 *
 * @param question - Question to ask about the image
 * @param image - VLM image input
 * @returns Promise resolving to answer text
 */
export async function askAboutImage(
  question: string,
  image: VLMImage
): Promise<string> {
  const result = await processImage(image, question);
  return result.text;
}

/**
 * Process an image with full options and metrics
 *
 * Matches iOS: RunAnywhere.processImage(_:prompt:maxTokens:temperature:topP:)
 *
 * @param image - VLM image input (filePath, rgbPixels, or base64)
 * @param prompt - Text prompt for the VLM
 * @param options - Generation options (maxTokens, temperature, topP)
 * @returns Promise resolving to VLMResult with text and metrics
 */
export async function processImage(
  image: VLMImage,
  prompt: string,
  options?: VLMGenerationOptions
): Promise<VLMResult> {
  if (!isNativeLlamaModuleAvailable()) {
    throw new Error('Native Llama module not available');
  }
  const native = requireNativeLlamaModule();

  // Convert VLMImage to native format
  const { imageFormat, imageData, imageWidth, imageHeight } =
    convertVLMImageToNative(image);

  // Build options JSON
  const optionsJson = JSON.stringify({
    max_tokens: options?.maxTokens ?? 2048,
    temperature: options?.temperature ?? 0.7,
    top_p: options?.topP ?? 0.9,
  });

  const resultJson = await native.processVLMImage(
    imageFormat,
    imageData,
    imageWidth,
    imageHeight,
    prompt,
    optionsJson
  );

  try {
    const result = JSON.parse(resultJson);
    return {
      text: result.text ?? '',
      promptTokens: result.prompt_tokens ?? 0,
      completionTokens: result.completion_tokens ?? 0,
      totalTimeMs: result.total_time_ms ?? 0,
      tokensPerSecond: result.tokens_per_second ?? 0,
    };
  } catch {
    if (resultJson.includes('error')) {
      throw new Error(resultJson);
    }
    return {
      text: resultJson,
      promptTokens: 0,
      completionTokens: 0,
      totalTimeMs: 0,
      tokensPerSecond: 0,
    };
  }
}

/**
 * Stream image processing with real-time tokens
 *
 * Returns a VLMStreamingResult containing:
 * - stream: AsyncIterable<string> for consuming tokens
 * - result: Promise<VLMResult> for final metrics
 * - cancel: Function to cancel generation
 *
 * Matches iOS: RunAnywhere.processImageStream(_:prompt:maxTokens:temperature:topP:)
 *
 * Example usage:
 * ```typescript
 * const streaming = await processImageStream(image, prompt);
 *
 * // Display tokens in real-time
 * for await (const token of streaming.stream) {
 *   console.log(token);
 * }
 *
 * // Get complete analytics after streaming finishes
 * const metrics = await streaming.result;
 * console.log(`Speed: ${metrics.tokensPerSecond} tok/s`);
 * ```
 */
export async function processImageStream(
  image: VLMImage,
  prompt: string,
  options?: VLMGenerationOptions
): Promise<VLMStreamingResult> {
  if (!isNativeLlamaModuleAvailable()) {
    throw new Error('Native Llama module not available');
  }

  const native = requireNativeLlamaModule();
  const startTime = Date.now();
  let firstTokenTime: number | null = null;
  let cancelled = false;
  let fullText = '';
  let tokenCount = 0;
  let resolveResult: ((result: VLMResult) => void) | null = null;
  let rejectResult: ((error: Error) => void) | null = null;

  // Convert VLMImage to native format
  const { imageFormat, imageData, imageWidth, imageHeight } =
    convertVLMImageToNative(image);

  // Build options JSON
  const optionsJson = JSON.stringify({
    max_tokens: options?.maxTokens ?? 2048,
    temperature: options?.temperature ?? 0.7,
    top_p: options?.topP ?? 0.9,
  });

  // Create the result promise
  const resultPromise = new Promise<VLMResult>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });

  // Create async generator for tokens
  async function* tokenGenerator(): AsyncGenerator<string> {
    const tokenQueue: string[] = [];
    let resolver: ((value: IteratorResult<string>) => void) | null = null;
    let done = false;
    let error: Error | null = null;

    // Start streaming
    native
      .processVLMImageStream(
        imageFormat,
        imageData,
        imageWidth,
        imageHeight,
        prompt,
        optionsJson,
        (token: string, isComplete: boolean) => {
          if (cancelled) return;

          if (!isComplete && token) {
            // Track first token time
            if (firstTokenTime === null) {
              firstTokenTime = Date.now();
            }

            fullText += token;
            tokenCount++;

            if (resolver) {
              resolver({ value: token, done: false });
              resolver = null;
            } else {
              tokenQueue.push(token);
            }
          }

          if (isComplete) {
            done = true;

            // Build final result
            const endTime = Date.now();
            const latencyMs = endTime - startTime;
            const timeToFirstTokenMs = firstTokenTime
              ? firstTokenTime - startTime
              : undefined;
            const tokensPerSecond =
              latencyMs > 0 ? (tokenCount / latencyMs) * 1000 : 0;

            const finalResult: VLMResult = {
              text: fullText,
              promptTokens: Math.ceil(prompt.length / 4),
              completionTokens: tokenCount,
              totalTimeMs: latencyMs,
              tokensPerSecond,
            };

            if (resolveResult) {
              resolveResult(finalResult);
            }

            if (resolver) {
              resolver({ value: undefined as unknown as string, done: true });
              resolver = null;
            }
          }
        }
      )
      .catch((err: Error) => {
        error = err;
        done = true;
        if (rejectResult) {
          rejectResult(err);
        }
        if (resolver) {
          resolver({ value: undefined as unknown as string, done: true });
        }
      });

    // Yield tokens
    while (!done || tokenQueue.length > 0) {
      if (tokenQueue.length > 0) {
        yield tokenQueue.shift()!;
      } else if (!done) {
        const result = await new Promise<IteratorResult<string>>((resolve) => {
          resolver = resolve;
        });
        if (result.done) break;
        yield result.value;
      }
    }

    if (error) {
      throw error;
    }
  }

  // Cancel function
  const cancel = (): void => {
    cancelled = true;
    cancelVLMGeneration();
  };

  return {
    stream: tokenGenerator(),
    result: resultPromise,
    cancel,
  };
}

/**
 * Cancel ongoing VLM generation
 *
 * Matches iOS: RunAnywhere.cancelVLMGeneration()
 */
export function cancelVLMGeneration(): void {
  if (!isNativeLlamaModuleAvailable()) {
    return;
  }
  const native = requireNativeLlamaModule();
  native.cancelVLMGeneration();
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Convert VLMImage discriminated union to native parameters
 * @internal
 */
function convertVLMImageToNative(image: VLMImage): {
  imageFormat: number;
  imageData: string;
  imageWidth: number;
  imageHeight: number;
} {
  switch (image.format) {
    case VLMImageFormat.FilePath:
      return {
        imageFormat: VLMImageFormat.FilePath,
        imageData: image.filePath,
        imageWidth: 0,
        imageHeight: 0,
      };

    case VLMImageFormat.RGBPixels:
      // Convert Uint8Array to base64 string for bridge crossing
      const base64Data = uint8ArrayToBase64(image.data);
      return {
        imageFormat: VLMImageFormat.RGBPixels,
        imageData: base64Data,
        imageWidth: image.width,
        imageHeight: image.height,
      };

    case VLMImageFormat.Base64:
      return {
        imageFormat: VLMImageFormat.Base64,
        imageData: image.base64,
        imageWidth: 0,
        imageHeight: 0,
      };

    default:
      throw new Error(`Unknown VLM image format: ${(image as VLMImage).format}`);
  }
}

/**
 * Convert Uint8Array to base64 string
 * @internal
 */
function uint8ArrayToBase64(bytes: Uint8Array): string {
  // Use btoa with binary string conversion
  let binaryString = '';
  for (let i = 0; i < bytes.length; i++) {
    binaryString += String.fromCharCode(bytes[i]);
  }
  return btoa(binaryString);
}
