/**
 * RunAnywhere+VAD.ts
 *
 * Top-level VAD (Voice Activity Detection) namespace — mirrors Swift's
 * `RunAnywhere+VAD.swift`. Provides a `RunAnywhere.vad.*` capability surface
 * around the existing convenience verbs (detectSpeech / startVAD / stopVAD /
 * cleanupVAD / setVADCallback / isVADReady).
 *
 * Phase C-prime WEB: closes the gap where the Web SDK exposed VAD verbs only
 * as flat top-level functions. The new namespace is symmetric with the
 * `RunAnywhere.solutions`, `RunAnywhere.storage`, `RunAnywhere.plugins`
 * surfaces and matches the Swift / Kotlin / RN `RunAnywhere.vad` shape.
 */

import {
  detectSpeech,
  setVADCallback,
  startVAD,
  stopVAD,
  cleanupVAD,
  isVADReady,
} from './RunAnywhere+Convenience';
import type { SpeechActivityCallback } from '../../types/index';

/**
 * Free-function namespace mirroring Swift's `RunAnywhere.vad` extension.
 *
 * Each entry is a thin wrapper around the corresponding verb in
 * `RunAnywhere+Convenience.ts`. Apps can use either form:
 *   - `RunAnywhere.detectSpeech(audio)` — flat top-level (Swift parity)
 *   - `RunAnywhere.vad.detect(audio)`   — namespace form (Swift parity too)
 */
export const VAD = {
  /** Run VAD on a single buffer; returns true when speech is present. */
  detect(audio: Float32Array): boolean {
    return detectSpeech(audio);
  },

  /** Set the speech-activity callback (replaces previous, pass null to clear). */
  setCallback(callback: SpeechActivityCallback | null): void {
    setVADCallback(callback);
  },

  /** Mirror of Swift `RunAnywhere.startVAD()`. */
  async start(): Promise<void> {
    return startVAD();
  },

  /** Mirror of Swift `RunAnywhere.stopVAD()`. */
  async stop(): Promise<void> {
    return stopVAD();
  },

  /** Mirror of Swift `RunAnywhere.cleanupVAD()`. */
  async cleanup(): Promise<void> {
    return cleanupVAD();
  },

  /** Whether the VAD provider is registered and its model loaded. */
  isReady(): boolean {
    return isVADReady();
  },
};
