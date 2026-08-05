/**
 * `RunAnywhere.vad` — speech detection over a buffer or a live stream.
 */

import {
  VADProcessRequest,
  VADResult,
} from '@runanywhere/proto-ts/vad_options';

import { ModelCategory } from '@runanywhere/proto-ts/model_types';

import { decode, encode, nextRequestId, preflight } from './Bridge';
import { ensureModelLoaded } from './Models';
import { toVadAudioSource } from './Inputs';
import { toVadOptions } from './Options';
import { toVadResult } from './Results';
import { pushStream } from './Stream';
import type {
  AudioInput,
  VadEvent,
  VadOptions,
  VadResult as PublicVadResult,
} from './Types';

async function detectOnce(
  audio: AudioInput,
  options?: VadOptions
): Promise<PublicVadResult> {
  const native = await preflight();
  if (options?.model) {
    await ensureModelLoaded(
      options.model,
      ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
    );
  }
  const request = VADProcessRequest.fromPartial({
    requestId: nextRequestId('vad'),
    audio: toVadAudioSource(audio),
    options: toVadOptions(options),
  });
  const resultBytes = await native.vadProcessProto(
    encode(request, VADProcessRequest)
  );
  return toVadResult(decode(resultBytes, VADResult, 'vadProcess'));
}

/** Voice-activity detection. */
export const vad = {
  /**
   * Report whether an audio buffer contains speech.
   *
   * @example
   * const result = await RunAnywhere.vad.detect(AudioInputs.pcm16(frame));
   * if (result.isSpeech) startTranscribing();
   *
   * @throws SDKException when no VAD model is loaded or detection fails.
   */
  detect: detectOnce,

  /**
   * Detect speech across a live audio stream, emitting boundary transitions.
   *
   * @throws SDKException into the consumer when detection fails in flight.
   */
  detectStream(
    audio: AsyncIterable<AudioInput>,
    options?: VadOptions
  ): AsyncIterable<VadEvent> {
    let input: AsyncIterator<AudioInput> | null = null;

    return pushStream<VadEvent>(
      async (controller) => {
        const iterator = audio[Symbol.asyncIterator]();
        input = iterator;
        void (async () => {
          let inSpeech = false;
          try {
            for (;;) {
              if (controller.closed) return;
              const step = await iterator.next();
              if (step.done) break;
              const result = await detectOnce(step.value, options);
              if (result.isSpeech && !inSpeech) {
                inSpeech = true;
                controller.push({ type: 'speechStarted' });
              } else if (!result.isSpeech && inSpeech) {
                inSpeech = false;
                controller.push({ type: 'speechEnded' });
              }
              controller.push({
                type: 'activity',
                isSpeech: result.isSpeech,
                probability: result.probability,
              });
            }
            if (inSpeech) controller.push({ type: 'speechEnded' });
            controller.push({ type: 'completed' });
            controller.finish();
          } catch (error) {
            controller.fail(error);
          }
        })();
      },
      async () => {
        await input?.return?.();
      }
    );
  },
};
