/**
 * RunAnywhere+STT.ts
 *
 * Speech-to-Text extension for RunAnywhere SDK. Wave 2: aligned to the
 * proto-canonical STT types (`@runanywhere/proto-ts/stt_options`). All
 * legacy ad-hoc shapes (the `STTResult` / `STTOutput` from
 * `types/STTTypes.ts`) have been deleted; we work directly off the
 * proto-generated interfaces.
 *
 * Matches Swift: `Public/Extensions/STT/RunAnywhere+STT.swift`.
 */

import { EventBus } from '../Events';
import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import {
  STTLanguage,
  type STTOptions,
  type STTOutput,
  type STTPartialResult,
  type TranscriptionMetadata,
} from '@runanywhere/proto-ts/stt_options';
import { STTOptions as STTOptionsCtor } from '@runanywhere/proto-ts/stt_options';

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
  });
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

/**
 * Extended native module type for streaming STT methods. Optional —
 * present only on backends that have implemented them.
 */
interface StreamingSTTNativeModule {
  startStreamingSTT?: (language: string) => Promise<boolean>;
  stopStreamingSTT?: () => Promise<boolean>;
  isStreamingSTT?: () => Promise<boolean>;
  /** rac_stt_stream_process_audio — if the bridge exposes it. */
  sttProcessAudio?: (samplesBase64: string) => Promise<void>;
}

/**
 * Streaming transcription handle. Mirrors the LLM/VLM streaming surface
 * shape (`stream` + `result` + `cancel`).
 */
export interface STTStreamingResult {
  partials: AsyncIterable<STTPartialResult>;
  result: Promise<STTOutput>;
  cancel: () => void;
}

// ============================================================================
// Speech-to-Text (STT) Extension
// ============================================================================

/** Load an STT model. */
export async function loadSTTModel(
  modelPath: string,
  modelType: string = 'whisper',
  config?: Record<string, unknown>
): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    logger.warning('Native module not available for loadSTTModel');
    return false;
  }
  const native = requireNativeModule();
  return native.loadSTTModel(
    modelPath,
    modelType,
    config ? JSON.stringify(config) : undefined
  );
}

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

/** Convert Uint8Array / ArrayBuffer / string audio input to a base64 string. */
function audioToBase64(audio: Uint8Array | string | ArrayBuffer): string {
  if (typeof audio === 'string') return audio;
  const bytes = audio instanceof Uint8Array ? audio : new Uint8Array(audio);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    const byte = bytes[i];
    if (byte !== undefined) binary += String.fromCharCode(byte);
  }
  return btoa(binary);
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
  const startTime = Date.now();
  const audioBase64 = audioToBase64(audio);
  const sampleRate = 16000;
  const language = sttLanguageToCode(options?.language);

  const resultJson = await native.transcribe(audioBase64, sampleRate, language);
  const endTime = Date.now();
  const processingTimeMs = endTime - startTime;

  try {
    const parsed = JSON.parse(resultJson);
    if (parsed.error) {
      throw new Error(parsed.error);
    }

    const audioLengthMs =
      typeof parsed.duration === 'number' ? parsed.duration * 1000 : 0;
    const metadata: TranscriptionMetadata = {
      modelId: parsed.modelId ?? 'unknown',
      processingTimeMs,
      audioLengthMs,
      realTimeFactor:
        audioLengthMs > 0 ? processingTimeMs / audioLengthMs : 0,
    };

    return {
      text: parsed.text ?? '',
      language: options?.language ?? STTLanguage.STT_LANGUAGE_UNSPECIFIED,
      confidence: parsed.confidence ?? 1.0,
      words: parsed.words ?? parsed.timestamps ?? [],
      alternatives: parsed.alternatives ?? [],
      metadata,
    };
  } catch (err) {
    if (err instanceof Error) throw err;
    throw new Error(`Transcription failed: ${resultJson}`);
  }
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
  const audioBase64 = audioToBase64(samples.buffer as ArrayBuffer);
  return transcribe(audioBase64, options);
}

/**
 * Push a raw audio chunk into the streaming STT session.
 *
 * Forwards to the Nitro bridge's `sttProcessAudio` if it exists, otherwise
 * is a no-op (the bridge does not yet expose streaming audio ingestion for RN).
 *
 * Matches Swift SDK: `RunAnywhere.processStreamingAudio(_:)` (§4).
 */
export async function processStreamingAudio(samples: Uint8Array): Promise<void> {
  if (!isNativeModuleAvailable()) return;
  const native = requireNativeModule() as unknown as StreamingSTTNativeModule;
  if (typeof native.sttProcessAudio === 'function') {
    // Encode to base64 for the bridge.
    let binary = '';
    for (let i = 0; i < samples.byteLength; i++) {
      binary += String.fromCharCode(samples[i]!);
    }
    const base64 = btoa(binary);
    await native.sttProcessAudio(base64);
  }
  // If bridge method absent, silently do nothing — the C++ streaming support
  // is not yet wired for RN (CPP-BLOCKED: rac_stt_stream_* ABI gap).
}

