/**
 * RunAnywhere+STT.ts
 *
 * Speech-to-Text extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+STT.swift
 */

import { EventBus } from '../Events';
import { requireNativeModule, isNativeModuleAvailable } from '@runanywhere/native';
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
      throw new Error(resultJson);
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
 * Transcribe audio with streaming callbacks
 * Matches Swift SDK: RunAnywhere.transcribeStream(audioData:options:onPartialResult:)
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

// ============================================================================
// Streaming STT (Real-time)
// ============================================================================

/**
 * Start streaming speech-to-text transcription
 * @deprecated Use transcribeStream() for better API parity with Swift SDK
 */
export async function startStreamingSTT(
  language: string = 'en',
  onPartial?: (text: string, confidence: number) => void,
  onFinal?: (text: string, confidence: number) => void,
  onError?: (error: string) => void
): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    logger.warning('Native module not available for startStreamingSTT');
    return false;
  }
  const native = requireNativeModule();

  if (onPartial || onFinal || onError) {
    EventBus.onVoice((event) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const evt = event as any;
      if (evt.type === 'sttPartialResult' && onPartial) {
        onPartial(evt.text || '', evt.confidence || 0);
      } else if (evt.type === 'sttCompleted' && onFinal) {
        onFinal(evt.text || '', evt.confidence || 0);
      } else if (evt.type === 'sttFailed' && onError) {
        onError(evt.error || 'Unknown error');
      }
    });
  }

  return native.startStreamingSTT(language);
}

/**
 * Stop streaming speech-to-text transcription
 */
export async function stopStreamingSTT(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.stopStreamingSTT();
}

/**
 * Check if streaming STT is currently active
 */
export async function isStreamingSTT(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.isStreamingSTT();
}
