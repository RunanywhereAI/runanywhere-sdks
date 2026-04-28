/**
 * RunAnywhere+STT.ts
 *
 * Speech-to-Text extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+STT.swift
 */

import { EventBus } from '../Events';
import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import type { STTOptions, STTResult } from '../../types';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  STTOutput,
  STTPartialResult,
  STTStreamCallback,
  STTStreamOptions,
  TranscriptionMetadata,
} from '../../types/STTTypes';

const logger = new SDKLogger('RunAnywhere.STT');

/**
 * Extended native module type for streaming STT methods
 * These methods are optional and may not be implemented in all backends
 */
interface StreamingSTTNativeModule {
  startStreamingSTT?: (language: string) => Promise<boolean>;
  stopStreamingSTT?: () => Promise<boolean>;
  isStreamingSTT?: () => Promise<boolean>;
}

/**
 * Streaming transcription result returning AsyncIterable for partials.
 * Mirrors the Swift `transcribeStream` shape and the LLM/VLM streaming
 * pattern (`stream` + `result` + `cancel`).
 */
export interface STTStreamingResult {
  /** Async iterator over partial transcription updates */
  partials: AsyncIterable<STTPartialResult>;

  /** Promise that resolves to the final STT output */
  result: Promise<STTOutput>;

  /** Cancel the streaming transcription */
  cancel: () => void;
}

// ============================================================================
// Speech-to-Text (STT) Extension
// ============================================================================

/**
 * Load an STT model
 */
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

/**
 * Check if an STT model is loaded
 */
export async function isSTTModelLoaded(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.isSTTModelLoaded();
}

/**
 * Unload the current STT model
 */
export async function unloadSTTModel(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.unloadSTTModel();
}

/**
 * Simple voice transcription
 * Matches Swift SDK: RunAnywhere.transcribe(_:)
 *
 * @param audioData Audio data (base64 string or ArrayBuffer)
 * @returns Transcribed text
 */
export async function transcribeSimple(
  audioData: string | ArrayBuffer
): Promise<string> {
  const result = await transcribe(audioData);
  return result.text;
}

/**
 * Transcribe audio data with full options
 * Matches Swift SDK: RunAnywhere.transcribeWithOptions(_:options:)
 */
export async function transcribe(
  audioData: string | ArrayBuffer,
  options?: STTOptions
): Promise<STTResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();

  let audioBase64: string;
  if (typeof audioData === 'string') {
    audioBase64 = audioData;
  } else {
    const bytes = new Uint8Array(audioData);
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      const byte = bytes[i];
      if (byte !== undefined) {
        binary += String.fromCharCode(byte);
      }
    }
    audioBase64 = btoa(binary);
  }

  const sampleRate = options?.sampleRate ?? 16000;
  const language = options?.language;

  const resultJson = await native.transcribe(audioBase64, sampleRate, language);

  try {
    const result = JSON.parse(resultJson);
    if (result.error) {
      throw new Error(result.error);
    }
    return {
      text: result.text ?? '',
      segments: result.segments ?? [],
      language: result.language,
      confidence: result.confidence ?? 1.0,
      duration: result.duration ?? 0,
      alternatives: result.alternatives ?? [],
    };
  } catch (err) {
    if (err instanceof Error) throw err;
    if (resultJson.includes('error')) {
      const errorMatch = resultJson.match(/"error":\s*"([^"]+)"/);
      throw new Error(errorMatch ? errorMatch[1] : resultJson);
    }
    return {
      text: resultJson,
      segments: [],
      confidence: 1.0,
      duration: 0,
      alternatives: [],
    };
  }
}

/**
 * Transcribe audio buffer (Float32Array)
 * Matches Swift SDK: RunAnywhere.transcribeBuffer(_:language:)
 */
export async function transcribeBuffer(
  samples: Float32Array,
  options?: STTOptions
): Promise<STTOutput> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const startTime = Date.now();
  const native = requireNativeModule();

  // Convert Float32Array to base64
  const bytes = new Uint8Array(samples.buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    const byte = bytes[i];
    if (byte !== undefined) {
      binary += String.fromCharCode(byte);
    }
  }
  const audioBase64 = btoa(binary);

  const sampleRate = options?.sampleRate ?? 16000;
  const language = options?.language ?? 'en';

  const resultJson = await native.transcribe(audioBase64, sampleRate, language);
  const endTime = Date.now();
  const processingTime = (endTime - startTime) / 1000;

  try {
    const result = JSON.parse(resultJson);

    // Estimate audio length from samples
    const audioLength = samples.length / sampleRate;

    const metadata: TranscriptionMetadata = {
      modelId: 'unknown',
      processingTime,
      audioLength,
      realTimeFactor: processingTime / audioLength,
    };

    return {
      text: result.text ?? '',
      confidence: result.confidence ?? 1.0,
      wordTimestamps: result.timestamps,
      detectedLanguage: result.language,
      alternatives: result.alternatives,
      metadata,
    };
  } catch {
    throw new Error(`Transcription failed: ${resultJson}`);
  }
}

/**
 * Transcribe audio with streaming partial results.
 *
 * Matches Swift SDK: RunAnywhere.transcribeStream(audioData:options:onPartialResult:).
 *
 * Both calling styles are supported:
 *  - Callback style: pass `options.onPartialResult` and `await` the
 *    returned Promise<STTOutput>. This is the legacy shape and matches
 *    the Swift signature.
 *  - AsyncIterable style: use `transcribeStreamAsync()` which returns a
 *    `STTStreamingResult { partials, result, cancel }` consistent with
 *    the LLM / VLM streaming primitives.
 *
 * @param audioData Audio data to transcribe
 * @param options Stream options with callback
 * @returns Final transcription output
 */
