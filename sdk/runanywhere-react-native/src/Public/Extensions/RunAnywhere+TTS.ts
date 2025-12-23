/**
 * RunAnywhere+TTS.ts
 *
 * Text-to-Speech extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+TTS.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import type { TTSConfiguration, TTSResult } from '../../types';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('RunAnywhere.TTS');

// ============================================================================
// Text-to-Speech (TTS) Extension
// ============================================================================

/**
 * Load a TTS model
 */
export async function loadTTSModel(
  modelPath: string,
  modelType: string = 'piper',
  config?: Record<string, unknown>
): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    logger.warning('Native module not available for loadTTSModel');
    return false;
  }
  const native = requireNativeModule();
  return native.loadTTSModel(
    modelPath,
    modelType,
    config ? JSON.stringify(config) : undefined
  );
}

/**
 * Check if a TTS model is loaded
 */
export async function isTTSModelLoaded(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.isTTSModelLoaded();
}

/**
 * Unload the current TTS model
 */
export async function unloadTTSModel(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.unloadTTSModel();
}

/**
 * Synthesize text to speech
 */
export async function synthesize(
  text: string,
  configuration?: TTSConfiguration
): Promise<TTSResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();

  const voiceId = configuration?.voice ?? '';
  const speedRate = configuration?.rate ?? 1.0;
  const pitchShift = configuration?.pitch ?? 1.0;

  const resultJson = await native.synthesize(text, voiceId, speedRate, pitchShift);

  try {
    const result = JSON.parse(resultJson);
    return {
      audio: result.audio ?? '',
      sampleRate: result.sampleRate ?? 22050,
      numSamples: result.numSamples ?? 0,
      duration: result.numSamples ? result.numSamples / result.sampleRate : 0,
    };
  } catch {
    if (resultJson.includes('error')) {
      throw new Error(resultJson);
    }
    return {
      audio: resultJson,
      sampleRate: 22050,
      numSamples: 0,
      duration: 0,
    };
  }
}

/**
 * Get available TTS voices
 */
export async function getTTSVoices(): Promise<string[]> {
  if (!isNativeModuleAvailable()) {
    return [];
  }
  const native = requireNativeModule();
  const voicesJson = await native.getTTSVoices();
  try {
    return JSON.parse(voicesJson);
  } catch {
    return voicesJson ? [voicesJson] : [];
  }
}

/**
 * Cancel ongoing TTS synthesis
 */
export function cancelTTS(): void {
  if (!isNativeModuleAvailable()) {
    return;
  }
  const native = requireNativeModule();
  native.cancelTTS();
}
