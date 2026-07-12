import { RunAnywhere } from '@runanywhere/core';
import {
  ModelCategory,
  ModelLoadRequest,
} from '@runanywhere/proto-ts/model_types';
import {
  VLMGenerationOptions,
  VLMImage,
  VLMImageFormat,
} from '@runanywhere/proto-ts/vlm_options';
import { isModelLoadedForCategory } from '../utils/runAnywhereLifecycle';

export class VLMService {
  /**
   * Load the model and track internal state
   */
  async loadModel(modelId: string, modelName?: string): Promise<void> {
    try {
      // eslint-disable-next-line no-console -- demo VLM lifecycle diagnostic
      console.log(`[VLMService] Loading model: ${modelName ?? modelId}`);

      const result = await RunAnywhere.loadModel(
        ModelLoadRequest.fromPartial({
          modelId,
          category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
          forceReload: false,
          validateAvailability: true,
        })
      );
      const success = result.success;

      if (success) {
        // eslint-disable-next-line no-console -- demo VLM lifecycle diagnostic
        console.log('[VLMService] Load success');
      } else {
        throw new Error('SDK returned failure for model load');
      }
    } catch (error) {
      console.error('[VLMService] Load failed:', error);
      throw error;
    }
  }

  /**
   * Check if model is loaded through the SDK lifecycle state.
   */
  async isModelLoaded(): Promise<boolean> {
    try {
      return await isModelLoadedForCategory(
        ModelCategory.MODEL_CATEGORY_MULTIMODAL
      );
    } catch {
      return false;
    }
  }

  /**
   * Process an image with streaming results.
   */
  async processImage(
    imagePath: string,
    prompt: string,
    maxTokens: number,
    onToken: (token: string) => void
  ): Promise<void> {
    if (!(await this.isModelLoaded())) {
      throw new Error('Model not loaded. Please select a model first.');
    }

    const image = VLMImage.fromPartial({
      format: VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH,
      filePath: imagePath,
      width: 0,
      height: 0,
      sizeBytes: 0,
      metadata: {},
    });

    // eslint-disable-next-line no-console -- demo VLM inference diagnostic
    console.log(`[VLMService] Processing image: ${imagePath}`);

    try {
      const stream = await RunAnywhere.processImageStream(
        image,
        VLMGenerationOptions.fromPartial({
          prompt,
          maxTokens,
          streamingEnabled: true,
        })
      );

      // Manual async iteration — Hermes doesn't recognise NitroModules async iterables with for-await
      const iter = stream[Symbol.asyncIterator]();
      let result = await iter.next();
      while (!result.done) {
        const event = result.value;
        if (event.token) {
          onToken(event.token);
        }
        if (event.result) {
          break;
        }
        result = await iter.next();
      }
    } catch (error) {
      console.error('[VLMService] Processing error:', error);
      throw error;
    }
  }

  cancel(): void {
    RunAnywhere.cancelVLMGeneration();
  }

  release(): void {
    // eslint-disable-next-line no-console -- demo VLM lifecycle diagnostic
    console.log('[VLMService] Service state released');
  }
}
