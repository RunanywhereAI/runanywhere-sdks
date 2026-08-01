/**
 * `RunAnywhere.stt` — transcription, live and one-shot.
 */

import {
  STTOutput,
  STTTranscriptionRequest,
} from '@runanywhere/proto-ts/stt_options';

import { SDKException } from '../../Foundation/Errors/SDKException';
import {
  sttState as sttStateProto,
  transcribeStream as transcribePartials,
} from '../Extensions/STT/RunAnywhere+STT';
import { decode, encode, nextRequestId, preflight } from './Bridge';
import { toAudioBytes, toSttAudioSource } from './Inputs';
import { toSttOptions } from './Options';
import { toSttState, toTranscription } from './Results';
import { pushStream } from './Stream';
import type {
  AudioInput,
  SttOptions,
  SttState,
  Transcription,
  TranscriptionEvent,
} from './Types';

/** Turn a public audio stream into the raw PCM stream the session driver feeds. */
function toByteStream(
  audio: AsyncIterable<AudioInput>
): AsyncIterable<Uint8Array> {
  return {
    [Symbol.asyncIterator](): AsyncIterator<Uint8Array> {
      const iterator = audio[Symbol.asyncIterator]();
      return {
        async next(): Promise<IteratorResult<Uint8Array>> {
          const step = await iterator.next();
          if (step.done) return { value: new Uint8Array(), done: true };
          return {
            value: toAudioBytes(step.value, 'stt.transcribeStream'),
            done: false,
          };
        },
        async return(): Promise<IteratorResult<Uint8Array>> {
          await iterator.return?.();
          return { value: new Uint8Array(), done: true };
        },
      };
    },
  };
}

/** Speech-to-text over a buffer or a live audio stream. */
export const stt = {
  /**
   * Transcribe a complete audio buffer.
   *
   * @example
   * const result = await RunAnywhere.stt.transcribe(AudioInputs.wav(bytes));
   * console.log(result.text);
   *
   * @throws SDKException when no speech model is loaded or transcription fails.
   */
  async transcribe(
    audio: AudioInput,
    options?: SttOptions
  ): Promise<Transcription> {
    const native = await preflight();
    const request = STTTranscriptionRequest.fromPartial({
      requestId: nextRequestId('stt'),
      audio: toSttAudioSource(audio),
      options: toSttOptions(options),
    });
    const resultBytes = await native.sttTranscribeProto(
      encode(request, STTTranscriptionRequest)
    );
    return toTranscription(decode(resultBytes, STTOutput, 'sttTranscribe'));
  },

  /**
   * Transcribe audio as it arrives, emitting partials then one final result.
   *
   * @throws SDKException into the consumer when the session fails in flight.
   */
  transcribeStream(
    audio: AsyncIterable<AudioInput>,
    options?: SttOptions
  ): AsyncIterable<TranscriptionEvent> {
    let inner: AsyncIterator<unknown> | null = null;

    return pushStream<TranscriptionEvent>(
      async (controller) => {
        controller.push({ type: 'started' });
        const partials = transcribePartials(toByteStream(audio), {
          ...toSttOptions(options),
        });
        const iterator = partials[Symbol.asyncIterator]();
        inner = iterator;
        void (async () => {
          try {
            for (;;) {
              const step = await iterator.next();
              if (step.done) break;
              const partial = step.value;
              if (partial.finalOutput?.error) {
                controller.fail(new SDKException(partial.finalOutput.error));
                return;
              }
              if (partial.isFinal) {
                controller.push({
                  type: 'final',
                  transcription: toTranscription(
                    partial.finalOutput ??
                      STTOutput.fromPartial({ text: partial.text })
                  ),
                });
                controller.finish();
                return;
              }
              controller.push({ type: 'partial', text: partial.text });
            }
            controller.finish();
          } catch (error) {
            controller.fail(error);
          }
        })();
      },
      async () => {
        await inner?.return?.();
      }
    );
  },

  /** Readiness, model, and language support of the speech component. */
  async state(): Promise<SttState> {
    return toSttState(await sttStateProto());
  },
};
