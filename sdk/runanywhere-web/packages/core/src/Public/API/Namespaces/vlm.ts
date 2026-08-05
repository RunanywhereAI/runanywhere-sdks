/**
 * `RunAnywhere.vlm` — vision-language generation over an image and a prompt.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  VLMGenerationOptions as VLMGenerationOptionsMessage,
  VLMStreamEventKind,
  type VLMGenerationOptions,
} from '@runanywhere/proto-ts/vlm_options';
import { vLMGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/vlm_options_convenience';
import { SDKException } from '../../../Foundation/SDKException.js';
import { VisionLanguage } from '../../Extensions/RunAnywhere+VisionLanguage.js';
import type { ImageInput } from '../Inputs.js';
import type { LlmOptions } from '../Options.js';
import type { GenerationEvent } from '../Events.js';
import type { GenerationResult } from '../Results.js';
import { vlmToGenerationResult } from '../Mapping.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

function toProtoVlmOptions(prompt: string, options?: LlmOptions): VLMGenerationOptions {
  const defaults = vLMGenerationOptionsDefaults();
  return VLMGenerationOptionsMessage.fromPartial({
    prompt,
    maxOutputTokens: options?.maxOutputTokens ?? defaults.maxOutputTokens,
    temperature: options?.temperature ?? defaults.temperature,
    topP: options?.topP ?? defaults.topP,
    topK: options?.topK ?? defaults.topK,
    minP: options?.minP ?? defaults.minP,
    repetitionPenalty: options?.repetitionPenalty ?? defaults.repetitionPenalty,
    seed: options?.seed ?? defaults.seed,
    stopSequences: options?.stopSequences ?? defaults.stopSequences,
    systemPrompt: options?.systemPrompt,
  });
}

/**
 * Resolve the vision model. Both `multimodal` and `vision` catalog categories
 * collapse to one VLM component in commons, so a caller-named model is
 * resolved against whichever category the catalog assigned it.
 */
async function ensureVisionModel(model?: string): Promise<void> {
  await ensureReady();
  try {
    await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_MULTIMODAL, model);
  } catch (error) {
    if (!model) {
      await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_VISION);
      return;
    }
    throw error;
  }
  if (!VisionLanguage.isModelLoaded) await VisionLanguage.loadCurrentModel();
}

/** Vision-language generation against the resident multimodal model. */
export const vlm = {
  /**
   * Answer a prompt about an image, loading and downloading the model when needed.
   *
   * @throws SDKException when no vision-capable backend is registered.
   *
   * @example
   * const image = await RunAnywhere.ImageInput.blob(pickedFile);
   * const result = await RunAnywhere.vlm.generate(image, 'What is in this photo?');
   */
  async generate(
    image: ImageInput,
    prompt: string,
    options?: LlmOptions,
  ): Promise<GenerationResult> {
    await ensureVisionModel(options?.model);
    const result = await VisionLanguage.processImage(image, toProtoVlmOptions(prompt, options));
    if (result.error) throw new SDKException(result.error);
    return vlmToGenerationResult(result);
  },

  /**
   * Stream an answer about an image as `started`, `textDelta`, and a
   * terminal `completed`/`failed` event. Never fabricates a successful
   * `completed`.
   *
   * @throws SDKException on preflight failure; in-flight failures arrive as a `failed` event.
   */
  generateStream(
    image: ImageInput,
    prompt: string,
    options?: LlmOptions,
  ): AsyncIterable<GenerationEvent> {
    return (async function* generation(): AsyncGenerator<GenerationEvent> {
      await ensureVisionModel(options?.model);
      const stream = await VisionLanguage.processImageStream(
        image,
        toProtoVlmOptions(prompt, options),
      );
      const itemId = 'response-0';
      let requestId = '';
      let announced = false;
      let terminal = false;
      let sequence = 0;
      let text = '';
      try {
        for await (const event of stream) {
          if (event.requestId) requestId = event.requestId;
          if (!announced) {
            announced = true;
            yield { type: 'started', requestId };
          }
          if (event.error) {
            yield { type: 'failed', requestId, partial: { text }, error: event.error };
            terminal = true;
            break;
          }
          if (event.token) {
            text += event.token;
            yield {
              type: 'textDelta', requestId, sequence: sequence++, itemId, index: 0, text: event.token,
            };
          }
          if (event.kind === VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED && event.result) {
            terminal = true;
            const result = vlmToGenerationResult(event.result, requestId);
            yield { type: 'completed', requestId, result };
          }
        }
      } catch (error) {
        yield { type: 'failed', requestId, partial: { text }, error: SDKException.fromUnknown(error).proto };
        terminal = true;
      } finally {
        if (!terminal) await VisionLanguage.cancelVLMGeneration();
      }
    })();
  },
};
