/**
 * RunAnywhere+STT.ts
 *
 * Speech-to-Text extension. Aligned to proto-canonical STT shapes
 * (`@runanywhere/proto-ts/stt_options`). All ad-hoc local result/output
 * shapes have been deleted; we work directly off the proto-generated
 * interfaces. Path-first loading and EventBus fallback streaming have
 * been removed — model loading goes through `loadModelLifecycle` and
 * streaming is driven by the native `sttTranscribeStreamProto` callback.
 *
 * Matches Swift: `Public/Extensions/STT/RunAnywhere+STT.swift`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import {
  STTLanguage,
  type STTOptions,
  type STTOutput,
  type STTPartialResult,
} from '@runanywhere/proto-ts/stt_options';
import {
  STTOptions as STTOptionsCtor,
  STTOutput as STTOutputMessage,
  STTPartialResult as STTPartialResultMessage,
} from '@runanywhere/proto-ts/stt_options';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';

const logger = new SDKLogger('RunAnywhere.STT');

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

// ============================================================================
// Speech-to-Text (STT) Extension
// ============================================================================

/** Check if an STT model is loaded. */
export async function isSTTModelLoaded(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.isSTTModelLoaded();
}

/** Unload the current STT model. */
export async function unloadSTTModel(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.unloadSTTModel();
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
    throw new Error('STT proto transcription returned an empty result');
  }
  return STTOutputMessage.decode(bytes);
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
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();
  const audioBytes = audioToArrayBuffer(audio);
  const optionBytes = bytesToArrayBuffer(
    STTOptionsCtor.encode(buildSTTOptions(options)).finish()
  );
  return decodeSTTOutput(await native.sttTranscribeProto(audioBytes, optionBytes));
}

/**
 * Simple voice transcription — returns just the text.
 *
 * Matches Swift SDK: `RunAnywhere.transcribe(_:)`.
 */
export async function transcribeSimple(
  audio: string | ArrayBuffer
): Promise<string> {
  const result = await transcribe(audio);
  return result.text;
}

/**
 * Transcribe an audio buffer.
 *
 * Matches Swift SDK: `RunAnywhere.transcribeBuffer(_:options:)`.
 */
export async function transcribeBuffer(
  samples: Float32Array,
  options?: Partial<STTOptions>
): Promise<STTOutput> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  return transcribe(samples.buffer as ArrayBuffer, options);
}

/**
 * Stream transcription results as an `AsyncIterable<STTPartialResult>` over
 * the native `sttTranscribeStreamProto` proto-byte callback.
 *
 * Matches the canonical cross-SDK spec §4:
 *   `transcribeStream(audio: Bytes) → Stream<STTPartialResult>`
 */
export function transcribeStream(
  audio: Uint8Array | string | ArrayBuffer,
  options: Partial<STTOptions> = {}
): AsyncIterable<STTPartialResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();
  const audioBytes = audioToArrayBuffer(audio);
  const optionBytes = bytesToArrayBuffer(
    STTOptionsCtor.encode(buildSTTOptions(options)).finish()
  );

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
          .sttTranscribeStreamProto(audioBytes, optionBytes, (partialBytes: ArrayBuffer) => {
            try {
              const partial = STTPartialResultMessage.decode(arrayBufferToBytes(partialBytes));
              if (resolver) {
                resolver({ value: partial, done: false });
                resolver = null;
              } else {
                queue.push(partial);
              }
              if (partial.isFinal) finish();
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

/**
 * Transcribe audio from a file path.
 *
 * Matches Swift SDK: `RunAnywhere.transcribeFile(_:options:)`.
 */
export async function transcribeFile(
  filePath: string,
  options?: Partial<STTOptions>
): Promise<STTOutput> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();
  const language = sttLanguageToCode(options?.language);
  const startTime = Date.now();
  const resultJson = await native.transcribeFile(filePath, language);
  const endTime = Date.now();
  const processingTimeMs = endTime - startTime;

  try {
    const parsed = JSON.parse(resultJson);
    if (parsed.error) throw new Error(parsed.error);

    const audioLengthMs =
      typeof parsed.duration === 'number' ? parsed.duration * 1000 : 0;
    return STTOutputMessage.fromPartial({
      text: parsed.text ?? '',
      language: options?.language ?? STTLanguage.STT_LANGUAGE_UNSPECIFIED,
      confidence: parsed.confidence ?? 1.0,
      words: parsed.words ?? parsed.timestamps ?? [],
      alternatives: parsed.alternatives ?? [],
      metadata: {
        modelId: parsed.modelId ?? 'unknown',
        processingTimeMs,
        audioLengthMs,
        realTimeFactor:
          audioLengthMs > 0 ? processingTimeMs / audioLengthMs : 0,
      },
      timestampMs: Date.now(),
      durationMs: audioLengthMs,
    });
  } catch (err) {
    if (err instanceof Error) throw err;
    throw new Error(`Transcription failed: ${resultJson}`);
  }
}

/** Map a proto `STTLanguage` enum value to the BCP-47 string the native bridge expects. */
function sttLanguageToCode(language?: STTLanguage): string {
  switch (language) {
    case STTLanguage.STT_LANGUAGE_AUTO:
      return 'auto';
    case STTLanguage.STT_LANGUAGE_EN:
      return 'en';
    case STTLanguage.STT_LANGUAGE_ES:
      return 'es';
    case STTLanguage.STT_LANGUAGE_FR:
      return 'fr';
    case STTLanguage.STT_LANGUAGE_DE:
      return 'de';
    case STTLanguage.STT_LANGUAGE_ZH:
      return 'zh';
    case STTLanguage.STT_LANGUAGE_JA:
      return 'ja';
    case STTLanguage.STT_LANGUAGE_KO:
      return 'ko';
    case STTLanguage.STT_LANGUAGE_IT:
      return 'it';
    case STTLanguage.STT_LANGUAGE_PT:
      return 'pt';
    case STTLanguage.STT_LANGUAGE_AR:
      return 'ar';
    case STTLanguage.STT_LANGUAGE_RU:
      return 'ru';
    case STTLanguage.STT_LANGUAGE_HI:
      return 'hi';
    default:
      return 'en';
  }
}

// ============================================================================
// Introspection
// ============================================================================

interface STTIntrospectionNativeModule {
  currentSTTModel?: () => Promise<string>;
  getCurrentSTTModelId?: () => Promise<string>;
}

/**
 * Get the currently loaded STT model ID, or `null` if none.
 *
 * Matches Swift: `RunAnywhere.currentSTTModel`.
 */
export async function currentSTTModel(): Promise<string | null> {
  if (!isNativeModuleAvailable()) return null;
  const native = requireNativeModule() as unknown as STTIntrospectionNativeModule;
  const fn = native.currentSTTModel ?? native.getCurrentSTTModelId;
  if (!fn) return null;
  const id = await fn.call(native);
  return id && id.length > 0 ? id : null;
}
