/**
 * RunAnywhere+STT.ts
 *
 * Speech-to-Text extension. Aligned to proto-canonical STT shapes
 * (`@runanywhere/proto-ts/stt_options`). All ad-hoc local result/output
 * shapes have been deleted; we work directly off the proto-generated
 * interfaces. Path-first loading and EventBus fallback streaming have
 * been removed — model loading goes through `loadModel` and streaming is
 * driven by a real native session (`sttStreamStart` / `sttStreamFeed` /
 * `sttStreamStop`) that yields live partials as audio is fed.
 *
 * Matches Swift: `Public/Extensions/STT/RunAnywhere+STT.swift` (public
 * contract) and `CppBridge+STT.swift` `transcribeSessionStream` (session
 * recipe + event mapping).
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
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
import {
  AudioFormat,
  CurrentModelRequest,
  ModelCategory,
} from '@runanywhere/proto-ts/model_types';
import { arrayBufferToBytes, bytesToArrayBuffer } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';
import { currentModel } from '../Models/RunAnywhere+ModelLifecycle';

const logger = new SDKLogger('RunAnywhere.STT');
let requestCounter = 0;

/**
 * Build a default proto `STTOptions` for callers that pass no options.
 * Defaults mirror Swift `RASTTOptions.defaults()` (Generated/RAConvenience.swift):
 * language EN, punctuation + word timestamps enabled.
 */
function defaultSTTOptions(): STTOptions {
  return STTOptionsCtor.create({
    language: STTLanguage.STT_LANGUAGE_EN,
    enablePunctuation: true,
    enableDiarization: false,
    maxSpeakers: 0,
    vocabularyList: [],
    enableWordTimestamps: true,
    beamSize: 0,
    detectLanguage: true,
    audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
    sampleRate: 16000,
    maxAlternatives: 0,
  });
}