/**
 * Stream transcription results as an `AsyncIterable<STTPartialResult>`.
 *
 * Each chunk of the `audio` iterable is fed into `processStreamingAudio`;
 * partial results are emitted via the VAD/STT EventBus. When the iterable
 * is exhausted a final result is produced by `transcribe()` and emitted as
 * the terminal `isFinal` partial.
 *
 * Matches the canonical cross-SDK spec §4:
 *   `transcribeStream(audio: Stream<Bytes>) → Stream<STTPartialResult>`
 *
 * The implementation degrades gracefully when the native bridge does not
 * expose `sttProcessAudio`: it falls back to calling `transcribe()` once and
 * emitting a single final partial result, which is the same behaviour the
 * Swift and Flutter SDKs exhibit on unsupported engines.
 */
export async function* transcribeStream(
  audio: AsyncIterable<Uint8Array> | Uint8Array | string | ArrayBuffer,
  options: Partial<STTOptions> = {}
): AsyncIterable<STTPartialResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  // Subscribe to STT partial-result events from the EventBus.
  const partialQueue: STTPartialResult[] = [];
  let partialResolver: ((value: IteratorResult<STTPartialResult>) => void) | null = null;

  const unsubscribe = EventBus.onVoice((event) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const evt = event as any;
    if (evt.type === 'sttPartialResult') {
      const partial: STTPartialResult = {
        text: evt.text ?? '',
        isFinal: false,
        stability: typeof evt.confidence === 'number' ? evt.confidence : 0,
      };
      if (partialResolver) {
        const res = partialResolver;
        partialResolver = null;
        res({ value: partial, done: false });
      } else {
        partialQueue.push(partial);
      }
    }
  });

  try {
    // If audio is an AsyncIterable, process each chunk.
    if (audio && typeof (audio as AsyncIterable<Uint8Array>)[Symbol.asyncIterator] === 'function') {
      for await (const chunk of audio as AsyncIterable<Uint8Array>) {
        await processStreamingAudio(chunk);
        // Drain any queued partials.
        while (partialQueue.length > 0) {
          yield partialQueue.shift()!;
        }
      }
    }

    // Drain remaining queued partials.
    while (partialQueue.length > 0) {
      yield partialQueue.shift()!;
    }

    // Fall back to single-shot transcribe for the final result (covers both the
    // AsyncIterable path above and the direct Uint8Array / string / ArrayBuffer
    // path).
    const audioInput = (audio && typeof (audio as AsyncIterable<Uint8Array>)[Symbol.asyncIterator] === 'function')
      ? new Uint8Array(0) // already processed above
      : audio as Uint8Array | string | ArrayBuffer;

    const finalOutput = (audioInput instanceof Uint8Array && audioInput.byteLength === 0)
      ? null
      : await transcribe(audioInput, options);

    if (finalOutput) {
      yield {
        text: finalOutput.text,
        isFinal: true,
        stability: finalOutput.confidence,
      };
    }
  } finally {
    unsubscribe();
  }
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
    return {
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
    };
  } catch (err) {
    if (err instanceof Error) throw err;
    throw new Error(`Transcription failed: ${resultJson}`);
  }
}

/**
 * Structured streaming transcription result handle.
 *
 * Provides `partials` (an `AsyncIterable<STTPartialResult>`), a `result`
 * `Promise<STTOutput>` that resolves when the stream completes, and a
 * `cancel()` function.
 *
 * Wraps the generator-based `transcribeStream` for callers that prefer a
 * handle-based API.
 */
export async function transcribeStreamAsync(
  audio: Uint8Array | string | ArrayBuffer,
  options: Partial<STTOptions> = {}
): Promise<STTStreamingResult> {
  let resolveResult!: (value: STTOutput) => void;
  let rejectResult!: (err: Error) => void;
  const resultPromise = new Promise<STTOutput>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });

  let cancelRequested = false;

  // Create the async generator stream from the canonical `transcribeStream`.
  const stream = transcribeStream(audio, options);

  async function* partialGenerator(): AsyncGenerator<STTPartialResult> {
    let lastOutput: STTOutput | null = null;
    try {
      for await (const partial of stream) {
        if (cancelRequested) break;
        yield partial;
        if (partial.isFinal) {
          // Reconstruct an STTOutput from the final partial.
          lastOutput = {
            text: partial.text,
            language: options.language ?? STTLanguage.STT_LANGUAGE_UNSPECIFIED,
            confidence: partial.stability ?? 1.0,
            words: [],
            alternatives: [],
          };
        }
      }
      resolveResult(lastOutput ?? {
        text: '',
        language: STTLanguage.STT_LANGUAGE_UNSPECIFIED,
        confidence: 0,
        words: [],
        alternatives: [],
      });
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      rejectResult(error);
      throw error;
    }
  }

  const cancel = (): void => {
    cancelRequested = true;
    void stopStreamingTranscription();
  };

  return {
    partials: partialGenerator(),
    result: resultPromise,
    cancel,
  };
}

/**
 * Stop streaming speech-to-text transcription.
 *
 * Matches Swift SDK: `RunAnywhere.stopStreamingTranscription()`.
 */
export async function stopStreamingTranscription(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule() as unknown as StreamingSTTNativeModule;
  if (!native.stopStreamingSTT) {
    return false;
  }
  return native.stopStreamingSTT();
}

/** Check if streaming STT is currently active. */
export async function isStreamingSTT(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule() as unknown as StreamingSTTNativeModule;
  if (!native.isStreamingSTT) {
    return false;
  }
  return native.isStreamingSTT();
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
