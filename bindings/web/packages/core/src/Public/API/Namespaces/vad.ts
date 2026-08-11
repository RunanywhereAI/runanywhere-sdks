/**
 * `RunAnywhere.vad` — voice-activity detection over a buffer or a live push stream.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { audioCaptureDefaults } from '@runanywhere/proto-ts/defaults/pool';
import { SDKException } from '../../../Foundation/SDKException.js';
import { AsyncQueue } from '../../../Foundation/AsyncQueue.js';
import { detectVoice, streamVoiceActivity } from '../../Extensions/RunAnywhere+VAD.js';
import { pcm16ToFloat32 } from '../../Extensions/RunAnywhere+AudioConvert.js';
import { audioInputToFloat32, type AudioFormatSpec, type AudioFrame, type AudioInput } from '../Inputs.js';
import type { VadOptions } from '../Options.js';
import type { VadEvent } from '../Events.js';
import type { VadResult, VadStream } from '../Results.js';
import { toProtoVadOptions, toVadResult } from '../Mapping.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

/** Native lifecycle VAD streaming is fixed at the mic capture rate (16kHz PCM). */
const NATIVE_STREAM_SAMPLE_RATE = audioCaptureDefaults.micSampleRateHz;

function toDetectOptions(options?: VadOptions) {
  const proto = toProtoVadOptions(options);
  return {
    activationThreshold: proto.activationThreshold,
    minSpeechDurationMs: proto.minSpeechDurationMs,
    minSilenceDurationMs: proto.minSilenceDurationMs,
    prefixPaddingMs: proto.prefixPaddingMs,
  };
}

async function ensureVadModel(): Promise<void> {
  await ensureReady();
  await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION);
}

function frameToFloat32(frame: AudioFrame, format: AudioFormatSpec): Float32Array {
  if (format.encoding === 'pcmF32Le') {
    const count = Math.floor(frame.samples.byteLength / 4);
    const view = new DataView(frame.samples.buffer, frame.samples.byteOffset, count * 4);
    const out = new Float32Array(count);
    for (let i = 0; i < count; i += 1) out[i] = view.getFloat32(i * 4, true);
    return out;
  }
  return pcm16ToFloat32(frame.samples);
}

/**
 * Live VAD push stream backing `vad.openStream`. Unlike STT, the native ABI
 * processes one chunk at a time against a persistent detector, so pushed
 * frames are forwarded immediately rather than buffered.
 */
function createVadStream(format: AudioFormatSpec, options?: VadOptions): VadStream {
  const inputQueue = new AsyncQueue<Float32Array>();
  const outputQueue = new AsyncQueue<VadEvent>();
  let speaking = false;
  let closed = false;

  void (async () => {
    try {
      for await (const result of streamVoiceActivity(inputQueue, toDetectOptions(options))) {
        const timestampMs = result.timestampMs || undefined;
        if (result.isSpeech && !speaking) {
          speaking = true;
          outputQueue.push({ type: 'speechStarted', timestampMs });
        } else if (!result.isSpeech && speaking) {
          speaking = false;
          outputQueue.push({ type: 'speechEnded', timestampMs });
        }
        outputQueue.push({
          type: 'activity',
          isSpeech: result.isSpeech,
          probability: result.probability,
          timestampMs,
        });
      }
      outputQueue.push({ type: 'completed' });
    } catch (error) {
      outputQueue.push({ type: 'failed', error: SDKException.fromUnknown(error).proto });
    } finally {
      outputQueue.complete();
    }
  })();

  return {
    events: outputQueue,

    pushFrame(frame: AudioFrame): void {
      if (closed) return;
      inputQueue.push(frameToFloat32(frame, format));
    },

    flush(): void {
      // No partial-result buffer on Web: every pushed frame is already processed as it arrives.
    },

    finish(): void {
      inputQueue.complete();
    },

    async close(): Promise<void> {
      if (closed) return;
      closed = true;
      inputQueue.complete();
      outputQueue.complete();
    },
  };
}

