import {
  processImageStream,
  loadVLMModel as sdkLoadModel,
  isVLMModelLoaded as sdkCheckLoaded,
  cancelVLMGeneration,
} from '@runanywhere/llamacpp';
import { VLMImageFormat, type VLMImage } from '@runanywhere/core';

export class VLMService {
  private _isLoaded: boolean = false;

  /**
   * Load the model and track internal state
   * Updated to accept modelName (3rd argument)
   */
  async loadModel(
    modelPath: string,
    mmprojPath?: string,
    modelName?: string
  ): Promise<void> {
    try {
      // eslint-disable-next-line no-console -- demo VLM lifecycle diagnostic
      console.log(`[VLMService] Loading model: ${modelName}`);

      // Pass 'undefined' for loraPath (3rd arg) as per SDK requirement
      const success = await sdkLoadModel(
        modelPath,
        mmprojPath,
        undefined,
        modelName
      );

      if (success) {
        this._isLoaded = true;
        // eslint-disable-next-line no-console -- demo VLM lifecycle diagnostic
        console.log('[VLMService] Load success');
      } else {
        this._isLoaded = false;
        throw new Error('SDK returned failure for model load');
      }
    } catch (error) {
      console.error('[VLMService] Load failed:', error);
      this._isLoaded = false;
      throw error;
    }
  }

  /**
   * Check if model is loaded (checks both internal flag and SDK)
   */
  async isModelLoaded(): Promise<boolean> {
    if (!this._isLoaded) return false;
    try {
      return await sdkCheckLoaded();
    } catch {
      return false;
    }
  }

  /**
   * Describe an image with streaming results
   */
  async describeImage(
    imagePath: string,
    prompt: string,
    maxTokens: number,
    onToken: (token: string) => void
  ): Promise<void> {
    if (!this._isLoaded) {
      throw new Error('Model not loaded. Please select a model first.');
    }

    const image: VLMImage = {
      format: VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH,
      filePath: imagePath,
      width: 0,
      height: 0,
    };

    // eslint-disable-next-line no-console -- demo VLM inference diagnostic
    console.log(`[VLMService] Processing image: ${imagePath}`);

    try {
      const response = await processImageStream(image, prompt, {
        prompt,
        maxTokens,
        temperature: 0.7,
        topP: 0.9,
        topK: 0,
      });

      // Manual async iteration — Hermes doesn't recognise NitroModules async iterables with for-await
      const iter = response.stream[Symbol.asyncIterator]();
      let result = await iter.next();
      while (!result.done) {
        onToken(result.value);
        result = await iter.next();
      }
    } catch (error) {
      console.error('[VLMService] Description error:', error);
      throw error;
    }
  }

  cancel(): void {
    cancelVLMGeneration();
  }

  release(): void {
    this._isLoaded = false;
    // eslint-disable-next-line no-console -- demo VLM lifecycle diagnostic
    console.log('[VLMService] Service state released');
  }
}
