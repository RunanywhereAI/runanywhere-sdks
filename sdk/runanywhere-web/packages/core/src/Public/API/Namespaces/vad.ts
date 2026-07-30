/**
 * `RunAnywhere.vad` — voice-activity detection over a buffer or a chunk stream.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { detectVoice, streamVoiceActivity } from '../../Extensions/RunAnywhere+VAD.js';
import { audioInputToFloat32, type AudioInput } from '../Inputs.js';
import type { VadOptions } from '../Options.js';
import type { VadEvent } from '../Events.js';
import type { VadResult } from '../Results.js';
import { toProtoVadOptions, toVadResult } from '../Mapping.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

function toDetectOptions(options?: VadOptions) {
  const proto = toProtoVadOptions(options);
  return {
    activationThreshold: proto.activationThreshold,
    minSpeechDurationMs: proto.minSpeechDurationMs,
    minSilenceDurationMs: proto.minSilenceDurationMs,
    prefixPaddingMs: proto.prefixPaddingMs,
    includeStatistics: proto.includeStatistics,
  };
}

async function ensureVadModel(): Promise<void> {
  await ensureReady();
  await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION);
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
    return toVadResult(await detectVoice(audioInputToFloat32(audio), toDetectOptions(options)));
  },

  /**
   * Detect speech across a stream of audio chunks, emitting activity
   * transitions against one persistent native detector.
   *
   * @throws SDKException on preflight failure; in-flight failures throw into the consumer.
   */
  detectStream(
    audio: AsyncIterable<AudioInput>,
    options?: VadOptions,
  ): AsyncIterable<VadEvent> {
    return (async function* detection(): AsyncGenerator<VadEvent> {
      await ensureVadModel();
      const frames = (async function* asFloat32(): AsyncGenerator<Float32Array> {
        for await (const chunk of audio) yield audioInputToFloat32(chunk);
      })();
      let speaking = false;
      let speechStartedMs = 0;
      for await (const result of streamVoiceActivity(frames, toDetectOptions(options))) {
        const timestampMs = result.timestampMs || result.startTimeMs;
        if (result.isSpeech && !speaking) {
          speaking = true;
          speechStartedMs = timestampMs;
          yield { type: 'speechStarted', timestampMs };
        } else if (!result.isSpeech && speaking) {
          speaking = false;
          yield {
            type: 'speechEnded',
            timestampMs,
            durationMs: Math.max(0, timestampMs - speechStartedMs),
          };
        }
        yield {
          type: 'activity',
          isSpeech: result.isSpeech,
          probability: result.confidence,
          timestampMs,
        };
      }
    })();
  },
};
