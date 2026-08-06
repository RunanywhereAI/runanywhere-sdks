/**
 * `RunAnywhere.stt` — speech-to-text over a buffer or a live push stream.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { STTStreamEventKind } from '@runanywhere/proto-ts/stt_options';
import { SDKException } from '../../../Foundation/SDKException.js';
import { AsyncQueue } from '../../../Foundation/AsyncQueue.js';
import { STTProtoAdapter } from '../../../Adapters/ModalityProtoAdapter.js';
import { sttState } from '../../Extensions/RunAnywhere+STT.js';
import { audioInputToPcm16, type AudioFormatSpec, type AudioFrame, type AudioInput } from '../Inputs.js';
import type { SttOptions } from '../Options.js';
import type { TranscriptionEvent } from '../Events.js';
import type { SttState, SttStream, Transcription } from '../Results.js';
import { toProtoSttOptions, toTranscription } from '../Mapping.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

function requireAdapter(verb: string): NonNullable<ReturnType<typeof STTProtoAdapter.tryDefault>> {
  const adapter = STTProtoAdapter.tryDefault();
  if (!adapter?.supportsLifecycleProtoSTT()) {
    throw SDKException.backendNotAvailable(
      verb,
      'No Web WASM backend exporting the lifecycle STT proto ABI is registered. Call ONNX.register() first.',
    );
  }
  return adapter;
}

function concatChunks(chunks: readonly Uint8Array[]): Uint8Array {
  const total = chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

function float32BytesToPcm16(bytes: Uint8Array): Uint8Array {
  const count = Math.floor(bytes.byteLength / 4);
  const view = new DataView(bytes.buffer, bytes.byteOffset, count * 4);
  const out = new Uint8Array(count * 2);
  const outView = new DataView(out.buffer);
  for (let i = 0; i < count; i += 1) {
    const clamped = Math.max(-1, Math.min(1, view.getFloat32(i * 4, true)));
    outView.setInt16(i * 2, Math.round(clamped * 0x7fff), true);
  }
  return out;
}

let requestSequence = 0;
function nextRequestId(): string {
  requestSequence += 1;
  return `stt-${Date.now()}-${requestSequence}`;
}

/**
 * Live STT push stream backing `stt.openStream`.
 *
 * The Web WASM artifact exports no incremental push ABI: frames are buffered
 * as they are pushed, and the native streaming pass runs once against the
 * buffered audio when `finish()` is called. Partial/final events forwarded
 * on `events` come from that native pass; none are synthesized, and the
 * stream never emits a `completed` it did not see the backend report.
 */
function createSttStream(format: AudioFormatSpec, options?: SttOptions): SttStream {
  const requestId = nextRequestId();
  const queue = new AsyncQueue<TranscriptionEvent>();
  const chunks: Uint8Array[] = [];
  let announcedStarted = false;
  let finished = false;
  let closed = false;
  let sequence = 0;

  function announceStarted(): void {
    if (announcedStarted) return;
    announcedStarted = true;
    queue.push({ type: 'started', requestId });
  }

  function pcm16BytesFor(frame: AudioFrame): Uint8Array {
    return format.encoding === 'pcmF32Le' ? float32BytesToPcm16(frame.samples) : frame.samples;
  }

  async function runNativePass(): Promise<void> {
    try {
      const audio = concatChunks(chunks);
      if (audio.length === 0) return;
      await ensureReady();
      await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
      const adapter = requireAdapter('stt.openStream');
      for await (const event of adapter.transcribeLifecycleStream(audio, toProtoSttOptions(options))) {
        if (closed) return;
        if (event.error) {
          queue.push({ type: 'failed', requestId, error: event.error });
          return;
        }
        if (event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_FINAL) {
          const final = event.finalOutput;
          if (final) {
            queue.push({
              type: 'transcriptFinal',
              requestId,
              sequence: sequence++,
              segment: toTranscription(final),
            });
          }
          queue.push({ type: 'completed', requestId });
          return;
        }
        if (event.partial?.text) {
          sequence += 1;
          queue.push({
            type: 'partial',
            requestId,
            sequence,
            segmentId: '0',
            revision: sequence,
            alternatives: [{ text: event.partial.text }],
          });
        }
      }
      // The native stream ended without a FINAL/error envelope. Stop
      // silently rather than fabricating a successful `completed`.
    } catch (error) {
      queue.push({ type: 'failed', requestId, error: SDKException.fromUnknown(error).proto });
    } finally {
      queue.complete();
    }
  }

  return {
    events: queue,

    pushFrame(frame: AudioFrame): void {
      if (closed || finished) return;
      announceStarted();
      chunks.push(pcm16BytesFor(frame));
    },

    flush(): void {
      // No incremental partial ABI on Web: nothing buffered client-side to flush.
    },

    finish(): void {
      if (finished || closed) return;
      finished = true;
      announceStarted();
      void runNativePass();
    },

    async close(): Promise<void> {
      if (closed) return;
      closed = true;
      queue.complete();
    },
  };
}

