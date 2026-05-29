/**
 * RunAnywhere+STT.ts
 *
 * Speech-to-Text extension. Aligned to proto-canonical STT shapes
 * (`@runanywhere/proto-ts/stt_options`). All ad-hoc local result/output
 * shapes have been deleted; we work directly off the proto-generated
 * interfaces. Path-first loading and EventBus fallback streaming have
 * been removed — model loading goes through `loadModel` and
 * streaming is driven by the native `sttTranscribeStreamProto` callback.
 *
 * Matches Swift: `Public/Extensions/STT/RunAnywhere+STT.swift`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import {
  STTLanguage,
  STTAudioEncoding,
  type STTOptions,
  type STTOutput,
  type STTPartialResult,
} from '@runanywhere/proto-ts/stt_options';
import {
  STTAudioSource,
  STTOptions as STTOptionsCtor,
  STTOutput as STTOutputMessage,
  STTPartialResult as STTPartialResultMessage,
  STTStreamEvent,
  STTStreamEventKind,
  STTTranscriptionRequest,
} from '@runanywhere/proto-ts/stt_options';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import { arrayBufferToBytes, bytesToArrayBuffer } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

const logger = new SDKLogger('RunAnywhere.STT');
let requestCounter = 0;

/** Build a default proto `STTOptions` for callers that pass no options. */
function defaultSTTOptions(): STTOptions {
  return STTOptionsCtor.create({
    language: STTLanguage.STT_LANGUAGE_AUTO,
    enablePunctuation: true,
    enableDiarization: false,
    maxSpeakers: 0,
    vocabularyList: [],
    enableWordTimestamps: false,
    beamSize: 0,
    detectLanguage: true,
    audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
    sampleRate: 16000,
    maxAlternatives: 0,
  });
}

/**
 * Streaming transcription handle. Mirrors the LLM/VLM streaming surface
 * shape (`partials` + `result` + `cancel`).
 */
export interface STTStreamingResult {
  partials: AsyncIterable<STTPartialResult>;
  result: Promise<STTOutput>;
  cancel: () => void;
}

/** Convert Uint8Array / ArrayBuffer / base64 string audio input to ArrayBuffer. */
function audioToArrayBuffer(audio: Uint8Array | string | ArrayBuffer): ArrayBuffer {
  if (typeof audio === 'string') {
    const binary = atob(audio);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytesToArrayBuffer(bytes);
  }
  if (audio instanceof Uint8Array) {
    return bytesToArrayBuffer(audio);
  }
  return audio;
}

function buildSTTOptions(options?: Partial<STTOptions>): STTOptions {
  return STTOptionsCtor.create({
    ...defaultSTTOptions(),
    ...options,
    language: options?.language ?? STTLanguage.STT_LANGUAGE_AUTO,
    detectLanguage:
      options?.detectLanguage ??
      (options?.language === undefined ||
        options.language === STTLanguage.STT_LANGUAGE_AUTO),
    audioFormat: options?.audioFormat ?? AudioFormat.AUDIO_FORMAT_PCM,
    sampleRate: options?.sampleRate ?? 16000,
    maxAlternatives: options?.maxAlternatives ?? 0,
  });
}

function decodeSTTOutput(buffer: ArrayBuffer): STTOutput {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed('sttTranscribeProto');
  }
  return STTOutputMessage.decode(bytes);
}

function nextSTTRequestId(): string {
  requestCounter += 1;
  return `rn-stt-${Date.now()}-${requestCounter}`;
}

function buildSTTRequestBytes(
  audio: ArrayBuffer,
  options?: Partial<STTOptions>
): ArrayBuffer {
  const audioBytes = arrayBufferToBytes(audio);
  const request = STTTranscriptionRequest.fromPartial({
    requestId: nextSTTRequestId(),
    audio: STTAudioSource.fromPartial({
      audioData: audioBytes,
      encoding: STTAudioEncoding.STT_AUDIO_ENCODING_PCM_S16_LE,
      audioFormat: options?.audioFormat ?? AudioFormat.AUDIO_FORMAT_PCM,
      sampleRate: options?.sampleRate ?? 16000,
      channels: 1,
      bitsPerSample: 16,
    }),
    options: buildSTTOptions(options),
    metadata: {},
  });
  return encodeProtoMessage(request, STTTranscriptionRequest);
}

/**
 * Transcribe audio data.
 *
 * Canonical cross-SDK signature: transcribe(audio: Uint8Array, options: STTOptions)
 * Also accepts string | ArrayBuffer for legacy callers.
 *
 * Matches Swift SDK: `RunAnywhere.transcribe(_:options:)`.
 */
export async function transcribe(
  audio: Uint8Array | string | ArrayBuffer,
  options?: Partial<STTOptions>
): Promise<STTOutput> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  const native = requireNativeModule();
  const audioBytes = audioToArrayBuffer(audio);
  return decodeSTTOutput(
    await native.sttTranscribeProto(buildSTTRequestBytes(audioBytes, options))
  );
}

