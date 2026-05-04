/**
 * RunAnywhere+VisionLanguage.ts
 *
 * Vision Language Model (VLM) extension for the RunAnywhere core SDK.
 * Renamed from RunAnywhere+VLM.ts (Wave 3) to match Swift canonical name.
 * Aligned to proto-canonical VLM shapes (`@runanywhere/proto-ts/vlm_options`).
 *
 * The actual backend dispatch lives in `@runanywhere/llamacpp` (optional
 * peer dep); this file forwards to it dynamically so core remains
 * backend-agnostic.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VLM/RunAnywhere+VisionLanguage.swift
 */

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { ModelRegistry } from '../../services/ModelRegistry';
import { FileSystem } from '../../services/FileSystem';
import type {
  VLMImage,
  VLMResult,
  VLMGenerationOptions,
} from '@runanywhere/proto-ts/vlm_options';

const logger = new SDKLogger('RunAnywhere.VLM');

/**
 * RN-local streaming wrapper. The proto `VLMResult` carries final
 * metrics; the streaming surface adds `stream` (token AsyncIterable) and
 * `cancel`. Same shape as `LLMStreamingResult`.
 */
export interface VLMStreamingResult {
  stream: AsyncIterable<string>;
  result: Promise<VLMResult>;
  cancel: () => void;
}

/**
 * Minimal structural interface for the `@runanywhere/llamacpp` module surface
 * used by this VLM extension. Keeps the dynamic-require typed without pulling
 * the full backend package into the core type graph (it is an optional dep).
 */
interface VLMModule {
  registerVLMBackend(): boolean | Promise<boolean>;
  loadVLMModel(
    modelPath: string,
    mmprojPath?: string,
    modelId?: string,
    modelName?: string
  ): boolean | Promise<boolean>;
  isVLMModelLoaded(): boolean | Promise<boolean>;
  unloadVLMModel(): boolean | Promise<boolean>;
  describeImage(image: VLMImage, prompt?: string): string | Promise<string>;
  askAboutImage(question: string, image: VLMImage): string | Promise<string>;
  processImage(
    image: VLMImage,
    prompt: string,
    options?: Partial<VLMGenerationOptions>
  ): VLMResult | Promise<VLMResult>;
  processImageStream(
    image: VLMImage,
    prompt: string,
    options?: Partial<VLMGenerationOptions>
  ): VLMStreamingResult | Promise<VLMStreamingResult>;
  cancelVLMGeneration(): void;
}

let _vlmModule: VLMModule | null = null;

async function getVLMModule(): Promise<VLMModule> {
  if (_vlmModule) return _vlmModule;
  try {
    // Optional peer dep: loaded dynamically so core doesn't require it.
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    _vlmModule = require('@runanywhere/llamacpp') as VLMModule;
    return _vlmModule;
  } catch {
    throw new Error(
      'VLM requires @runanywhere/llamacpp package. Install it to use VLM features.'
    );
  }
}

/**
 * Register VLM backend.
 *
 * Matches iOS: auto-registered, but explicit in RN.
 */
export async function registerVLMBackend(): Promise<boolean> {
  const vlm = await getVLMModule();
  return vlm.registerVLMBackend();
}

/**
 * Load a VLM model by providing paths directly.
 *
 * Matches iOS: `RunAnywhere.loadVLMModel(_:mmprojPath:modelId:modelName:)`.
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
 * Matches iOS: `RunAnywhere.loadVLMModelById(_:)`.
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

/** Whether a VLM model is loaded. */
export async function isVLMModelLoaded(): Promise<boolean> {
  try {
    const vlm = await getVLMModule();
    return vlm.isVLMModelLoaded();
  } catch {
    return false;
  }
}

/** Unload the currently loaded VLM model. */
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
 * Matches iOS: `RunAnywhere.describeImage(_:prompt:)`.
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
 * Matches iOS: `RunAnywhere.askAboutImage(_:image:)`.
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
 * Matches iOS: `RunAnywhere.processImage(_:prompt:maxTokens:temperature:topP:)`.
 */
export async function processImage(
  image: VLMImage,
  prompt: string,
  options?: Partial<VLMGenerationOptions>
): Promise<VLMResult> {
  const vlm = await getVLMModule();
  return vlm.processImage(image, prompt, options);
}

/**
 * Stream image processing with real-time tokens.
 *
 * Matches iOS: `RunAnywhere.processImageStream(_:prompt:maxTokens:temperature:topP:)`.
 */
export async function processImageStream(
  image: VLMImage,
  prompt: string,
  options?: Partial<VLMGenerationOptions>
): Promise<VLMStreamingResult> {
  const vlm = await getVLMModule();
  return vlm.processImageStream(image, prompt, options);
}

/**
 * Cancel ongoing VLM generation.
 *
 * Matches iOS: `RunAnywhere.cancelVLMGeneration()`.
 */
export function cancelVLMGeneration(): void {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const vlm = require('@runanywhere/llamacpp') as VLMModule;
    vlm.cancelVLMGeneration();
  } catch {
    // Silently ignore if llamacpp not available.
  }
}
