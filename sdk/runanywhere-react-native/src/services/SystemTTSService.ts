/**
 * SystemTTSService.ts
 *
 * System TTS Service implementation using native platform TTS APIs
 *
 * Platform Support:
 * - iOS: AVSpeechSynthesizer via TurboModule
 * - Android: TextToSpeech via TurboModule
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/TTS/TTSComponent.swift (SystemTTSService)
 */

import { NativeRunAnywhere } from '../native/NativeRunAnywhere';
import type { TTSService, VoiceInfo } from '../Core/Protocols/Voice/TTSService';
import type { TTSConfiguration } from '../Core/Models/Configuration/TTSConfiguration';
import type { TTSResult } from '../Core/Models/TTS/TTSResult';
import { SDKError, SDKErrorCode } from '../Public/Errors/SDKError';
import { Platform } from 'react-native';

/**
 * Native voice info from platform TTS
 */
interface NativeVoiceInfo {
  id?: string;
  identifier?: string;
  language?: string;
  name?: string;
  displayName?: string;
  gender?: 'male' | 'female' | 'neutral';
  isNeural?: boolean;
  quality?: 'low' | 'medium' | 'high' | 'enhanced';
  sampleUrl?: string;
}

/**
 * System TTS Service implementation using native platform TTS
 *
 * iOS: Uses AVSpeechSynthesizer
 * Android: Uses TextToSpeech
 */
export class SystemTTSService implements TTSService {
  // MARK: - Properties

  private _isReady: boolean = false;
  private _currentModel: string | null = null;
  private _isSynthesizing: boolean = false;
  private _availableVoices: string[] = [];

  // MARK: - TTSService Protocol Implementation

