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
import type { SDKEvent } from '@runanywhere/proto-ts/sdk_events';
import type {
  VLMGenerationOptions,
  VLMImage,
  VLMResult,
} from '@runanywhere/proto-ts/vlm_options';

export class LifecycleVLMProvider implements VisionLanguageProvider {
  private _modelLoaded = false;

  get isInitialized(): boolean {
    return VLMProtoAdapter.tryDefault()?.supportsProtoVLM() ?? false;
  }

  get isModelLoaded(): boolean {
    return this._modelLoaded;
  }

  async loadCurrentModel(currentModel: CurrentModelResult): Promise<void> {
    if (!currentModel.modelId) {
      throw SDKException.componentNotReady(
        'vlm',
        'No C++ lifecycle VLM model is loaded.',
      );
    }
    this._modelLoaded = true;
  }

  async unloadModel(): Promise<void> {
    this._modelLoaded = false;
  }

  async processImage(
    image: VLMImage,
    options: VLMGenerationOptions,
  ): Promise<VLMResult> {
    if (!this._modelLoaded) {
      throw SDKException.componentNotReady(
        'vlm',
        'No VLM model has been loaded through RunAnywhere.loadModel().',
      );
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
      throw SDKException.generationFailed('Native VLM proto path returned no result.');
    }
    return result;
  }

  async processImageStream(
    image: VLMImage,
    options: VLMGenerationOptions,
  ): Promise<AsyncIterable<SDKEvent>> {
    if (!this._modelLoaded) {
      throw SDKException.componentNotReady(
        'vlm',
        'No VLM model has been loaded through RunAnywhere.loadModel().',
      );
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
