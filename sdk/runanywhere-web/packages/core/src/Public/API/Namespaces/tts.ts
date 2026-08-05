/**
 * `RunAnywhere.tts` — speech synthesis and device playback.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { audioCaptureDefaults } from '@runanywhere/proto-ts/defaults/pool';
import { SDKException, type ProtoSDKError } from '../../../Foundation/SDKException.js';
import { SDKLogger } from '../../../Foundation/SDKLogger.js';
import { TTSProtoAdapter } from '../../../Adapters/ModalityProtoAdapter.js';
import {
  TTS as TTSCapability,
  sharedTTSPlayback,
  stopTTSPlayback,
} from '../../Extensions/RunAnywhere+TTS.js';
import type { TtsOptions } from '../Options.js';
import type { Audio, AudioChunk, SpeechHandle, Voice } from '../Results.js';
import { toAudio, toProtoTtsOptions, toVoice } from '../Mapping.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

const logger = new SDKLogger('tts');

function requireAdapter(verb: string): NonNullable<ReturnType<typeof TTSProtoAdapter.tryDefault>> {
  const adapter = TTSProtoAdapter.tryDefault();
  if (!adapter?.supportsLifecycleProtoTTS()) {
    throw SDKException.backendNotAvailable(
      verb,
      'No Web WASM backend exporting the lifecycle TTS proto ABI is registered. Call ONNX.register() first.',
    );
  }
  return adapter;
}

/** Decode synthesized bytes into the Float32 samples the Web Audio API wants. */
function toPlaybackSamples(audio: Audio): Float32Array | null {
  if (audio.data.byteLength === 0) return null;
  if (audio.format === 'pcm') {
    const count = Math.floor(audio.data.byteLength / 4);
    const view = new DataView(audio.data.buffer, audio.data.byteOffset, count * 4);
    const out = new Float32Array(count);
    for (let i = 0; i < count; i += 1) out[i] = view.getFloat32(i * 4, true);
    return out;
  }
  if (audio.format === 'pcm16') {
    const count = Math.floor(audio.data.byteLength / 2);
    const view = new DataView(audio.data.buffer, audio.data.byteOffset, count * 2);
    const out = new Float32Array(count);
    for (let i = 0; i < count; i += 1) out[i] = view.getInt16(i * 2, true) / 0x8000;
    return out;
  }
  // Containerized audio needs a decoder the SDK does not ship.
  return null;
}

async function ensureVoiceModel(): Promise<void> {
  await ensureReady();
  await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS);
}

let speechSequence = 0;
function nextSpeechId(): string {
  speechSequence += 1;
  return `speech-${Date.now()}-${speechSequence}`;
}

/** The most recently created `speak()` handle, for the deprecated `stop()` adapter. */
let latestHandle: SpeechHandle | null = null;

function createSpeechHandle(text: string, options?: TtsOptions): SpeechHandle {
  const id = nextSpeechId();
  let interrupted = false;
  let error: ProtoSDKError | undefined;
  let settle!: () => void;
  const settled = new Promise<void>((resolve) => { settle = resolve; });

  const handle: SpeechHandle = {
    id,
    get interrupted(): boolean {
      return interrupted;
    },
    get error(): ProtoSDKError | undefined {
      return error;
    },
    async interrupt(): Promise<void> {
      interrupted = true;
      stopTTSPlayback();
      TTSCapability.stopLoaded();
      await settled;
    },
    async waitForPlayout(): Promise<void> {
      await settled;
    },
  };

  void (async () => {
    try {
      const audio = await tts.synthesize(text, options);
      const samples = toPlaybackSamples(audio);
      if (!samples || samples.length === 0) {
        logger.warning(`speak(): cannot play ${audio.format} audio without a container decoder`);
        return;
      }
      await sharedTTSPlayback().play(
        samples,
        audio.sampleRate > 0 ? audio.sampleRate : audioCaptureDefaults.ttsSampleRateHz,
      );
    } catch (caught) {
      error = SDKException.fromUnknown(caught).proto;
      logger.warning(`speak(): failed: ${error.message}`);
    } finally {
      settle();
      if (latestHandle === handle) latestHandle = null;
    }
  })();

  return handle;
}

/** Speech synthesis against the resident voice model. */
export const tts = {
  /**
   * Synthesize text into an audio buffer.
   *
   * @throws SDKException when no TTS backend or voice is loaded.
   *
   * @example
   * const audio = await RunAnywhere.tts.synthesize('Hello from on-device AI.');
   * console.log(audio.durationMs);
   */
  async synthesize(text: string, options?: TtsOptions): Promise<Audio> {
    await ensureVoiceModel();
    const output = await requireAdapter('tts.synthesize')
      .synthesizeLifecycle(text, toProtoTtsOptions(options));
    if (!output) {
      throw SDKException.processingFailed('The TTS proto path returned no audio.');
    }
    if (output.error) throw new SDKException(output.error);
    return toAudio(output);
  },

  /**
   * Synthesize text as a sequence of audio chunks.
   *
   * @throws SDKException on preflight failure; in-flight failures throw into the consumer.
   */
  synthesizeStream(text: string, options?: TtsOptions): AsyncIterable<AudioChunk> {
    return (async function* synthesis(): AsyncGenerator<AudioChunk> {
      await ensureVoiceModel();
      const outputs = requireAdapter('tts.synthesizeStream')
        .synthesizeLifecycleStream(text, toProtoTtsOptions(options));
      let index = 0;
      let last: { data: Uint8Array; index: number } | null = null;
      for await (const output of outputs) {
        if (output.error) throw new SDKException(output.error);
        if (last) yield { data: last.data, index: last.index, isFinal: false };
        last = { data: output.audioData, index: output.chunkIndex || index };
        index += 1;
      }
      if (last) yield { data: last.data, index: last.index, isFinal: true };
    })();
  },

  /**
   * Synthesize text and play it through the device speakers.
   *
   * There is no global `tts.stop()`; interrupt playback through the returned handle.
   *
   * @throws SDKException never — synthesis/playback failure surfaces on `handle.error`.
   */
  async speak(text: string, options?: TtsOptions): Promise<SpeechHandle> {
    const handle = createSpeechHandle(text, options);
    latestHandle = handle;
    return handle;
  },

  /**
   * @deprecated Use the `SpeechHandle` returned by `speak()`. Interrupts the
   *   most recently created handle when one is still active.
   */
  stop(): void {
    void latestHandle?.interrupt();
  },

  /** Voices the loaded synthesis model can render. */
  async voices(): Promise<Voice[]> {
    await ensureVoiceModel();
    return TTSCapability.listLoadedVoices().map(toVoice);
  },
};
