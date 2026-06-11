/**
 * RunAnywhere+VisionLanguage.ts
 *
 * Public VLM namespace matching Swift's RunAnywhere+VisionLanguage. The Web
 * implementation delegates to a backend-installed provider so app code never
 * imports backend worker bridges directly.
 */

import type {
  VLMGenerationOptions,
  VLMImage,
  VLMResult,
} from '@runanywhere/proto-ts/vlm_options';
import { VLMModelFamily } from '@runanywhere/proto-ts/vlm_options';
import {
  ModelCategory,
  type CurrentModelResult,
} from '@runanywhere/proto-ts/model_types';
import type { SDKEvent } from '@runanywhere/proto-ts/sdk_events';
import { SDKException } from '../../Foundation/SDKException';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle';

export interface VisionLanguageProvider {
  readonly isInitialized: boolean;
  readonly isModelLoaded: boolean;
  loadCurrentModel?(currentModel: CurrentModelResult): Promise<void>;
  unloadModel?(): Promise<void>;
  processImage(image: VLMImage, options: VLMGenerationOptions): Promise<VLMResult>;
  processImageStream?(image: VLMImage, options: VLMGenerationOptions): Promise<AsyncIterable<SDKEvent>>;
  cancelVLMGeneration(): Promise<void> | void;
}

let provider: VisionLanguageProvider | null = null;

export function setVisionLanguageProvider(next: VisionLanguageProvider | null): void {
  provider = next;
}

function requireProvider(feature: string): VisionLanguageProvider {
  if (provider) return provider;
  throw SDKException.backendNotAvailable(
    feature,
    'No Web vision-language provider is registered. Call LlamaCPP.register() first.',
  );
}

export const VisionLanguage = {
  get isInitialized(): boolean {
    return provider?.isInitialized ?? false;
  },

  get isModelLoaded(): boolean {
    return provider?.isModelLoaded ?? false;
  },

  async loadCurrentModel(): Promise<void> {
    const current =
      WebModelLifecycle.currentModel({
        category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        includeModelMetadata: true,
      }) ??
      WebModelLifecycle.currentModel({ includeModelMetadata: true });

    if (!current?.modelId) {
      // Swift parity: RunAnywhere+VisionLanguage.swift:40 throws `.notInitialized` ("VLM model not loaded").
      throw SDKException.notInitialized(
        'No VLM model is loaded. Call RunAnywhere.loadModel(...) with a multimodal model before RunAnywhere.processImage().',
      );
    }

    const active = requireProvider('visionLanguage.loadCurrentModel');
    if (!active.loadCurrentModel) {
      throw SDKException.backendNotAvailable(
        'visionLanguage.loadCurrentModel',
        'The active Web vision-language provider cannot load C++ lifecycle resolved artifacts.',
      );
    }
    await active.loadCurrentModel(current);
  },

  async unloadModel(): Promise<void> {
    const active = requireProvider('visionLanguage.unloadModel');
    if (!active.unloadModel) return;
    await active.unloadModel();
  },

  processImage(image: VLMImage, options: VLMGenerationOptions): Promise<VLMResult> {
    return requireProvider('visionLanguage.processImage').processImage(
      image,
      normalizeVLMGenerationOptions(options, false),
    );
  },

  async processImageStream(
    image: VLMImage,
    options: VLMGenerationOptions,
  ): Promise<AsyncIterable<SDKEvent>> {
    const active = requireProvider('visionLanguage.processImageStream');
    if (!active.processImageStream) {
      throw SDKException.backendNotAvailable(
        'visionLanguage.processImageStream',
        'The active Web vision-language provider does not expose streaming.',
      );
    }
    return active.processImageStream(image, normalizeVLMGenerationOptions(options, true));
  },

  async cancelVLMGeneration(): Promise<void> {
    await requireProvider('visionLanguage.cancelVLMGeneration').cancelVLMGeneration();
  },
};

export type VisionLanguageCapability = typeof VisionLanguage;

function normalizeVLMGenerationOptions(
  options: VLMGenerationOptions,
  streamingEnabled: boolean,
): VLMGenerationOptions {
  // Defaults mirror Swift `RAVLMGenerationOptions.defaults()`
  // (RAVLMImage+Helpers.swift:25-33): maxTokens 256, temperature 0.7,
  // topP 0.9, topK 40. Normalize only when unset/<=0.
  return {
    prompt: options.prompt ?? '',
    maxTokens: options.maxTokens > 0 ? options.maxTokens : 256,
    temperature: options.temperature > 0 ? options.temperature : 0.7,
    topP: options.topP > 0 ? options.topP : 0.9,
    topK: options.topK > 0 ? options.topK : 40,
    stopSequences: options.stopSequences ?? [],
    streamingEnabled,
    systemPrompt: options.systemPrompt,
    maxImageSize: options.maxImageSize ?? 0,
    nThreads: options.nThreads ?? 0,
    useGpu: options.useGpu ?? true,
    modelFamily: options.modelFamily || VLMModelFamily.VLM_MODEL_FAMILY_AUTO,
    customChatTemplate: options.customChatTemplate,
    imageMarkerOverride: options.imageMarkerOverride,
    seed: options.seed ?? 0,
    repetitionPenalty: options.repetitionPenalty > 0 ? options.repetitionPenalty : 1,
    minP: options.minP ?? 0,
    emitImageEmbeddings: options.emitImageEmbeddings ?? false,
  };
}
