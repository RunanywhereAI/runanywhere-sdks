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
import {
  ModelCategory,
  type CurrentModelResult,
} from '@runanywhere/proto-ts/model_types';
import type { SDKEvent } from '@runanywhere/proto-ts/sdk_events';
import { SDKException } from '../../Foundation/SDKException';
import { ModelLifecycle } from './RunAnywhere+ModelLifecycle';

export interface VisionLanguageLoadModelRequest {
  modelId: string;
  modelName: string;
  modelFilename: string;
  mmprojFilename: string;
  modelData: ArrayBuffer;
  mmprojData: ArrayBuffer;
}

export interface VisionLanguageProvider {
  readonly isInitialized: boolean;
  readonly isModelLoaded: boolean;
  loadModel?(request: VisionLanguageLoadModelRequest): Promise<void>;
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

  async loadModel(request: VisionLanguageLoadModelRequest): Promise<void> {
    const active = requireProvider('visionLanguage.loadModel');
    if (!active.loadModel) {
      throw SDKException.backendNotAvailable(
        'visionLanguage.loadModel',
        'The active Web vision-language provider does not expose model loading.',
      );
    }
    await active.loadModel(request);
  },

  async loadCurrentModel(): Promise<void> {
    const current =
      ModelLifecycle.currentModel({
        category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        includeModelMetadata: true,
      }) ??
      ModelLifecycle.currentModel({ includeModelMetadata: true });

    if (!current?.modelId) {
      throw SDKException.componentNotReady(
        'vlm',
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
    return requireProvider('visionLanguage.processImage').processImage(image, options);
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
    return active.processImageStream(image, options);
  },

  async cancelVLMGeneration(): Promise<void> {
    await requireProvider('visionLanguage.cancelVLMGeneration').cancelVLMGeneration();
  },
};

export type VisionLanguageCapability = typeof VisionLanguage;
