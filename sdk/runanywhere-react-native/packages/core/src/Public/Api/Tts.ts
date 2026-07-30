/**
 * `RunAnywhere.tts` — synthesis and device playback.
 */

import {
  TTSOutput,
  TTSStreamEvent,
  TTSStreamEventKind,
  TTSSynthesisRequest,
  TTSVoiceList,
} from '@runanywhere/proto-ts/tts_options';

import { SDKException } from '../../Foundation/Errors/SDKException';
import { speak as speakAndPlay, stopSpeaking } from '../Extensions/TTS/RunAnywhere+TTS';
import { decode, decodeEvent, decodeOptional, encode, nextRequestId, preflight } from './Bridge';
import { toTtsOptions } from './Options';
import { toAudio, toAudioChunk, toVoice } from './Results';
import { pushStream } from './Stream';
import type { Audio, AudioChunk, TtsOptions, Voice } from './Types';

function buildRequest(text: string, options?: TtsOptions): ArrayBuffer {
  return encode(
    TTSSynthesisRequest.fromPartial({
      requestId: nextRequestId('tts'),
      text,
      options: toTtsOptions(options),
    }),
    TTSSynthesisRequest
  );
}

/** Text-to-speech synthesis and playback. */
export const tts = {
  /**
   * Synthesize `text` into an audio buffer.
   *
   * @example
   * const audio = await RunAnywhere.tts.synthesize('Hello there.');
   * console.log(audio.durationMs);
   *
   * @throws SDKException when no voice is loaded or synthesis fails.
   */
  async synthesize(text: string, options?: TtsOptions): Promise<Audio> {
    const native = await preflight();
    const resultBytes = await native.ttsSynthesizeProto(
      buildRequest(text, options)
    );
    return toAudio(decode(resultBytes, TTSOutput, 'ttsSynthesize'));
  },

  /**
   * Synthesize `text`, yielding audio chunks as they are produced.
   *
   * @throws SDKException into the consumer when synthesis fails in flight.
   */
  synthesizeStream(
    text: string,
    options?: TtsOptions
  ): AsyncIterable<AudioChunk> {
    let cancel: (() => Promise<void>) | null = null;

    return pushStream<AudioChunk>(
      async (controller) => {
        const native = await preflight();
        const requestBytes = buildRequest(text, options);
        cancel = async () => {
          await native.ttsStopProto().catch(() => undefined);
        };

        void native
          .ttsSynthesizeStreamProto(requestBytes, (eventBytes: ArrayBuffer) => {
            const event = decodeEvent(eventBytes, TTSStreamEvent);
            if (event.kind === TTSStreamEventKind.TTS_STREAM_EVENT_KIND_ERROR) {
              controller.fail(
                SDKException.processingFailed(
                  event.errorMessage || 'TTS stream failed'
                )
              );
              return;
            }
            if (event.output) {
              controller.push(toAudioChunk(event.output));
            }
            if (
              event.kind === TTSStreamEventKind.TTS_STREAM_EVENT_KIND_COMPLETED
            ) {
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

  /**
   * Synthesize `text` and play it through the device output.
   *
   * @throws SDKException when no voice is loaded or synthesis fails.
   */
  async speak(text: string, options?: TtsOptions): Promise<void> {
    await speakAndPlay(text, toTtsOptions(options));
  },

  /** Stop playback and any in-flight synthesis. */
  async stop(): Promise<void> {
    await stopSpeaking();
  },

  /** Voices the loaded speech-synthesis model can speak with. */
  async voices(): Promise<Voice[]> {
    const native = await preflight();
    const list = decodeOptional(await native.ttsListVoicesProto(), TTSVoiceList);
    return (list?.voices ?? []).map(toVoice);
  },
};
