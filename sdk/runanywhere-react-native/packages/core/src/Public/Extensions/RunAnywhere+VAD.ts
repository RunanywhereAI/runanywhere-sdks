/**
 * RunAnywhere+VAD.ts
 *
 * Voice Activity Detection extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+VAD.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '@runanywhere/native';

// ============================================================================
// Voice Activity Detection (VAD) Extension
// ============================================================================

/**
 * Load a VAD model
 */
export async function loadVADModel(
  modelPath: string,
  config?: Record<string, unknown>
): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.loadVADModel(
    modelPath,
    config ? JSON.stringify(config) : undefined
  );
}

/**
 * Check if a VAD model is loaded
 */
export async function isVADModelLoaded(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.isVADModelLoaded();
}

/**
 * Process audio for voice activity detection
 */
export async function processVAD(
  audioData: string | ArrayBuffer,
  sampleRate: number = 16000
): Promise<{ isSpeech: boolean; probability: number }> {
  if (!isNativeModuleAvailable()) {
    return { isSpeech: false, probability: 0 };
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

  const resultJson = await native.processVAD(audioBase64, sampleRate);
  try {
    return JSON.parse(resultJson);
  } catch {
    return { isSpeech: false, probability: 0 };
  }
}
