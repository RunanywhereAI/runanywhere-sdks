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
  async loadModel(modelPath: string, mmprojPath?: string, modelName?: string): Promise<void> {
    try {
      console.log(`[VLMService] Loading model: ${modelName}`);
      
      // Pass 'undefined' for loraPath (3rd arg) as per SDK requirement
      const success = await sdkLoadModel(modelPath, mmprojPath, undefined, modelName);
      
      if (success) {
        this._isLoaded = true;
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
    } catch (e) {
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
      format: VLMImageFormat.FilePath,
      filePath: imagePath,
    };

    console.log(`[VLMService] Processing image: ${imagePath}`);
    
    try {
      const response = await processImageStream(image, prompt, { maxTokens });
      
      // Consume the async iterator and fire callback
      for await (const token of response.stream) {
        onToken(token);
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
    console.log('[VLMService] Service state released');
  }
}