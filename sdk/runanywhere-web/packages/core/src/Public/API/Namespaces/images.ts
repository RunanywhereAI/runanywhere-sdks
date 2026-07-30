/**
 * `RunAnywhere.images` — diffusion image generation, including inpainting.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { DiffusionStreamEventKind } from '@runanywhere/proto-ts/diffusion_options';
import { SDKException } from '../../../Foundation/SDKException.js';
import {
  cancelImageGeneration,
  generateImage,
  generateImageStream,
} from '../../Extensions/RunAnywhere+Diffusion.js';
import type { ImageOptions } from '../Options.js';
import type { ImageEvent } from '../Events.js';
import type { ImageResult } from '../Results.js';
import { toImageResult, toProtoImageOptions } from '../Mapping.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

async function ensureImageModel(): Promise<void> {
  await ensureReady();
  await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION);
}

/** Image generation against the resident diffusion model. */
export const images = {
  /**
   * Generate an image from a prompt; set `options.mode` to inpaint instead.
   *
   * @throws SDKException when no diffusion model is loaded.
   *
   * @example
   * const { images: rendered } = await RunAnywhere.images.generate('a tiny robot gardener');
   * canvas.src = URL.createObjectURL(new Blob([rendered[0].bytes]));
   */
  async generate(prompt: string, options?: ImageOptions): Promise<ImageResult> {
    await ensureImageModel();
    const protoOptions = toProtoImageOptions(prompt, options);
    const result = await generateImage(protoOptions);
    if (result.errorMessage) throw SDKException.processingFailed(result.errorMessage);
    return toImageResult(result, protoOptions.steps ?? 0);
  },

  /**
   * Generate an image, emitting `started`, per-step `progress`, and `completed`.
   *
   * @throws SDKException on preflight failure; in-flight failures throw into the consumer.
   */
  generateStream(prompt: string, options?: ImageOptions): AsyncIterable<ImageEvent> {
    return (async function* generation(): AsyncGenerator<ImageEvent> {
      await ensureImageModel();
      const protoOptions = toProtoImageOptions(prompt, options);
      const steps = protoOptions.steps ?? 0;
      let announced = false;
      let completed = false;
      try {
        for await (const event of generateImageStream(protoOptions)) {
          if (!('kind' in event)) {
            yield {
              type: 'progress',
              step: event.currentStep,
              totalSteps: event.totalSteps,
              partialImage: event.intermediateImageData,
            };
            continue;
          }
          if (event.kind === DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_ERROR) {
            throw SDKException.processingFailed(
              event.errorMessage || `Image generation failed with code ${event.errorCode}`,
            );
          }
          if (!announced) {
            announced = true;
            yield { type: 'started' };
          }
          if (event.progress) {
            yield {
              type: 'progress',
              step: event.progress.currentStep,
              totalSteps: event.progress.totalSteps,
              partialImage: event.progress.intermediateImageData,
            };
          }
          if (event.result) {
            completed = true;
            yield { type: 'completed', result: toImageResult(event.result, steps) };
          }
        }
      } finally {
        if (!completed) await cancelImageGeneration();
      }
    })();
  },
};
