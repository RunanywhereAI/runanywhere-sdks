/**
 * `RunAnywhere.stt` — speech-to-text over a buffer or a chunk stream.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { STTStreamEventKind } from '@runanywhere/proto-ts/stt_options';
import { SDKException } from '../../../Foundation/SDKException.js';
import { STTProtoAdapter } from '../../../Adapters/ModalityProtoAdapter.js';
import { sttState } from '../../Extensions/RunAnywhere+STT.js';
import { audioInputToPcm16, type AudioInput } from '../Inputs.js';
import type { SttOptions } from '../Options.js';
import type { TranscriptionEvent } from '../Events.js';
import type { SttState, Transcription } from '../Results.js';
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

/** Speech-to-text against the resident transcription model. */
export const stt = {
  /**
   * Transcribe one audio payload, loading and downloading the model when needed.
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
      audioInputToPcm16(audio),
      toProtoSttOptions(options),
    );
    if (!output) {
      throw SDKException.processingFailed('The STT proto path returned no transcription.');
    }
    if (output.error) throw new SDKException(output.error);
    return toTranscription(output);
  },

  /**
   * Transcribe a stream of audio chunks, emitting `started`, `partial`, and `final`.
   *
   * The Web WASM artifact exports no incremental push ABI, so chunks are
   * collected while the caller supplies them and the native streaming pass runs
   * once the input stream closes. Partials come from that pass; none are
   * synthesized.
   *
   * @throws SDKException on preflight failure; in-flight failures throw into the consumer.
   */
  transcribeStream(
    audio: AsyncIterable<AudioInput>,
    options?: SttOptions,
  ): AsyncIterable<TranscriptionEvent> {
    return (async function* transcription(): AsyncGenerator<TranscriptionEvent> {
      await ensureReady();
      await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
      const adapter = requireAdapter('stt.transcribeStream');
      yield { type: 'started' };

      const chunks: Uint8Array[] = [];
      for await (const chunk of audio) chunks.push(audioInputToPcm16(chunk));
      if (chunks.length === 0) return;

      const events = adapter.transcribeLifecycleStream(
        concatChunks(chunks),
        toProtoSttOptions(options),
      );
      for await (const event of events) {
        if (event.error) throw new SDKException(event.error);
        if (event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_FINAL) {
          const final = event.finalOutput ?? event.partial?.finalOutput;
          if (final) yield { type: 'final', transcription: toTranscription(final) };
          return;
        }
        if (event.partial?.text) yield { type: 'partial', text: event.partial.text };
      }
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