/** Speech-to-text against the resident transcription model. */
export const stt = {
  /**
   * Transcribe one audio payload, loading and downloading the model when needed.
   *
   * A `container` payload (e.g. `AudioInput.wav`) is decoded through the
   * browser's own audio decoder before it reaches the model.
   *
   * @throws SDKException when no STT backend is registered or transcription fails.
   *
   * @example
   * const audio = await RunAnywhere.AudioInput.file(pickedFile);
   * const { text } = await RunAnywhere.stt.transcribe(audio);
   */
  async transcribe(audio: AudioInput, options?: SttOptions): Promise<Transcription> {
    await ensureReady();
    await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
    const adapter = requireAdapter('stt.transcribe');
    const output = await adapter.transcribeLifecycle(
      await audioInputToPcm16(audio),
      toProtoSttOptions(options),
    );
    if (!output) {
      throw SDKException.processingFailed('The STT proto path returned no transcription.');
    }
    if (output.error) throw new SDKException(output.error);
    return toTranscription(output);
  },

  /**
   * Open a live transcription stream with one audio format established up front.
   *
   * @throws SDKException on preflight failure (no backend registered, or
   *   `format.encoding === 'container'` — live streams take raw PCM only).
   *
   * @example
   * const stream = await RunAnywhere.stt.openStream({ encoding: 'pcmS16Le', sampleRate: 16000 });
   * for await (const event of stream.events) { ... }
   */
  async openStream(format: AudioFormatSpec, options?: SttOptions): Promise<SttStream> {
    if (format.encoding === 'container') {
      throw SDKException.invalidConfiguration(
        'stt.openStream needs raw PCM audio; container formats are batch-only — use stt.transcribe.',
      );
    }
    await ensureReady();
    await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
    requireAdapter('stt.openStream');
    return createSttStream(format, options);
  },

  /**
   * Transcribe a stream of audio chunks, emitting `started`, `partial`, and
   * `transcriptFinal`/`completed`.
   *
   * @deprecated Use `stt.openStream`. This forwards into an `SttStream` when
   *   every chunk shares one format; mixed formats throw.
   * @throws SDKException on preflight failure, or when chunks carry mixed formats.
   */
  transcribeStream(
    audio: AsyncIterable<AudioInput>,
    options?: SttOptions,
  ): AsyncIterable<TranscriptionEvent> {
    return (async function* transcription(): AsyncGenerator<TranscriptionEvent> {
      let stream: SttStream | null = null;
      let format: AudioFormatSpec | null = null;
      for await (const chunk of audio) {
        if (!format) {
          format = chunk.format;
          if (format.encoding === 'container') {
            throw SDKException.invalidConfiguration(
              'stt.transcribeStream needs raw PCM chunks; decode container audio before streaming it.',
            );
          }
          stream = await stt.openStream(format, options);
        } else if (
          chunk.format.encoding !== format.encoding
          || chunk.format.sampleRate !== format.sampleRate
          || (chunk.format.channels ?? 1) !== (format.channels ?? 1)
        ) {
          throw SDKException.invalidConfiguration(
            'stt.transcribeStream requires every chunk to share one audio format.',
          );
        }
        stream!.pushFrame({ samples: chunk.bytes, sampleCount: chunk.bytes.byteLength });
      }
      if (!stream) return;
      stream.finish();
      yield* stream.events;
    })();
  },

  /** Readiness, model, and language support of the loaded transcription model. */
  async state(): Promise<SttState> {
    const state = await sttState();
    return {
      isReady: state.isReady,
      modelId: state.currentModel,
      supportsStreaming: state.supportsStreaming,
      languages: state.supportedLanguageCodes,
    };
  },
};