  /**
   * Initialize the TTS service
   */
  async initialize(_modelPath?: string | null): Promise<void> {
    try {
      // For system TTS, we don't need a model path
      // Just fetch available voices
      const voicesJson = await NativeRunAnywhere.getTTSVoices();
      const voices = JSON.parse(voicesJson);

      // Extract voice IDs/languages from voice info
      if (Array.isArray(voices)) {
        this._availableVoices = (voices as NativeVoiceInfo[])
          .map((v) => v.id || v.language || v.identifier || '')
          .filter(Boolean);
      }

      this._isReady = true;
      this._currentModel = 'system';
    } catch (error) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        `Failed to initialize System TTS: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  /**
   * Synthesize text to speech
   *
   * @param text - Text to synthesize
   * @param configuration - TTS configuration with voice, rate, pitch, etc.
   * @returns TTSResult with base64-encoded audio data
   */
  async synthesize(
    text: string,
    configuration?: TTSConfiguration
  ): Promise<TTSResult> {
    if (!this._isReady) {
      throw new SDKError(
        SDKErrorCode.ComponentNotReady,
        'System TTS service is not initialized'
      );
    }

    if (!text || text.trim().length === 0) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Text to synthesize cannot be empty'
      );
    }

    try {
      this._isSynthesizing = true;

      // Extract configuration parameters
      const voiceId = configuration?.voice || null;
      const speedRate = configuration?.speakingRate || 1.0;
      const pitchShift = configuration?.pitch || 1.0;

      // Call native TTS synthesis
      const resultJson = await NativeRunAnywhere.synthesize(
        text,
        voiceId,
        speedRate,
        pitchShift
      );

      const result = JSON.parse(resultJson);

      // Return TTSResult matching the expected interface
      return {
        audio: result.audio, // base64 encoded audio
        sampleRate: result.sampleRate || 22050,
        numSamples: result.numSamples || 0,
        duration: result.duration || 0,
      };
    } catch (error) {
      throw new SDKError(
        SDKErrorCode.GenerationFailed,
        `TTS synthesis failed: ${error instanceof Error ? error.message : String(error)}`
      );
    } finally {
      this._isSynthesizing = false;
    }
  }

  /**
   * Get available voices for TTS
   *
   * @returns Array of voice identifiers/languages
   */
  async getAvailableVoices(): Promise<string[]> {
    if (!this._isReady) {
      // Try to initialize if not ready
      await this.initialize();
    }
    return this._availableVoices;
  }

  /**
   * Get detailed voice information
   *
   * @returns Array of VoiceInfo objects with detailed voice metadata
   */
  async getVoiceInfo(): Promise<VoiceInfo[]> {
    try {
      const voicesJson = await NativeRunAnywhere.getTTSVoices();
      const voices = JSON.parse(voicesJson);

      if (!Array.isArray(voices)) {
        return [];
      }

      // Map native voice info to VoiceInfo interface
      return (voices as NativeVoiceInfo[])
        .filter((v) => v.id || v.identifier || v.language)
        .map(
          (v): VoiceInfo => ({
            id: v.id || v.identifier || v.language || 'unknown',
            name: v.name || v.displayName || v.language || 'Unknown Voice',
            language: v.language || 'en-US',
            gender: v.gender,
            isNeural: v.isNeural || v.quality === 'enhanced',
            quality: v.quality,
            sampleUrl: v.sampleUrl,
          })
        );
    } catch (error) {
      console.warn('Failed to get detailed voice info:', error);
      return [];
    }
  }

  /**
   * Check if service is ready
   */
  get isReady(): boolean {
    return this._isReady;
  }

  /**
   * Get current model identifier
   */
  get currentModel(): string | null {
    return this._currentModel;
  }

  /**
   * Check if currently synthesizing
   */
  get isSynthesizing(): boolean {
    return this._isSynthesizing;
  }

  /**
   * Clean up and release resources
   */
  async cleanup(): Promise<void> {
    try {
      // Stop any ongoing synthesis
      if (this._isSynthesizing) {
        NativeRunAnywhere.cancelTTS();
      }

      this._isReady = false;
      this._currentModel = null;
      this._isSynthesizing = false;
      this._availableVoices = [];
    } catch (error) {
      console.warn('Error during TTS cleanup:', error);
    }
  }

  /**
   * Stop current synthesis
   */
  async stop(): Promise<void> {
    try {
      NativeRunAnywhere.cancelTTS();
      this._isSynthesizing = false;
    } catch (error) {
      console.warn('Error stopping TTS:', error);
    }
  }
}

/**
 * Helper function to get available voices grouped by language
 *
 * @returns Map of language code to array of voice IDs
 */
export async function getVoicesByLanguage(): Promise<Map<string, VoiceInfo[]>> {
  const service = new SystemTTSService();
  await service.initialize();

  const voices = await service.getVoiceInfo();
  const voiceMap = new Map<string, VoiceInfo[]>();

  for (const voice of voices) {
    const lang = voice.language;
    if (!voiceMap.has(lang)) {
      voiceMap.set(lang, []);
    }
    voiceMap.get(lang)!.push(voice);
  }

  return voiceMap;
}

/**
 * Helper function to get default voice for a language
 *
 * @param language - Language code (e.g., 'en-US', 'es-ES')
 * @returns Default voice ID for the language, or null if not found
 */
export async function getDefaultVoice(
  language: string
): Promise<string | null> {
  const service = new SystemTTSService();
  await service.initialize();

  const voices = await service.getVoiceInfo();

  // Try exact match first
  let voice = voices.find((v) => v.language === language);

  // Try language prefix match (e.g., 'en' for 'en-US')
  if (!voice) {
    const langPrefix = language.split('-')[0];
    if (langPrefix) {
      voice = voices.find((v) => v.language.startsWith(langPrefix));
    }
  }

  // Return first available voice if no match
  if (!voice && voices.length > 0) {
    voice = voices[0];
  }

  return voice?.id || null;
}

/**
 * Platform-specific voice configuration
 */
export const PlatformVoices = {
  iOS: {
    SIRI_FEMALE_EN_US: 'com.apple.ttsbundle.siri_female_en-US_compact',
    SIRI_MALE_EN_US: 'com.apple.ttsbundle.siri_male_en-US_compact',
    SAMANTHA: 'com.apple.ttsbundle.Samantha-compact',
    ALEX: 'com.apple.ttsbundle.Alex-compact',
  },
  Android: {
    DEFAULT_EN_US: 'en-US',
    DEFAULT_ES_ES: 'es-ES',
    DEFAULT_FR_FR: 'fr-FR',
    DEFAULT_DE_DE: 'de-DE',
  },
};

/**
 * Get platform-specific default voice
 */
export function getPlatformDefaultVoice(): string {
  if (Platform.OS === 'ios') {
    return PlatformVoices.iOS.SIRI_FEMALE_EN_US;
  } else if (Platform.OS === 'android') {
    return PlatformVoices.Android.DEFAULT_EN_US;
  }
  return 'en-US';
}
