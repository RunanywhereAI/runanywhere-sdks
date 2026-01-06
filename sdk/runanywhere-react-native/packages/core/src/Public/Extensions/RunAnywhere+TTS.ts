/**
 * RunAnywhere+TTS.ts
 *
 * Text-to-Speech extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+TTS.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import type { TTSConfiguration, TTSResult } from '../../types';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { AudioPlaybackManager } from '../../Features/VoiceSession/AudioPlaybackManager';
import type {
  TTSOptions,
  TTSOutput,
  TTSSpeakResult,
  TTSVoiceInfo,
  TTSStreamChunkCallback,
  TTSSynthesisMetadata,
} from '../../types/TTSTypes';

const logger = new SDKLogger('RunAnywhere.TTS');

// Internal audio playback manager for speak() functionality
let ttsAudioPlayback: AudioPlaybackManager | null = null;

function getAudioPlayback(): AudioPlaybackManager {
  if (!ttsAudioPlayback) {
    ttsAudioPlayback = new AudioPlaybackManager();
  }
  return ttsAudioPlayback;
}

// ============================================================================
// Voice Loading
// ============================================================================

/**
 * Load a TTS model/voice
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
 * Load a TTS voice by ID
 * Matches Swift SDK: RunAnywhere.loadTTSVoice(_:)
 */
export async function loadTTSVoice(voiceId: string): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  logger.info(`Loading TTS voice: ${voiceId}`);
  const native = requireNativeModule();

  // Get model info to find the voice path
  const modelInfoJson = await native.getModelInfo(voiceId);
  const modelInfo = JSON.parse(modelInfoJson);

  if (!modelInfo.localPath) {
    throw new Error(`Voice '${voiceId}' is not downloaded`);
  }

  const loaded = await native.loadTTSModel(modelInfo.localPath, 'piper');
  if (!loaded) {
    throw new Error(`Failed to load voice '${voiceId}'`);
  }

  logger.info(`TTS voice loaded: ${voiceId}`);
}

/**
 * Unload the current TTS voice
 * Matches Swift SDK: RunAnywhere.unloadTTSVoice()
 */
export async function unloadTTSVoice(): Promise<void> {
  if (!isNativeModuleAvailable()) {
    return;
  }
  const native = requireNativeModule();
  await native.unloadTTSModel();
  logger.info('TTS voice unloaded');
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
 * Check if a TTS voice is loaded
 * Matches Swift SDK: RunAnywhere.isTTSVoiceLoaded
 */
export async function isTTSVoiceLoaded(): Promise<boolean> {
  return isTTSModelLoaded();
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

// ============================================================================
// Voice Management
// ============================================================================

/**
 * Get available TTS voices
 * Matches Swift SDK: RunAnywhere.availableTTSVoices
 */
export async function availableTTSVoices(): Promise<string[]> {
  if (!isNativeModuleAvailable()) {
    return [];
  }

  const native = requireNativeModule();
  const voicesJson = await native.getTTSVoices();

  try {
    const voices = JSON.parse(voicesJson);
    if (Array.isArray(voices)) {
      return voices.map((v: TTSVoiceInfo | string) =>
        typeof v === 'string' ? v : v.id
      );
    }
    return [];
  } catch {
    return voicesJson ? [voicesJson] : [];
  }
}

/**
 * Get detailed voice information
 */
export async function getTTSVoiceInfo(): Promise<TTSVoiceInfo[]> {
  if (!isNativeModuleAvailable()) {
    return [];
  }

  const native = requireNativeModule();
  const voicesJson = await native.getTTSVoices();

  try {
    const voices = JSON.parse(voicesJson);
    if (Array.isArray(voices)) {
      return voices.map((v: TTSVoiceInfo | { id: string; name?: string; language?: string }) => ({
        id: v.id,
        name: v.name ?? v.id,
        language: v.language ?? 'en-US',
        isDownloaded: true,
      }));
    }
    return [];
  } catch {
    return [];
  }
}

// ============================================================================
// Synthesis
// ============================================================================

/**
 * Synthesize text to speech
 * Matches Swift SDK: RunAnywhere.synthesize(_:options:)
 */
export async function synthesize(
  text: string,
  options?: TTSOptions
): Promise<TTSOutput> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const startTime = Date.now();
  const native = requireNativeModule();

  const voiceId = options?.voice ?? '';
  const speedRate = options?.rate ?? 1.0;
  const pitchShift = options?.pitch ?? 1.0;

  const resultJson = await native.synthesize(text, voiceId, speedRate, pitchShift);
  const endTime = Date.now();
  const processingTime = (endTime - startTime) / 1000;

  try {
    const result = JSON.parse(resultJson);

    const sampleRate = result.sampleRate ?? 22050;
    const numSamples = result.numSamples ?? 0;
    const duration = numSamples > 0 ? numSamples / sampleRate : 0;

    const metadata: TTSSynthesisMetadata = {
      voice: voiceId || 'default',
      language: options?.language,
      processingTime,
      characterCount: text.length,
    };

    return {
      audioData: result.audio ?? '',
      format: 'pcm',
      duration,
      metadata,
    };
  } catch {
    if (resultJson.includes('error')) {
      throw new Error(resultJson);
    }
    return {
      audioData: resultJson,
      format: 'pcm',
      duration: 0,
      metadata: {
        voice: voiceId || 'default',
        processingTime,
        characterCount: text.length,
      },
    };
  }
}

/**
 * Synthesize with streaming (chunked audio output)
 * Matches Swift SDK: RunAnywhere.synthesizeStream(_:options:onAudioChunk:)
 */
export async function synthesizeStream(
  text: string,
  options: TTSOptions = {},
  onAudioChunk: TTSStreamChunkCallback
): Promise<TTSOutput> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const startTime = Date.now();

  // For now, synthesize and emit as single chunk
  // In a full implementation, this would stream chunks from native
  const output = await synthesize(text, options);

  // Decode base64 and emit as chunk
  if (output.audioData) {
    try {
      const binaryString = atob(output.audioData);
      const bytes = new Uint8Array(binaryString.length);
      for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
      }
      onAudioChunk(bytes.buffer);
    } catch (error) {
      logger.error(`Failed to decode audio chunk: ${error}`);
    }
  }

  return output;
}