/**
 * Stream-in / stream-out overload: mirrors Swift's `transcribeStream(audio:AsyncStream<Data>)`.
 *
 * Accumulates VAD-segmented `Uint8Array` chunks from the caller's `AsyncIterable`,
 * concatenates them into a single buffer, then forwards to the native
 * `sttTranscribeStreamProto` callback — matching the Swift behaviour exactly.
 * Prefer this overload for live-mic transcription; use the single-buffer overload
 * only when the full clip is already assembled.
 */
export function transcribeStream(
  audio: AsyncIterable<Uint8Array>,
  options?: Partial<STTOptions>
): AsyncIterable<STTPartialResult>;

/**
 * Single-buffer convenience overload: accepts a pre-assembled audio clip.
 * Kept for backward compatibility with existing callers.
 */
export function transcribeStream(
  audio: Uint8Array | string | ArrayBuffer,
  options?: Partial<STTOptions>
): AsyncIterable<STTPartialResult>;

export function transcribeStream(
  audio: AsyncIterable<Uint8Array> | Uint8Array | string | ArrayBuffer,
  options: Partial<STTOptions> = {}
): AsyncIterable<STTPartialResult> {
  if (audio != null && typeof audio === 'object' && Symbol.asyncIterator in audio) {
    return transcribeStreamFromAsyncIterable(audio as AsyncIterable<Uint8Array>, options);
  }
  return transcribeStreamFromBuffer(audio as Uint8Array | string | ArrayBuffer, options);
}

async function* transcribeStreamFromAsyncIterable(
  chunks: AsyncIterable<Uint8Array>,
  options: Partial<STTOptions>
): AsyncIterable<STTPartialResult> {
  const parts: Uint8Array[] = [];
  let totalLength = 0;
  for await (const chunk of chunks) {
    parts.push(chunk);
    totalLength += chunk.byteLength;
  }
  const accumulated = new Uint8Array(totalLength);
  let offset = 0;
  for (const part of parts) {
    accumulated.set(part, offset);
    offset += part.byteLength;
  }
  yield* transcribeStreamFromBuffer(accumulated, options);
}

function transcribeStreamFromBuffer(
  audio: Uint8Array | string | ArrayBuffer,
  options: Partial<STTOptions> = {}
): AsyncIterable<STTPartialResult> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }

  const native = requireNativeModule();
  const audioBytes = audioToArrayBuffer(audio);
  const requestBytes = buildSTTRequestBytes(audioBytes, options);

  return {
    [Symbol.asyncIterator](): AsyncIterator<STTPartialResult> {
      const queue: STTPartialResult[] = [];
      let resolver: ((value: IteratorResult<STTPartialResult>) => void) | null = null;
      let done = false;
      let started = false;
      let streamError: Error | null = null;

      const finish = (): void => {
        done = true;
        if (resolver) {
          resolver({ value: undefined as unknown as STTPartialResult, done: true });
          resolver = null;
        }
      };

      const start = (): void => {
        if (started) return;
        started = true;
        native
          .sttTranscribeStreamProto(requestBytes, (eventBytes: ArrayBuffer) => {
            try {
              const event = STTStreamEvent.decode(arrayBufferToBytes(eventBytes));
              const partial =
                event.partial ??
                (event.finalOutput
                  ? STTPartialResultMessage.fromPartial({
                      text: event.finalOutput.text,
                      isFinal: true,
                      confidence: event.finalOutput.confidence,
                      language: event.finalOutput.language,
                      timestampMs: event.finalOutput.timestampMs,
                      requestId: event.requestId,
                    })
                  : null);
              if (!partial) {
                if (event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_ERROR) {
                  throw SDKException.generationFailedWith(
                    event.errorMessage ?? 'STT stream failed'
                  );
                }
                return;
              }
              if (resolver) {
                resolver({ value: partial, done: false });
                resolver = null;
              } else {
                queue.push(partial);
              }
              if (
                partial.isFinal ||
                event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_FINAL
              ) {
                finish();
              }
            } catch (error) {
              streamError = error instanceof Error ? error : new Error(String(error));
              finish();
            }
          })
          .then(() => {
            if (!done) finish();
          })
          .catch((err: Error) => {
            streamError = err;
            logger.warning(`sttTranscribeStreamProto rejected: ${err.message}`);
            finish();
          });
      };

      return {
        async next(): Promise<IteratorResult<STTPartialResult>> {
          start();
          if (queue.length > 0) {
            return { value: queue.shift()!, done: false };
          }
          if (streamError) throw streamError;
          if (done) {
            return { value: undefined as unknown as STTPartialResult, done: true };
          }
          return new Promise<IteratorResult<STTPartialResult>>((resolve) => {
            resolver = resolve;
          }).then((result) => {
            if (streamError) throw streamError;
            return result;
          });
        },
        async return(): Promise<IteratorResult<STTPartialResult>> {
          finish();
          return { value: undefined as unknown as STTPartialResult, done: true };
        },
      };
    },
  };
}
