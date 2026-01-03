/**
 * SystemTTSService.ts
 *
 * System TTS service wrapper.
 * Delegates to native platform TTS.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/TTS/System/SystemTTSService.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '@runanywhere/native';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('SystemTTSService');

/**
 * TTS Voice
 */
export interface TTSVoice {
  id: string;
  name: string;
  language: string;
  quality: string;
}

/**
 * Platform-specific voices
 */
export const PlatformVoices = {
  ios: [] as TTSVoice[],
  android: [] as TTSVoice[],
};

/**
 * Get voices by language
 */
export async function getVoicesByLanguage(language: string): Promise<TTSVoice[]> {
  if (!isNativeModuleAvailable()) return [];

  try {
    const native = requireNativeModule();
    const json = await native.getTTSVoices();
    const voices: TTSVoice[] = JSON.parse(json);
    return voices.filter(v => v.language.startsWith(language));
  } catch (error) {
    logger.warning('Failed to get voices:', { error });
    return [];
  }
}

/**
 * Get default voice
 */
export async function getDefaultVoice(): Promise<TTSVoice | null> {
  if (!isNativeModuleAvailable()) return null;

  try {
    const native = requireNativeModule();
    const json = await native.getTTSVoices();
    const voices: TTSVoice[] = JSON.parse(json);
    return voices[0] ?? null;
  } catch {
    return null;
  }
}

/**
 * Get platform default voice
 */
export function getPlatformDefaultVoice(): TTSVoice | null {
  return null;
}

/**
 * System TTS Service
 */
export class SystemTTSService {
  private static _instance: SystemTTSService | null = null;

  static get shared(): SystemTTSService {
    if (!SystemTTSService._instance) {
      SystemTTSService._instance = new SystemTTSService();
    }
    return SystemTTSService._instance;
  }

  /**
   * Synthesize text to speech
   */
  async synthesize(
    text: string,
    voiceId?: string,
    speedRate = 1.0,
    pitchShift = 1.0
  ): Promise<string> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    return native.synthesize(text, voiceId ?? '', speedRate, pitchShift);
  }

  /**
   * Get available voices
   */
  async getVoices(): Promise<TTSVoice[]> {
    if (!isNativeModuleAvailable()) return [];

    const native = requireNativeModule();
    const json = await native.getTTSVoices();
    return JSON.parse(json);
  }

  /**
   * Cancel synthesis
   */
  async cancel(): Promise<void> {
    if (!isNativeModuleAvailable()) return;

    const native = requireNativeModule();
    await native.cancelTTS();
  }

  /**
   * Reset singleton (for testing)
   */
  static reset(): void {
    SystemTTSService._instance = null;
  }
}
