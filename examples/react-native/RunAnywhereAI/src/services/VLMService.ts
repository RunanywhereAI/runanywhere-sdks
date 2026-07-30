import { ImageInputs, RunAnywhere } from '@runanywhere/core';
import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { isModelLoadedForCategory } from '../utils/runAnywhereLifecycle';

export class VLMService {
  private active: AsyncIterator<unknown> | null = null;

  /** Load the vision model through the SDK lifecycle. */
  async loadModel(modelId: string, modelName?: string): Promise<void> {
    try {
      // eslint-disable-next-line no-console -- demo VLM lifecycle diagnostic
      console.log(`[VLMService] Loading model: ${modelName ?? modelId}`);
      await RunAnywhere.models.load(modelId);
      // eslint-disable-next-line no-console -- demo VLM lifecycle diagnostic
      console.log('[VLMService] Load success');
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

    // eslint-disable-next-line no-console -- demo VLM inference diagnostic
    console.log(`[VLMService] Processing image: ${imagePath}`);

    // Manual async iteration — Hermes doesn't recognise NitroModules async iterables with for-await
    const iterator = RunAnywhere.vlm
      .generateStream(ImageInputs.file(imagePath), prompt, {
        maxOutputTokens: maxTokens,
      })
      [Symbol.asyncIterator]();
    this.active = iterator;
    try {
      let step = await iterator.next();
      while (!step.done) {
        const event = step.value;
        if (event.type === 'token') {
          onToken(event.text);
        }
        if (event.type === 'completed') {
          break;
        }
        step = await iterator.next();
      }
    } catch (error) {
      console.error('[VLMService] Processing error:', error);
      throw error;
    } finally {
      this.active = null;
      await iterator.return?.();
    }
  }

  /** Cancel the in-flight generation by tearing its stream down. */
  cancel(): void {
    void this.active?.return?.();
    this.active = null;
  }

  release(): void {
    // eslint-disable-next-line no-console -- demo VLM lifecycle diagnostic
    console.log('[VLMService] Service state released');
  }
}
