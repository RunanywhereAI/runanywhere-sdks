/**
 * RunAnywhere+VAD.ts
 *
 * Top-level VAD (Voice Activity Detection) namespace — mirrors Swift's
 * `RunAnywhere+VAD.swift`. Provides a `RunAnywhere.vad.*` capability surface
 * around the existing convenience verbs (detectSpeech / startVAD / stopVAD /
 * cleanupVAD / setVADCallback / isVADReady) plus the canonical §6 methods.
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
import type {
  SpeechActivityCallback,
  VADResult,
  VADOptions,
  VADConfiguration,
} from '../../types/index';
import { SDKException } from '../../Foundation/SDKException';
import { ExtensionPoint } from '../../Infrastructure/ExtensionPoint';

/** Extended VAD provider with model management and full canonical surface. */
interface VADModelProvider {
  detectVoiceActivity?(audio: Uint8Array, options?: VADOptions): Promise<VADResult>;
  streamVAD?(audio: AsyncIterable<Uint8Array>): AsyncIterable<VADResult>;
  initializeVAD?(config?: VADConfiguration): Promise<void>;
  resetVAD?(): Promise<void>;
  setVADAudioBufferCallback?(cb: (buffer: Uint8Array) => void): void;
  setVADStatisticsCallback?(cb: (stats: unknown) => void): void;
  loadVADModel?(modelId: string): Promise<void>;
  unloadVADModel?(): Promise<void>;
  isVADModelLoaded?: boolean;
}

function getVADProvider(): VADModelProvider | null {
  return ExtensionPoint.getProvider('vad') as VADModelProvider | null;
}

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

  /**
   * Full VAD inference with result (§6 `detectVoiceActivity`).
   * Returns a structured `VADResult` with probability, timing, and segments.
   */
  async detectVoiceActivity(audio: Uint8Array, options?: VADOptions): Promise<VADResult> {
    const provider = getVADProvider();
    if (typeof provider?.detectVoiceActivity === 'function') {
      return provider.detectVoiceActivity(audio, options);
    }
    throw SDKException.backendNotAvailable(
      'detectVoiceActivity',
      'The active VAD provider does not implement detectVoiceActivity.',
    );
  },

  /**
   * Streaming VAD over an audio stream (§6 `streamVAD`).
   * Returns an AsyncIterable of VADResult, one per chunk.
   */
  streamVAD(audio: AsyncIterable<Uint8Array>): AsyncIterable<VADResult> {
    const provider = getVADProvider();
    if (typeof provider?.streamVAD === 'function') {
      return provider.streamVAD(audio);
    }
    throw SDKException.backendNotAvailable(
      'streamVAD',
      'The active VAD provider does not implement streaming VAD.',
    );
  },

  /** Initialize VAD with optional config (§6). */
  async initializeVAD(config?: VADConfiguration): Promise<void> {
    const provider = getVADProvider();
    if (typeof provider?.initializeVAD === 'function') {
      return provider.initializeVAD(config);
    }
  },

  /** Set the speech-activity callback (§6 `setVADSpeechActivityCallback`). Replaces previous, pass null to clear. */
  setVADSpeechActivityCallback(callback: SpeechActivityCallback | null): void {
    setVADCallback(callback);
  },

  /** Set a callback for raw audio buffers (§6 `setVADAudioBufferCallback`). */
  setVADAudioBufferCallback(cb: (buffer: Uint8Array) => void): void {
    getVADProvider()?.setVADAudioBufferCallback?.(cb);
  },

  /** Set a callback for VAD statistics (§6 `setVADStatisticsCallback`). */
  setVADStatisticsCallback(cb: (stats: unknown) => void): void {
    getVADProvider()?.setVADStatisticsCallback?.(cb);
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

  /** Reset VAD internal state (§6). */
  async resetVAD(): Promise<void> {
    const provider = getVADProvider();
    if (typeof provider?.resetVAD === 'function') {
      return provider.resetVAD();
    }
  },

  /** Load a VAD model by ID (§6). */
  async loadVADModel(modelId: string): Promise<void> {
    const provider = getVADProvider();
    if (typeof provider?.loadVADModel === 'function') {
      return provider.loadVADModel(modelId);
    }
    throw SDKException.backendNotAvailable(
      'loadVADModel',
      'No VAD provider registered. Install and register @runanywhere/web-onnx.',
    );
  },

  /** Unload the active VAD model (§6). */
  async unloadVADModel(): Promise<void> {
    const provider = getVADProvider();
    if (typeof provider?.unloadVADModel === 'function') {
      return provider.unloadVADModel();
    }
  },

  /** Whether a VAD model is currently loaded (§6). */
  get isVADModelLoaded(): boolean {
    return getVADProvider()?.isVADModelLoaded ?? false;
  },

  /** Whether the VAD provider is registered and its model loaded. */
  isReady(): boolean {
    return isVADReady();
  },
};
