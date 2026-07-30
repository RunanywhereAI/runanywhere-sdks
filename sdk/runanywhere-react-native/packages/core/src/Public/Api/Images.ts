/**
 * `RunAnywhere.images` — on-device diffusion.
 */

import {
  DiffusionGenerationRequest,
  DiffusionResult,
} from '@runanywhere/proto-ts/diffusion_options';

import { requireInitialized } from '../../Foundation/Initialization/InitializedGuard';
import { decode, encode, nextRequestId, preflight } from './Bridge';
import { toImageOptions } from './Options';
import { toImageResult } from './Results';
import { pushStream } from './Stream';
import type { ImageEvent, ImageOptions, ImageResult } from './Types';

function buildRequest(prompt: string, options?: ImageOptions): ArrayBuffer {
  return encode(
    DiffusionGenerationRequest.fromPartial({
      requestId: nextRequestId('image'),
      options: toImageOptions(prompt, options),
    }),
    DiffusionGenerationRequest
  );
}

/** Image generation and inpainting. */
export const images = {
  /**
   * Generate an image from `prompt`.
   *
   * @example
   * const result = await RunAnywhere.images.generate('a lighthouse at dusk');
   * const png = result.images[0]?.data;
   *
   * @throws SDKException when no diffusion model is loaded, the platform has no
   * diffusion backend, or generation fails.
   */
  async generate(
    prompt: string,
    options?: ImageOptions
  ): Promise<ImageResult> {
    const native = await preflight();
    const resultBytes = await native.diffusionGenerateLifecycleProto(
      buildRequest(prompt, options)
    );
    return toImageResult(decode(resultBytes, DiffusionResult, 'imagesGenerate'));
  },

  /**
   * Generate an image, reporting `started` then `completed`.
   *
   * Commons' diffusion stream kickoff is still a documented not-implemented
   * stub, so per-step `progress` events do not arrive yet; the image itself is
   * produced by the same lifecycle generate the one-shot verb uses.
   *
   * @throws SDKException into the consumer when generation fails in flight.
   */
  generateStream(
    prompt: string,
    options?: ImageOptions
  ): AsyncIterable<ImageEvent> {
    requireInitialized();
    let cancelled = false;

    return pushStream<ImageEvent>(
      async (controller) => {
        const native = await preflight();
        const requestBytes = buildRequest(prompt, options);
        controller.push({ type: 'started' });
        void native
          .diffusionGenerateLifecycleProto(requestBytes)
          .then((resultBytes: ArrayBuffer) => {
            if (cancelled) {
              controller.finish();
              return;
            }
            controller.push({
              type: 'completed',
              result: toImageResult(
                decode(resultBytes, DiffusionResult, 'imagesGenerateStream')
              ),
            });
            controller.finish();
          })
          .catch((error: Error) => controller.fail(error));
      },
      () => {
        cancelled = true;
      }
    );
  },
};
