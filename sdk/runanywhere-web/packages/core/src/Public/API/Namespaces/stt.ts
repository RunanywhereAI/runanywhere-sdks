/**
 * `RunAnywhere.stt` — speech-to-text over a buffer or a live push stream.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { STTStreamEventKind } from '@runanywhere/proto-ts/stt_options';
import { audioCaptureDefaults } from '@runanywhere/proto-ts/defaults/pool';
import { SDKException } from '../../../Foundation/SDKException.js';
import { SDKLogger } from '../../../Foundation/SDKLogger.js';
import { AsyncQueue } from '../../../Foundation/AsyncQueue.js';
import { spokenTranscript } from '../../../Foundation/TranscriptText.js';
import { STTProtoAdapter } from '../../../Adapters/ModalityProtoAdapter.js';
import { sttState } from '../../Extensions/RunAnywhere+STT.js';
import { audioInputToPcm16, type AudioFormatSpec, type AudioFrame, type AudioInput } from '../Inputs.js';
import type { SttOptions } from '../Options.js';
import type { TranscriptionEvent } from '../Events.js';
import type { SttState, SttStream, Transcription } from '../Results.js';
import { toProtoSttOptions, toTranscription } from '../Mapping.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

const logger = new SDKLogger('stt');

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
 * How much audio a preview pass needs before its guess is worth showing.
 *
 * Whisper decodes a whole window at once, so a 300 ms sliver either returns
 * nothing or returns a confident invention. A little over a second is where its
 * first guess starts tracking what was actually said.
 */
const PREVIEW_MIN_AUDIO_MS = 1_200;
/**
 * New audio required before the next preview. The previous pass must also have
 * finished, so on a slow device the real cadence is however long a pass takes —
 * the stream self-throttles instead of queueing work it cannot keep up with.
 */
const PREVIEW_MIN_NEW_AUDIO_MS = 700;

/**
 * Live STT push stream backing `stt.openStream`.
 *
 * How partials are produced. The Web speech WASM exports no incremental push
 * ABI — `rac_stt_transcribe_stream_lifecycle_proto` takes one whole buffer —
 * so this session re-runs that pass over the audio accumulated *so far* while
 * capture is still open, and publishes each result as a `partial`. The pass at
 * `finish()` sees the complete utterance and is the only one that produces
 * `transcriptFinal`.
 *
 * That is what makes a "transcribe as I speak" surface honest: words appear
 * while the microphone is open, and because every preview re-decodes from the
 * start of the utterance with more context than the last, earlier guesses are
 * genuinely revised rather than merely appended to. Previously frames were only
 * buffered and the single pass ran after the microphone closed, so a live mode
 * produced exactly one update — batch transcription wearing a streaming label.
 *
 * Previews are strictly best-effort: only one runs at a time, a failed preview
 * is logged and dropped rather than failing the stream, and `finish()` waits
 * for the in-flight one so two passes never share the resident model. The final
 * pass alone owns `failed`/`transcriptFinal`/`completed`, and the stream still
 * never emits a `completed` the backend did not report.
 */
