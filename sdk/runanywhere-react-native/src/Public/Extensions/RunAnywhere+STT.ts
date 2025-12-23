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
 * Transcribe audio data
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
// Streaming STT
// ============================================================================

/**
 * Start streaming speech-to-text transcription
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