/**
 * Stop current TTS synthesis
 * Matches Swift SDK: RunAnywhere.stopSynthesis()
 */
export async function stopSynthesis(): Promise<void> {
  // Native cancellation
  cancelTTS();

  // Also stop playback if speak() was used
  const playback = getAudioPlayback();
  playback.stop();
}

// ============================================================================
// Speak (Simple Playback API)
// ============================================================================

/**
 * Speak text aloud - the simplest way to use TTS
 *
 * The SDK handles audio synthesis and playback internally.
 * Just call this method and the text will be spoken through the device speakers.
 *
 * Matches Swift SDK: RunAnywhere.speak(_:options:)
 *
 * Example:
 * ```typescript
 * // Simple usage
 * await speak("Hello world");
 *
 * // With options
 * const result = await speak("Hello", { rate: 1.2 });
 * console.log(`Duration: ${result.duration}s`);
 * ```
 */
export async function speak(
  text: string,
  options?: TTSOptions
): Promise<TTSSpeakResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  logger.info(`Speaking: "${text.substring(0, 50)}..."`);

  // Synthesize the audio
  const output = await synthesize(text, options);

  // Play the audio
  if (output.audioData) {
    const playback = getAudioPlayback();
    await playback.play(output.audioData);
  }

  return {
    duration: output.duration,
    voice: output.metadata.voice,
    processingTime: output.metadata.processingTime,
    characterCount: output.metadata.characterCount,
  };
}

/**
 * Whether speech is currently playing
 * Matches Swift SDK: RunAnywhere.isSpeaking
 */
export function isSpeaking(): boolean {
  const playback = getAudioPlayback();
  return playback.isPlaying;
}

/**
 * Stop current speech playback
 * Matches Swift SDK: RunAnywhere.stopSpeaking()
 */
export async function stopSpeaking(): Promise<void> {
  const playback = getAudioPlayback();
  playback.stop();
  await stopSynthesis();
  logger.info('Speech stopped');
}

// ============================================================================
// Legacy APIs
// ============================================================================

/**
 * Get available TTS voices (legacy)
 * @deprecated Use availableTTSVoices() instead
 */
export async function getTTSVoices(): Promise<string[]> {
  return availableTTSVoices();
}

/**
 * Cancel ongoing TTS synthesis
 */
export function cancelTTS(): void {
  if (!isNativeModuleAvailable()) {
    return;
  }
  // Note: Native module would need a cancelTTS method
  // For now, just log
  logger.debug('TTS cancellation requested');
}

// ============================================================================
// Cleanup
// ============================================================================

/**
 * Cleanup TTS resources
 */
export function cleanupTTS(): void {
  if (ttsAudioPlayback) {
    ttsAudioPlayback.cleanup();
    ttsAudioPlayback = null;
  }
}
