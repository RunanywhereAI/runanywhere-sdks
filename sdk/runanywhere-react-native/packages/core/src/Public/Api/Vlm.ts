/**
 * `RunAnywhere.vlm` — generation grounded in an image.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  VLMGenerationRequest,
  VLMResult,
  VLMStreamEvent,
  VLMStreamEventKind,
} from '@runanywhere/proto-ts/vlm_options';

import { SDKException } from '../../Foundation/Errors/SDKException';
import { requireInitialized } from '../../Foundation/Initialization/InitializedGuard';
import { decode, decodeEvent, encode, nextRequestId, preflight } from './Bridge';
import { toVlmImage } from './Inputs';
import { ensureModelLoaded } from './Models';
import { toVlmOptions } from './Options';
import {
  emptyGenerationResult,
  toGenerationResultFromVlm,
} from './Results';
import { pushStream } from './Stream';
import type {
  GenerationEvent,
  GenerationResult,
  ImageInput,
  LlmOptions,
} from './Types';

async function buildRequest(
  image: ImageInput,
  prompt: string,
  options: LlmOptions | undefined,
  requestId: string
): Promise<ArrayBuffer> {
  if (options?.model) {
    await ensureModelLoaded(
      options.model,
      ModelCategory.MODEL_CATEGORY_VISION
    );
  }
  const request = VLMGenerationRequest.fromPartial({
    requestId,
    images: [toVlmImage(image)],
    options: toVlmOptions(prompt, options),
  });
  return encode(request, VLMGenerationRequest);
}

/** Vision-language generation over a single image. */
export const vlm = {
  /**
   * Answer `prompt` about `image`.
   *
   * @example
   * const result = await RunAnywhere.vlm.generate(ImageInputs.file(path), 'What is in this photo?');
   * console.log(result.text);
   *
   * @throws SDKException when no vision model is available or generation fails.
   */
  async generate(
    image: ImageInput,
    prompt: string,
    options?: LlmOptions
  ): Promise<GenerationResult> {
    const native = await preflight();
    const requestId = nextRequestId('vlm');
    const resultBytes = await native.vlmProcessProto(
      await buildRequest(image, prompt, options, requestId)
    );
    return toGenerationResultFromVlm(
      decode(resultBytes, VLMResult, 'vlmProcess'),
      requestId,
      options?.model ?? ''
    );
  },

  /**
   * Stream an answer about `image` as `started`, token deltas, then `completed`.
   *
   * @throws SDKException into the consumer when generation fails in flight.
   */
  generateStream(
    image: ImageInput,
    prompt: string,
    options?: LlmOptions
  ): AsyncIterable<GenerationEvent> {
    requireInitialized();
    const requestId = nextRequestId('vlm');
    const model = options?.model ?? '';
    let cancel: (() => Promise<void>) | null = null;

    return pushStream<GenerationEvent>(
      async (controller) => {
        const native = await preflight();
        const requestBytes = await buildRequest(
          image,
          prompt,
          options,
          requestId
        );
        cancel = async () => {
          await native.vlmCancelProto().catch(() => undefined);
        };
        controller.push({ type: 'started', requestId });

        void native
          .vlmProcessStreamProto(requestBytes, (eventBytes: ArrayBuffer) => {
            const event = decodeEvent(eventBytes, VLMStreamEvent);
            if (event.error) {
              controller.fail(new SDKException(event.error));
              return;
            }
            if (event.token.length > 0) {
              controller.push({
                type: 'token',
                text: event.token,
                kind: 'text',
              });
            }
            const isTerminal =
              event.kind === VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED ||
              event.isFinal ||
              event.result !== undefined;
            if (isTerminal) {
              controller.push({
                type: 'completed',
                result: event.result
                  ? toGenerationResultFromVlm(event.result, requestId, model)
                  : emptyGenerationResult(requestId, model),
              });
              controller.finish();
            }
          })
          .then(() => controller.finish())
          .catch((error: Error) => controller.fail(error));
      },
      async () => {
        await cancel?.();
      }
    );
  },
};