function createSttStream(format: AudioFormatSpec, options?: SttOptions): SttStream {
  const requestId = nextRequestId();
  const queue = new AsyncQueue<TranscriptionEvent>();
  const chunks: Uint8Array[] = [];
  let bufferedBytes = 0;
  let announcedStarted = false;
  let finished = false;
  let closed = false;
  let sequence = 0;
  /** Set once the final pass has published its transcript; no preview may follow it. */
  let settled = false;
  let previewPass: Promise<void> | null = null;
  let previewedBytes = 0;

  const sampleRate = format.sampleRate > 0
    ? format.sampleRate
    : audioCaptureDefaults.micSampleRateHz;
  const channels = format.channels && format.channels > 0 ? format.channels : 1;
  /** PCM16 bytes → wall-clock milliseconds of audio. */
  const durationMs = (bytes: number): number => (bytes / 2 / channels / sampleRate) * 1000;

  function announceStarted(): void {
    if (announcedStarted) return;
    announcedStarted = true;
    queue.push({ type: 'started', requestId });
  }

  function pcm16BytesFor(frame: AudioFrame): Uint8Array {
    return format.encoding === 'pcmF32Le' ? float32BytesToPcm16(frame.samples) : frame.samples;
  }

  function publishPartial(text: string): void {
    const spoken = spokenTranscript(text);
    if (!spoken || closed || settled) return;
    sequence += 1;
    queue.push({
      type: 'partial',
      requestId,
      sequence,
      segmentId: '0',
      revision: sequence,
      alternatives: [{ text: spoken }],
    });
  }

  /**
   * One preview decode of everything captured so far. Whichever text the pass
   * settles on is published as a single revision — a preview is a guess about
   * the whole utterance, not a delta, so emitting its intermediate envelopes
   * would make the pane flicker between two decodes of the same audio.
   */
  async function runPreviewPass(audio: Uint8Array): Promise<void> {
    try {
      const adapter = requireAdapter('stt.openStream');
      let best = '';
      for await (const event of adapter.transcribeLifecycleStream(audio, toProtoSttOptions(options))) {
        if (closed || settled) return;
        if (event.error) return; // A preview never fails the stream; the final pass reports.
        const text = event.partial?.text || event.finalOutput?.text || '';
        if (text.trim()) best = text;
      }
      publishPartial(best);
    } catch (error) {
      logger.debug(
        `Live transcription preview skipped: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  /**
   * Start a preview if one is warranted. `force` (from `flush()`) waives the
   * new-audio cadence but not the minimum window — below that the model has
   * nothing to work with and would answer with an invention.
   */
  function maybeStartPreview(force: boolean): void {
    if (closed || finished || settled || previewPass) return;
    if (durationMs(bufferedBytes) < PREVIEW_MIN_AUDIO_MS) return;
    if (!force && durationMs(bufferedBytes - previewedBytes) < PREVIEW_MIN_NEW_AUDIO_MS) return;
    previewedBytes = bufferedBytes;
    const audio = concatChunks(chunks);
    const pass = runPreviewPass(audio).finally(() => {
      if (previewPass === pass) previewPass = null;
    });
    previewPass = pass;
  }

  async function runNativePass(): Promise<void> {
    try {
      // The resident model serves one pass at a time: let the preview that was
      // already decoding drain before the authoritative pass takes it over.
      if (previewPass) await previewPass.catch(() => { /* previews never fail the stream */ });
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
            settled = true;
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
        if (event.partial?.text) publishPartial(event.partial.text);
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
      const bytes = pcm16BytesFor(frame);
      chunks.push(bytes);
      bufferedBytes += bytes.byteLength;
      maybeStartPreview(false);
    },

    flush(): void {
      if (closed || finished) return;
      maybeStartPreview(true);
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
   * Chunks are drained by a pump that runs *alongside* the event loop. Draining
   * the whole iterable first and only then yielding meant a caller feeding a
   * live microphone received nothing until the microphone closed — every partial
   * the session had produced arrived in one burst afterwards, which reads on
   * screen as no streaming at all.
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
      const chunks = audio[Symbol.asyncIterator]();
      // The first chunk establishes the format the session is opened with, so
      // it has to be awaited before there is a stream to push into.
      const first = await chunks.next();
      if (first.done) return;
      const format: AudioFormatSpec = first.value.format;
      if (format.encoding === 'container') {
        throw SDKException.invalidConfiguration(
          'stt.transcribeStream needs raw PCM chunks; decode container audio before streaming it.',
        );
      }
      const stream: SttStream = await stt.openStream(format, options);

      const push = (chunk: AudioInput): void => {
        if (
          chunk.format.encoding !== format.encoding
          || chunk.format.sampleRate !== format.sampleRate
          || (chunk.format.channels ?? 1) !== (format.channels ?? 1)
        ) {
          throw SDKException.invalidConfiguration(
            'stt.transcribeStream requires every chunk to share one audio format.',
          );
        }
        stream.pushFrame({ samples: chunk.bytes, sampleCount: chunk.bytes.byteLength });
      };

      push(first.value);
      // Captured rather than left to reject: a consumer that stops iterating
      // early never reaches the rethrow below, and a floating rejection there
      // would surface as an unhandled promise instead of a stream error.
      let pumpError: unknown;
      const pump = (async () => {
        try {
          for (let next = await chunks.next(); !next.done; next = await chunks.next()) {
            push(next.value);
          }
        } finally {
          // Whether the source ended or threw, the audio pushed so far still
          // deserves a final transcript — and `finish()` is what completes the
          // event stream the consumer below is iterating.
          stream.finish();
        }
      })().catch((error: unknown) => { pumpError = error; });

      try {
        yield* stream.events;
      } finally {
        // Closing the event stream does not end the pump: it is parked on
        // `chunks.next()`, which for a live microphone only settles when the
        // next frame arrives — so a consumer that breaks early would leave the
        // capture source running with nobody reading it. Ending the source is
        // what stops the pump. Deliberately not awaited: an iterator defers its
        // `return()` behind the pending `next()`, and awaiting that here would
        // make the consumer's `break` block on the next microphone frame.
        void Promise.resolve(chunks.return?.()).catch(() => {
          // Source cleanup is best-effort; the consumer has already left.
        });
        await stream.close();
      }
      await pump;
      // Surfaces a mixed-format/source failure once the transcript events the
      // session did produce have been delivered.
      if (pumpError !== undefined) throw pumpError;
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
