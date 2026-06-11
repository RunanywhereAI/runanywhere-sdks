/**
 * LifecycleVLMProvider
 *
 * Swift-shaped VLM provider for Web: after RunAnywhere.loadModel() selects a
 * multimodal model through the shared C++ lifecycle, VLM inference calls the
 * same proto ABI on the already-registered main WASM module. No JS-side model
 * routing or second worker-owned lifecycle is required.
 */

import {
  SDKException,
  VLMProtoAdapter,
  type VisionLanguageProvider,
} from '@runanywhere/web/internal';
import type { CurrentModelResult } from '@runanywhere/proto-ts/model_types';
import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import type { SDKEvent } from '@runanywhere/proto-ts/sdk_events';
import type {
  VLMGenerationOptions,
  VLMImage,
  VLMResult,
} from '@runanywhere/proto-ts/vlm_options';

function isVisionModelCategory(category: ModelCategory | undefined): boolean {
  return (
    category === ModelCategory.MODEL_CATEGORY_MULTIMODAL ||
    category === ModelCategory.MODEL_CATEGORY_VISION
  );
}

export class LifecycleVLMProvider implements VisionLanguageProvider {
  private _modelLoaded = false;
  private _loadedModelId: string | null = null;

  get isInitialized(): boolean {
    return VLMProtoAdapter.tryDefault()?.supportsProtoVLM() ?? false;
  }

  get isModelLoaded(): boolean {
    return this._modelLoaded;
  }

  get loadedModelId(): string | null {
    return this._loadedModelId;
  }

  async loadCurrentModel(currentModel: CurrentModelResult): Promise<void> {
    if (!currentModel.modelId) {
      // Swift parity: VLM model-guards throw `.notInitialized` ("VLM model not
      // loaded", RunAnywhere+VisionLanguage.swift:40).
      throw SDKException.notInitialized('No C++ lifecycle VLM model is loaded.');
    }
    // Mirror iOS LlamaCPPVLMProvider: gate on MULTIMODAL/VISION category so an
    // accidental LLM/STT/TTS load doesn't flip the VLM gate.
    if (!isVisionModelCategory(currentModel.category)) {
      // Swift taxonomy: wrong-state calls throw `.invalidState`.
      throw SDKException.invalidState(
        `Loaded model category (${currentModel.category}) is not MULTIMODAL/VISION; refusing to enable VLM gate.`,
      );
    }
    this._loadedModelId = currentModel.modelId;
    this._modelLoaded = true;
  }

  async unloadModel(): Promise<void> {
    this._modelLoaded = false;
    this._loadedModelId = null;
  }

  async processImage(
    image: VLMImage,
    options: VLMGenerationOptions,
  ): Promise<VLMResult> {
    if (!this._modelLoaded) {
      throw SDKException.notInitialized('No VLM model has been loaded through RunAnywhere.loadModel().');
    }

    const adapter = VLMProtoAdapter.tryDefault();
    if (!adapter?.supportsProtoVLM()) {
      throw SDKException.backendNotAvailable(
        'visionLanguage.processImage',
        'The active Web WASM module does not expose rac_vlm_*_proto exports.',
      );
    }

    const result = await adapter.processAsync(0, image, options);
    if (!result) {
      // Swift taxonomy: failed operations throw `.processingFailed`.
      throw SDKException.processingFailed('Native VLM proto path returned no result.');
    }
    return result;
  }

  async processImageStream(
    image: VLMImage,
    options: VLMGenerationOptions,
  ): Promise<AsyncIterable<SDKEvent>> {
    if (!this._modelLoaded) {
      throw SDKException.notInitialized('No VLM model has been loaded through RunAnywhere.loadModel().');
    }

    const adapter = VLMProtoAdapter.tryDefault();
    if (!adapter?.supportsProtoVLM()) {
      throw SDKException.backendNotAvailable(
        'visionLanguage.processImageStream',
        'The active Web WASM module does not expose rac_vlm_*_proto exports.',
      );
    }

    return adapter.streamEvents(0, image, options);
  }

  cancelVLMGeneration(): void {
    VLMProtoAdapter.tryDefault()?.cancel(0);
  }
}
