/**
 * RunAnywhere+TTS.ts
 *
 * Text-to-speech namespace — mirrors Swift's `RunAnywhere+TTS.swift`.
 * Provides `RunAnywhere.tts.*` capability surface around synthesize/speak.
 */

import type { TTSOptions, TTSOutput } from '@runanywhere/proto-ts/tts_options';
import type { TTSSynthesisResult, TTSSynthesizeOptions } from '../../types/index';
import { synthesize, speak, isSpeaking, stopSpeaking } from './RunAnywhere+Convenience';

export type { TTSOptions, TTSOutput };

export const TTS = {
  async synthesize(text: string, options?: TTSSynthesizeOptions): Promise<TTSSynthesisResult> {
    return synthesize(text, options);
  },

  async speak(text: string, options?: TTSSynthesizeOptions): Promise<void> {
    return speak(text, options);
  },

  isSpeaking(): boolean {
    return isSpeaking();
  },

  stop(): void {
    stopSpeaking();
  },
};