/** Voice-activity detection against the resident VAD model. */
export const vad = {
  /**
   * Report whether one audio payload contains speech.
   *
   * @throws SDKException when no VAD model is loaded.
   *
   * @example
   * const { isSpeech, probability } = await RunAnywhere.vad.detect(
   *   RunAnywhere.AudioInput.float32(samples));
   */
  async detect(audio: AudioInput, options?: VadOptions): Promise<VadResult> {
    await ensureVadModel();
    return toVadResult(await detectVoice(await audioInputToFloat32(audio), toDetectOptions(options)));
  },

  /**
   * Open a live voice-activity stream with one audio format established up front.
   *
   * @throws SDKException on preflight failure — no VAD model loaded, a
   *   `container` format, or a sample rate other than 16000 Hz (the only
   *   rate the native streaming detector currently accepts).
   *
   * @example
   * const stream = await RunAnywhere.vad.openStream({ encoding: 'pcmS16Le', sampleRate: 16000 });
   * for await (const event of stream.events) { ... }
   */
  async openStream(format: AudioFormatSpec, options?: VadOptions): Promise<VadStream> {
    if (format.encoding === 'container') {
      throw SDKException.invalidConfiguration(
        'vad.openStream needs raw PCM audio; container formats are batch-only — use vad.detect.',
      );
    }
    if (format.sampleRate !== NATIVE_STREAM_SAMPLE_RATE) {
      throw SDKException.invalidConfiguration(
        `Native VAD streaming currently requires ${NATIVE_STREAM_SAMPLE_RATE} Hz PCM (received ${format.sampleRate} Hz).`,
      );
    }
    await ensureVadModel();
    return createVadStream(format, options);
  },

  /**
   * Detect speech across a stream of audio chunks, emitting activity
   * transitions against one persistent native detector.
   *
   * @deprecated Use `vad.openStream`. This forwards into a `VadStream` when
   *   every chunk shares one format; mixed formats throw.
   * @throws SDKException on preflight failure, or when chunks carry mixed formats.
   */
  detectStream(
    audio: AsyncIterable<AudioInput>,
    options?: VadOptions,
  ): AsyncIterable<VadEvent> {
    return (async function* detection(): AsyncGenerator<VadEvent> {
      // The pump runs beside the yield loop, not before it. Draining `audio`
      // to completion first and only then forwarding `stream.events` is fine
      // for a finite buffer and fatal for the live microphone every caller
      // actually passes: that iterable never completes, so the loop never
      // exited and not one event was ever emitted — including the `failed`
      // event that a rejected `openStream` had already queued, which is why
      // a broken detector looked like silence instead of an error.
      const source = audio[Symbol.asyncIterator]();
      const first = await source.next();
      if (first.done) return;
      const format: AudioFormatSpec = first.value.format;
      const stream = await vad.openStream(format, options);

      let stopped = false;
      let pumpError: unknown;
      void (async () => {
        try {
          let step: IteratorResult<AudioInput> = first;
          for (; !step.done; step = await source.next()) {
            if (stopped) return;
            const chunk: AudioInput = step.value;
            if (
              chunk.format.encoding !== format.encoding
              || chunk.format.sampleRate !== format.sampleRate
              || (chunk.format.channels ?? 1) !== (format.channels ?? 1)
            ) {
              throw SDKException.invalidConfiguration(
                'vad.detectStream requires every chunk to share one audio format.',
              );
            }
            stream.pushFrame({ samples: chunk.bytes, sampleCount: chunk.bytes.byteLength });
          }
        } catch (error) {
          pumpError = error;
        } finally {
          // Always terminate the event stream, success or failure — otherwise a
          // rejected pump leaves the consumer below waiting forever.
          stream.finish();
        }
      })();

      try {
        yield* stream.events;
      } finally {
        // Abandoning the generator (a `break`, an unmounted view) must stop the
        // pump and release the native session, not leave audio being fed into
        // a stream nobody reads. `source.return()` is how a caller's own
        // generator learns to shut its microphone pump down.
        //
        // Deliberately not awaited, matching `stt.detectStream`: an async
        // iterator defers its `return()` behind the pending `next()`, and for a
        // live microphone that `next()` only settles when the next frame
        // arrives. Awaiting here would make the consumer's `break` — and the
        // `stream.close()` that releases the native session — block on a frame
        // that may never come if capture has already stopped.
        stopped = true;
        void Promise.resolve(source.return?.(undefined)).catch(() => {
          // Source cleanup is best-effort; the consumer has already left.
        });
        await stream.close();
      }
      if (pumpError) throw pumpError;
    })();
  },
};