function buildSTTOptions(options?: Partial<STTOptions>): STTOptions {
  return STTOptionsCtor.create({
    ...defaultSTTOptions(),
    ...options,
    language: options?.language ?? STTLanguage.STT_LANGUAGE_EN,
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
  audio: Uint8Array,
  options?: Partial<STTOptions>
): ArrayBuffer {
  const request = STTTranscriptionRequest.fromPartial({
    requestId: nextSTTRequestId(),
    audio: STTAudioSource.fromPartial({
      audioData: audio,
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
 *
 * Matches Swift SDK: `RunAnywhere.transcribe(_:options:)`.
 */
export async function transcribe(
  audio: Uint8Array,
  options?: Partial<STTOptions>
): Promise<STTOutput> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  await ensureServicesReady();
  const native = requireNativeModule();
  return decodeSTTOutput(
    await native.sttTranscribeProto(buildSTTRequestBytes(audio, options))
  );
}

/**
 * Stream-in / stream-out overload: mirrors Swift's `transcribeStream(audio:AsyncStream<Data>)`.
 *
 * Feeds the caller's PCM `Uint8Array` chunks into a native streaming
 * session as they arrive and yields `STTPartialResult` events live —
 * partials carry an incremental transcript and an `isFinal` flag; the
 * stream closes after the final event.
 *
 * Public contract (RunAnywhere+STT.swift):
 * - SDK not initialized / services not ready / no SPEECH_RECOGNITION model
 *   loaded → the stream finishes SILENTLY with zero events.
 * - Bridge errors surface as a terminal partial with `isFinal = true` and
 *   text `"STT stream failed: ..."` — never as a thrown error.
 * - If the session ends without an `isFinal` event, one empty
 *   `{ isFinal: true }` partial is synthesized.
 */
export function transcribeStream(
  audio: AsyncIterable<Uint8Array>,
  options: Partial<STTOptions> = {}
): AsyncIterable<STTPartialResult> {
  return transcribeStreamFromAsyncIterable(audio, options);
}

/**
 * Real session driver. Mirrors Swift `CppBridge+STT.swift`
 * `transcribeSessionStream`: load model on the streaming handle → register
 * proto callback + start session → feed chunks as they arrive → stop on
 * natural end (drains finals through the still-registered callback) or
 * cancel on consumer abort / feed failure.
 */
function transcribeStreamFromAsyncIterable(
  chunks: AsyncIterable<Uint8Array>,
  options: Partial<STTOptions>
): AsyncIterable<STTPartialResult> {
  return {
    [Symbol.asyncIterator](): AsyncIterator<STTPartialResult> {
      const queue: STTPartialResult[] = [];
      let resolver: ((value: IteratorResult<STTPartialResult>) => void) | null = null;
      let done = false;
      let started = false;
      let cancelled = false;
      let sawFinal = false;
      let sessionId: number | null = null;
      const input = chunks[Symbol.asyncIterator]();

      const finish = (): void => {
        done = true;
        if (resolver) {
          resolver({ value: undefined as unknown as STTPartialResult, done: true });
          resolver = null;
        }
      };

      const deliver = (partial: STTPartialResult): void => {
        if (done || cancelled) return;
        if (partial.isFinal) sawFinal = true;
        if (resolver) {
          resolver({ value: partial, done: false });
          resolver = null;
        } else {
          queue.push(partial);
        }
      };

      // Terminal failure partial — bridge errors never throw out of the
      // iterator (RunAnywhere+STT.swift:91-98).
      const failTerminally = (message: string, errorCode = 0): void => {
        deliver(
          STTPartialResultMessage.fromPartial({
            isFinal: true,
            text: message,
            finalOutput: STTOutputMessage.fromPartial({
              errorMessage: message,
              errorCode,
            }),
          })
        );
        finish();
      };

      // Event mapping per Swift STTStreamSessionContext.yield:
      // PARTIAL/ENDPOINT → partial if present; FINAL → merged final partial;
      // ERROR → terminal failure partial; STARTED/UNSPECIFIED ignored.
      const onEvent = (eventBytes: ArrayBuffer): void => {
        if (done || cancelled) return;
        let event;
        try {
          event = STTStreamEvent.decode(arrayBufferToBytes(eventBytes));
        } catch (error) {
          logger.warning(`Failed to decode STT stream event: ${String(error)}`);
          return;
        }
        switch (event.kind) {
          case STTStreamEventKind.STT_STREAM_EVENT_KIND_PARTIAL:
          case STTStreamEventKind.STT_STREAM_EVENT_KIND_ENDPOINT:
            if (event.partial) deliver(event.partial);
            break;
          case STTStreamEventKind.STT_STREAM_EVENT_KIND_FINAL: {
            const partial = STTPartialResultMessage.fromPartial(event.partial ?? {});
            partial.isFinal = true;
            if (event.finalOutput) {
              partial.finalOutput = event.finalOutput;
              if (!partial.text) partial.text = event.finalOutput.text;
            }
            deliver(partial);
            break;
          }
          case STTStreamEventKind.STT_STREAM_EVENT_KIND_ERROR:
            failTerminally(event.errorMessage || 'STT stream failed', event.errorCode);
            break;
          default:
            // STARTED / UNSPECIFIED — ignored.
            break;
        }
      };

      const cancelNativeSession = async (): Promise<void> => {
        if (sessionId == null) return;
        const id = sessionId;
        sessionId = null;
        try {
          await requireNativeModule().sttStreamCancel(id);
        } catch (error) {
          logger.warning(`sttStreamCancel failed: ${String(error)}`);
        }
      };

      const run = async (): Promise<void> => {
        // Not initialized / services not ready → finish silently with
        // zero events (Swift RunAnywhere+STT.swift:56-70).
        if (!isNativeModuleAvailable()) {
          finish();
          return;
        }
        const native = requireNativeModule();
        try {
          if (!(await native.isInitialized())) {
            finish();
            return;
          }
          await ensureServicesReady();
        } catch {
          finish();
          return;
        }

        // Lifecycle-resolved SPEECH_RECOGNITION model snapshot — missing
        // model → silent finish; missing path/id → terminal failure.
        let snapshot;
        try {
          snapshot = await currentModel(
            CurrentModelRequest.fromPartial({
              category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
              includeModelMetadata: true,
            })
          );
        } catch {
          finish();
          return;
        }
        if (!snapshot?.found) {
          finish();
          return;
        }
        const modelId = snapshot.modelId || snapshot.model?.id || '';
        const modelPath = snapshot.resolvedPath || snapshot.model?.localPath || '';
        const modelName = snapshot.model?.name || modelId;
        if (!modelId || !modelPath) {
          failTerminally('STT stream failed: loaded STT model is missing a resolved path');
          return;
        }

        // Load on the streaming handle, then start the session (callback is
        // registered before rac_stt_stream_start_proto on the native side).
        try {
          await native.sttStreamLoadModel(modelPath, modelId, modelName);
          if (cancelled) {
            finish();
            return;
          }
          sessionId = await native.sttStreamStart(
            encodeProtoMessage(buildSTTOptions(options), STTOptionsCtor),
            onEvent
          );
        } catch (error) {
          failTerminally(
            `STT stream failed: ${error instanceof Error ? error.message : String(error)}`
          );
          return;
        }
        if (cancelled) {
          await cancelNativeSession();
          finish();
          return;
        }

        // Feed pump: drive the caller's iterator manually (Hermes-safe),
        // skip empty chunks; feed/iterator failure → terminal failure
        // partial + cancel.
        const activeSessionId = sessionId;
        try {
          for (;;) {
            if (cancelled || done) break;
            const step = await input.next();
            if (step.done) break;
            const chunk = step.value;
            if (!chunk || chunk.byteLength === 0) continue;
            await native.sttStreamFeed(activeSessionId, bytesToArrayBuffer(chunk));
          }
        } catch (error) {
          failTerminally(
            `STT stream failed: ${error instanceof Error ? error.message : String(error)}`
          );
          await cancelNativeSession();
          return;
        }

        if (cancelled || done) {
          await cancelNativeSession();
          finish();
          return;
        }

        // Natural end: stop drains final events through the
        // still-registered callback before resolving.
        try {
          sessionId = null;
          await native.sttStreamStop(activeSessionId);
        } catch (error) {
          failTerminally(
            `STT stream failed: ${error instanceof Error ? error.message : String(error)}`
          );
          return;
        }

        // No isFinal seen → synthesize one empty terminal partial
        // (Swift RunAnywhere+STT.swift:86-90).
        if (!sawFinal && !done && !cancelled) {
          deliver(STTPartialResultMessage.fromPartial({ isFinal: true }));
        }
        finish();
      };

      const start = (): void => {
        if (started) return;
        started = true;
        void run();
      };

      return {
        async next(): Promise<IteratorResult<STTPartialResult>> {
          start();
          if (queue.length > 0) {
            return { value: queue.shift()!, done: false };
          }
          if (done) {
            return { value: undefined as unknown as STTPartialResult, done: true };
          }
          return new Promise<IteratorResult<STTPartialResult>>((resolve) => {
            resolver = resolve;
          });
        },
        async return(): Promise<IteratorResult<STTPartialResult>> {
          // Consumer cancel: stop the input source, cancel the native
          // session, suppress further event delivery.
          cancelled = true;
          try {
            await input.return?.();
          } catch {
            // Input iterator cleanup failures are non-fatal on cancel.
          }
          await cancelNativeSession();
          finish();
          return { value: undefined as unknown as STTPartialResult, done: true };
        },
      };
    },
  };
}