export async function transcribeStream(
  audioData: string | ArrayBuffer,
  options: STTStreamOptions
): Promise<STTOutput> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const startTime = Date.now();
  const native = requireNativeModule();

  let audioBase64: string;
  let audioSize: number;

  if (typeof audioData === 'string') {
    audioBase64 = audioData;
    audioSize = atob(audioData).length;
  } else {
    const bytes = new Uint8Array(audioData);
    audioSize = bytes.byteLength;
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      const byte = bytes[i];
      if (byte !== undefined) {
        binary += String.fromCharCode(byte);
      }
    }
    audioBase64 = btoa(binary);
  }

  const sampleRate = options?.sampleRate ?? 16000;
  const language = options?.language ?? 'en';

  // Set up event listener for partial results
  let finalText = '';
  let finalConfidence = 1.0;

  if (options.onPartialResult) {
    const unsubscribe = EventBus.onVoice((event) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const evt = event as any;
      if (evt.type === 'sttPartialResult') {
        const partialResult: STTPartialResult = {
          transcript: evt.text ?? '',
          confidence: evt.confidence,
          isFinal: false,
        };
        options.onPartialResult?.(partialResult);
      } else if (evt.type === 'sttCompleted') {
        finalText = evt.text ?? '';
        finalConfidence = evt.confidence ?? 1.0;
        unsubscribe();
      }
    });
  }

  // Transcribe
  const resultJson = await native.transcribe(audioBase64, sampleRate, language);
  const endTime = Date.now();
  const processingTime = (endTime - startTime) / 1000;

  try {
    const result = JSON.parse(resultJson);

    // Estimate audio length
    const bytesPerSample = 2; // 16-bit
    const audioLength = audioSize / (sampleRate * bytesPerSample);

    const metadata: TranscriptionMetadata = {
      modelId: 'unknown',
      processingTime,
      audioLength,
      realTimeFactor: processingTime / audioLength,
    };

    // Emit final partial result
    if (options.onPartialResult) {
      options.onPartialResult({
        transcript: result.text ?? '',
        confidence: result.confidence ?? 1.0,
        isFinal: true,
      });
    }

    return {
      text: result.text ?? finalText,
      confidence: result.confidence ?? finalConfidence,
      wordTimestamps: result.timestamps,
      detectedLanguage: result.language,
      alternatives: result.alternatives,
      metadata,
    };
  } catch {
    throw new Error(`Streaming transcription failed: ${resultJson}`);
  }
}

/**
 * Transcribe audio from a file path
 */
export async function transcribeFile(
  filePath: string,
  options?: STTOptions
): Promise<STTResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();

  const language = options?.language ?? 'en';
  const resultJson = await native.transcribeFile(filePath, language);

  try {
    const result = JSON.parse(resultJson);
    if (result.error) {
      throw new Error(result.error);
    }
    return {
      text: result.text ?? '',
      segments: result.segments ?? [],
      language: result.language,
      confidence: result.confidence ?? 1.0,
      duration: result.duration ?? 0,
      alternatives: result.alternatives ?? [],
    };
  } catch {
    if (resultJson.includes('error')) {
      const errorMatch = resultJson.match(/"error":\s*"([^"]+)"/);
      throw new Error(errorMatch ? errorMatch[1] : resultJson);
    }
    return {
      text: resultJson,
      segments: [],
      confidence: 1.0,
      duration: 0,
      alternatives: [],
    };
  }
}

/**
 * AsyncIterable variant of `transcribeStream`.
 *
 * Returns `{ partials, result, cancel }` mirroring the LLM/VLM streaming
 * primitives. Use this when you want to consume partials with
 * `for await ... of partials`.
 *
 * Matches the Swift `RunAnywhere.transcribeStream(_:)` AsyncStream shape
 * (callback-based on the Swift side too, but exposed as `AsyncStream`).
 *
 * Example:
 * ```ts
 * const streaming = await transcribeStreamAsync(audioData, { language: 'en' });
 * for await (const partial of streaming.partials) {
 *   console.log(partial.transcript);
 * }
 * const final = await streaming.result;
 * ```
 */
export async function transcribeStreamAsync(
  audioData: string | ArrayBuffer,
  options: STTOptions = {}
): Promise<STTStreamingResult> {
  const queue: STTPartialResult[] = [];
  let resolver: ((value: IteratorResult<STTPartialResult>) => void) | null = null;
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

  // Drive the underlying callback-based API.
  transcribeStream(audioData, {
    ...options,
    onPartialResult: pushPartial,
  })
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

// ============================================================================
// Streaming STT (Real-time)
// ============================================================================

// v3.1: startStreamingSTT DELETED. Use transcribeStream() which provides
// the same callback-based streaming via the canonical proto path.

/**
 * Stop streaming speech-to-text transcription.
 *
 * Matches Swift SDK: `RunAnywhere.stopStreamingTranscription()`.
 * The legacy `stopStreamingSTT` name is retained as a re-export below
 * for backwards compatibility.
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

/**
 * @deprecated Use `stopStreamingTranscription` for parity with the Swift
 * SDK. This alias is kept for back-compat and will be removed in a future
 * version.
 */
export const stopStreamingSTT = stopStreamingTranscription;

/**
 * Check if streaming STT is currently active
 */
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
