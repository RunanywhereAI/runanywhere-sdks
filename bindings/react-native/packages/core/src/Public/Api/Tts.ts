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
import type { Audio, AudioChunk, SpeechHandle, TtsOptions, Voice } from './Types';

let speechSequence = 0;
function nextSpeechId(): string {
  speechSequence += 1;
  return `speech-${Date.now()}-${speechSequence}`;
}

/** The most recently created `speak()` handle, for the deprecated `stop()` adapter. */
let latestHandle: MutableSpeechHandle | null = null;

interface MutableSpeechHandle extends SpeechHandle {
  interrupted: boolean;
  error?: Error;
}

function createSpeechHandle(text: string, options?: TtsOptions): MutableSpeechHandle {
  let settle!: () => void;
  const settled = new Promise<void>((resolve) => {
    settle = resolve;
  });
  const handle: MutableSpeechHandle = {
    id: nextSpeechId(),
    interrupted: false,
    error: undefined,
    async interrupt(): Promise<void> {
      handle.interrupted = true;
      await stopSpeaking().catch(() => undefined);
      settle();
    },
    async waitForPlayout(): Promise<void> {
      await settled;
    },
  };

  void speakAndPlay(text, toTtsOptions(options))
    .catch((error: unknown) => {
      handle.error = error instanceof Error ? error : new Error(String(error));
    })
    .finally(() => {
      settle();
      if (latestHandle === handle) latestHandle = null;
    });

  return handle;
}

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
                event.error
                  ? new SDKException(event.error)
                  : SDKException.processingFailed('TTS stream failed')
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
   * Synthesize `text` and play it through the device output, returning
   * immediately with a handle to the in-flight utterance.
   *
   * There is no global `tts.stop()`; interrupt playback through the
   * returned handle.
   *
   * @throws SDKException never directly — synthesis/playback failure
   * surfaces on `handle.error`.
   */
  speak(text: string, options?: TtsOptions): SpeechHandle {
    const handle = createSpeechHandle(text, options);
    latestHandle = handle;
    return handle;
  },

  /**
   * @deprecated Use the `SpeechHandle` returned by `speak()`. Interrupts the
   * most recently created handle when one is still active.
   */
  async stop(): Promise<void> {
    if (latestHandle) {
      await latestHandle.interrupt();
      return;
    }
    await stopSpeaking();
  },

  /** Voices the loaded speech-synthesis model can speak with. */
  async voices(): Promise<Voice[]> {
    const native = await preflight();
    const list = decodeOptional(await native.ttsListVoicesProto(), TTSVoiceList);
    return (list?.voices ?? []).map(toVoice);
  },
};
