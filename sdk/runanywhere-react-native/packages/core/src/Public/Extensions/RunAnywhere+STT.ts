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
 * Streaming transcription with partial-result callback.
 *
 * Matches Swift SDK: `RunAnywhere.transcribeStream(audioData:options:onPartialResult:)`.
 */
export async function transcribeStream(
  audio: Uint8Array | string | ArrayBuffer,
  options: Partial<STTOptions> & {
    onPartialResult?: (partial: STTPartialResult) => void;
  } = {}
): Promise<STTOutput> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const onPartialResult = options.onPartialResult;
  let unsubscribe: (() => void) | null = null;

  if (onPartialResult) {
    unsubscribe = EventBus.onVoice((event) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const evt = event as any;
      if (evt.type === 'sttPartialResult') {
        onPartialResult({
          text: evt.text ?? '',
          isFinal: false,
          stability: typeof evt.confidence === 'number' ? evt.confidence : 0,
        });
      } else if (evt.type === 'sttCompleted' && unsubscribe) {
        unsubscribe();
      }
    });
  }

  try {
    const output = await transcribe(audio, options);
    if (onPartialResult) {
      onPartialResult({
        text: output.text,
        isFinal: true,
        stability: output.confidence,
      });
    }
    return output;
  } finally {
    if (unsubscribe) unsubscribe();
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
 * AsyncIterable variant of `transcribeStream`.
 *
 * Matches the LLM/VLM streaming primitives (`stream` + `result` + `cancel`).
 */
export async function transcribeStreamAsync(
  audio: Uint8Array | string | ArrayBuffer,
  options: Partial<STTOptions> = {}
): Promise<STTStreamingResult> {
  const queue: STTPartialResult[] = [];
  let resolver:
    | ((value: IteratorResult<STTPartialResult>) => void)
    | null = null;
  let done = false;
  let streamError: Error | null = null;
  let cancelled = false;

  let resolveResult!: (value: STTOutput) => void;
  let rejectResult!: (err: Error) => void;
  const resultPromise = new Promise<STTOutput>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });

  const pushPartial = (partial: STTPartialResult): void => {
    if (cancelled) return;
    if (resolver) {
      resolver({ value: partial, done: false });
      resolver = null;
    } else {
      queue.push(partial);
    }
  };

  transcribeStream(audio, { ...options, onPartialResult: pushPartial })
    .then((output) => {
      done = true;
      resolveResult(output);
      if (resolver) {
        resolver({ value: undefined as unknown as STTPartialResult, done: true });
        resolver = null;
      }
    })
    .catch((err: Error) => {
      streamError = err;
      done = true;
      rejectResult(err);
      if (resolver) {
        resolver({ value: undefined as unknown as STTPartialResult, done: true });
        resolver = null;
      }
    });

  async function* partialGenerator(): AsyncGenerator<STTPartialResult> {
    while (!done || queue.length > 0) {
      if (queue.length > 0) {
        yield queue.shift()!;
      } else if (!done) {
        const next = await new Promise<IteratorResult<STTPartialResult>>(
          (resolve) => {
            resolver = resolve;
          }
        );
        if (next.done) break;
        yield next.value;
      }
    }
    if (streamError) throw streamError;
  }

  const cancel = (): void => {
    cancelled = true;
    void stopStreamingTranscription();
    if (resolver) {
      done = true;
      resolver({ value: undefined as unknown as STTPartialResult, done: true });
      resolver = null;
    }
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
