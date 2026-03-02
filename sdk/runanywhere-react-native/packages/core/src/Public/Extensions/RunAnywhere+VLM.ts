/**
 * RunAnywhere+VLM.ts
 *
 * Vision Language Model (VLM) extension for the RunAnywhere core SDK.
 * Dynamically imports from @runanywhere/llamacpp (optional dependency)
 * so VLM methods are accessible via RunAnywhere.* — matching iOS pattern.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VLM/RunAnywhere+VisionLanguage.swift
 */

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { ModelRegistry } from '../../services/ModelRegistry';
import { FileSystem } from '../../services/FileSystem';
import type {
  VLMImage,
  VLMResult,
  VLMStreamingResult,
  VLMGenerationOptions,
} from '../../types/VLMTypes';

const logger = new SDKLogger('RunAnywhere.VLM');

type VLMModule = typeof import('../../../llamacpp/src/RunAnywhere+VLM');

let _vlmModule: VLMModule | null = null;

async function getVLMModule(): Promise<VLMModule> {
  if (_vlmModule) return _vlmModule;
  try {
    _vlmModule = require('@runanywhere/llamacpp');
    return _vlmModule!;
  } catch {
    throw new Error(
      'VLM requires @runanywhere/llamacpp package. Install it to use VLM features.'
    );
  }
}

/**
 * Register VLM backend.
 * Matches iOS: auto-registered, but explicit in RN.
 */
export async function registerVLMBackend(): Promise<boolean> {
  const vlm = await getVLMModule();
  return vlm.registerVLMBackend();
}

/**
 * Load a VLM model by providing paths directly.
 *
 * Matches iOS: RunAnywhere.loadVLMModel(_:mmprojPath:modelId:modelName:)
 */
export async function loadVLMModel(
  modelPath: string,
  mmprojPath?: string,
  modelId?: string,
  modelName?: string
): Promise<boolean> {
  const vlm = await getVLMModule();
  return vlm.loadVLMModel(modelPath, mmprojPath, modelId, modelName);
}

/**
 * Load a VLM model by its registered model ID.
 * Automatically resolves the model path and mmproj path from the registry.
 *
 * Matches iOS: RunAnywhere.loadVLMModelById(_:)
 */
export async function loadVLMModelById(modelId: string): Promise<boolean> {
  const modelInfo = await ModelRegistry.getModel(modelId);
  if (!modelInfo) {
    throw new Error(`VLM model not found in registry: ${modelId}`);
  }

  if (!modelInfo.localPath) {
    throw new Error(`VLM model not downloaded: ${modelId}`);
  }

  let mmprojPath: string | undefined;
  try {
    mmprojPath = await FileSystem.findMmprojForModel(modelInfo.localPath);
  } catch {
    logger.debug(`No mmproj found for ${modelId}, backend will auto-detect`);
  }

  return loadVLMModel(modelInfo.localPath, mmprojPath, modelId, modelInfo.name);
}

/**
 * Check if a VLM model is loaded.
 *
 * Matches iOS: RunAnywhere.isVLMModelLoaded
 */
export async function isVLMModelLoaded(): Promise<boolean> {
  try {
    const vlm = await getVLMModule();
    return vlm.isVLMModelLoaded();
  } catch {
    return false;
  }
}

/**
 * Unload the currently loaded VLM model.
 *
 * Matches iOS: RunAnywhere.unloadVLMModel()
 */
export async function unloadVLMModel(): Promise<boolean> {
  try {
    const vlm = await getVLMModule();
    return vlm.unloadVLMModel();
  } catch {
    return false;
  }
}

/**
 * Describe an image with an optional prompt.
 *
 * Matches iOS: RunAnywhere.describeImage(_:prompt:)
 */
export async function describeImage(
  image: VLMImage,
  prompt?: string
): Promise<string> {
  const vlm = await getVLMModule();
  return vlm.describeImage(image, prompt);
}

/**
 * Ask a question about an image.
 *
 * Matches iOS: RunAnywhere.askAboutImage(_:image:)
 */
export async function askAboutImage(
  question: string,
  image: VLMImage
): Promise<string> {
  const vlm = await getVLMModule();
  return vlm.askAboutImage(question, image);
}

/**
 * Process an image with full options and metrics.
 *
 * Matches iOS: RunAnywhere.processImage(_:prompt:maxTokens:temperature:topP:)
 */
export async function processImage(
  image: VLMImage,
  prompt: string,
  options?: VLMGenerationOptions
): Promise<VLMResult> {
  const vlm = await getVLMModule();
  return vlm.processImage(image, prompt, options);
}

/**
 * Stream image processing with real-time tokens.
 *
 * Matches iOS: RunAnywhere.processImageStream(_:prompt:maxTokens:temperature:topP:)
 */
export async function processImageStream(
  image: VLMImage,
  prompt: string,
  options?: VLMGenerationOptions
): Promise<VLMStreamingResult> {
  const vlm = await getVLMModule();
  return vlm.processImageStream(image, prompt, options);
}

/**
 * Cancel ongoing VLM generation.
 *
 * Matches iOS: RunAnywhere.cancelVLMGeneration()
 */
export function cancelVLMGeneration(): void {
  try {
    const vlm = require('@runanywhere/llamacpp');
    vlm.cancelVLMGeneration();
  } catch {
    // Silently ignore if llamacpp not available
  }
}
