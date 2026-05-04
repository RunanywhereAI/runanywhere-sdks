/**
 * RunAnywhere+TTS.ts
 *
 * Text-to-speech namespace — mirrors Swift's `RunAnywhere+TTS.swift`.
 * Provides `RunAnywhere.tts.*` capability surface around synthesize/speak.
 */

import type { TTSOptions, TTSOutput, TTSVoiceInfo } from '@runanywhere/proto-ts/tts_options';
import type { TTSSynthesisResult, TTSSynthesizeOptions } from '../../types/index';
import { synthesize, speak, isSpeaking, stopSpeaking } from './RunAnywhere+Convenience';
import { SDKException } from '../../Foundation/SDKException';
import { ExtensionPoint } from '../../Infrastructure/ExtensionPoint';

export type { TTSOptions, TTSOutput, TTSVoiceInfo };

/** TTS provider interface extensions for model/voice management. */
interface TTSModelProvider {
  loadTTSVoice?(voiceId: string): Promise<void>;
  unloadTTSVoice?(): Promise<void>;
  isTTSVoiceLoaded?: boolean;
  availableTTSVoices?(): Promise<TTSVoiceInfo[]>;
  loadTTSModel?(modelId: string): Promise<void>;
  unloadTTSModel?(): Promise<void>;
  synthesizeStream?(text: string, options?: TTSSynthesizeOptions): AsyncIterable<Uint8Array>;
}

function getTTSProvider(): TTSModelProvider | null {
  return ExtensionPoint.getProvider('tts') as TTSModelProvider | null;
}

export const TTS = {
  async synthesize(text: string, options?: TTSSynthesizeOptions): Promise<TTSSynthesisResult> {
    return synthesize(text, options);
  },

  /**
   * Streaming TTS synthesis (§5). Returns an AsyncIterable of PCM audio chunks.
   * Delegates to the TTS provider if available.
   */
  synthesizeStream(text: string, options?: TTSSynthesizeOptions): AsyncIterable<Uint8Array> {
    const provider = getTTSProvider();
    if (typeof provider?.synthesizeStream === 'function') {
      return provider.synthesizeStream(text, options);
    }
    throw SDKException.backendNotAvailable(
      'synthesizeStream',
      'The active TTS provider does not implement streaming synthesis.',
    );
  },

  async speak(text: string, options?: TTSSynthesizeOptions): Promise<void> {
    return speak(text, options);
  },

  isSpeaking(): boolean {
    return isSpeaking();
  },

  /** Stop current TTS playback (§5). */
  stop(): void {
    stopSpeaking();
  },

  /** Stop current TTS synthesis — alias for `stop()` per §5 `stopSynthesis`. */
  stopSynthesis(): void {
    stopSpeaking();
  },

  /** Load a TTS voice by ID (§5). */
  async loadTTSVoice(voiceId: string): Promise<void> {
    const provider = getTTSProvider();
    if (typeof provider?.loadTTSVoice === 'function') {
      return provider.loadTTSVoice(voiceId);
    }
    throw SDKException.backendNotAvailable(
      'loadTTSVoice',
      'No TTS provider registered. Install and register @runanywhere/web-onnx.',
    );
  },

  /** Unload the active TTS voice (§5). */
  async unloadTTSVoice(): Promise<void> {
    const provider = getTTSProvider();
    if (typeof provider?.unloadTTSVoice === 'function') {
      return provider.unloadTTSVoice();
    }
  },

  /** Whether a TTS voice is currently loaded (§5). */
  get isTTSVoiceLoaded(): boolean {
    return getTTSProvider()?.isTTSVoiceLoaded ?? false;
  },

  /** List available TTS voices (§5). */
  async availableTTSVoices(): Promise<TTSVoiceInfo[]> {
    const provider = getTTSProvider();
    if (typeof provider?.availableTTSVoices === 'function') {
      return provider.availableTTSVoices();
    }
    return [];
  },

  /** Load a TTS model by ID (§5). */
  async loadTTSModel(modelId: string): Promise<void> {
    const provider = getTTSProvider();
    if (typeof provider?.loadTTSModel === 'function') {
      return provider.loadTTSModel(modelId);
    }
    throw SDKException.backendNotAvailable(
      'loadTTSModel',
      'No TTS provider registered. Install and register @runanywhere/web-onnx.',
    );
  },

  /** Unload the active TTS model (§5). */
  async unloadTTSModel(): Promise<void> {
    const provider = getTTSProvider();
    if (typeof provider?.unloadTTSModel === 'function') {
      return provider.unloadTTSModel();
    }
  },
};
