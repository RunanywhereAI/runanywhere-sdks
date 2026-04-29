/**
 * RunAnywhere+VAD.ts
 *
 * Voice Activity Detection extension. Wave 2: aligned to proto-canonical
 * VAD shapes (`@runanywhere/proto-ts/vad_options`). Legacy ad-hoc local
 * shapes have been deleted.
 *
 * Matches Swift: `Public/Extensions/VAD/RunAnywhere+VAD.swift`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { EventBus } from '../Events';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import {
  type VADConfiguration,
  type VADOptions,
  type VADResult,
  type VADStatistics,
  SpeechActivityKind,
} from '@runanywhere/proto-ts/vad_options';

const logger = new SDKLogger('RunAnywhere.VAD');

/** RN-local runtime VAD state. (No proto counterpart — purely local UI/debug.) */
export interface VADState {
  isInitialized: boolean;
  isRunning: boolean;
  isSpeechActive: boolean;
  currentProbability: number;
}

export type VADSpeechActivityCallback = (kind: SpeechActivityKind) => void;
export type VADAudioBufferCallback = (samples: Float32Array) => void;
export type VADStatisticsCallback = (statistics: VADStatistics) => void;

/** Native module interface extension for VAD statistics. */
interface VADStatisticsNativeModule {
  /** rac_vad_component_get_statistics — wired by round1 C++ fix. */
  vadGetStatistics?: () => Promise<string>;
}

let vadState: VADState = {
  isInitialized: false,
  isRunning: false,
  isSpeechActive: false,
  currentProbability: 0,
};

let speechActivityCallback: VADSpeechActivityCallback | null = null;
let audioBufferCallback: VADAudioBufferCallback | null = null;
let statisticsCallback: VADStatisticsCallback | null = null;

// ============================================================================
// VAD Initialization
// ============================================================================

/**
 * Initialize VAD with optional configuration.
 *
 * Matches Swift SDK: `RunAnywhere.initializeVAD()`.
 */
export async function initializeVAD(config?: VADConfiguration): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  logger.info('Initializing VAD...');
  const native = requireNativeModule();

  if (config) {
    const configJson = JSON.stringify({
      modelId: config.modelId,
      sampleRate: config.sampleRate ?? 16000,
      frameLengthMs: config.frameLengthMs ?? 100,
      threshold: config.threshold ?? 0.015,
      enableAutoCalibration: config.enableAutoCalibration ?? false,
    });
    const loaded = await native.loadVADModel(
      config.modelId || 'default',
      configJson
    );
    if (!loaded) {
      throw new Error('Failed to initialize VAD');
    }
  }

  vadState.isInitialized = true;
  logger.info('VAD initialized');
  EventBus.publish('Voice', { type: 'vadInitialized' });
}

/** Whether VAD is ready. */
export async function isVADReady(): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = requireNativeModule();
  return native.isVADModelLoaded();
}

/** Get current VAD state. */
export function getVADState(): VADState {
  return { ...vadState };
}

// ============================================================================
// VAD Model Loading
// ============================================================================

/** Load a VAD model. */
export async function loadVADModel(
  modelPath: string,
  config?: VADConfiguration
): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  logger.info(`Loading VAD model: ${modelPath}`);
  const native = requireNativeModule();
  const configJson = config ? JSON.stringify(config) : undefined;
  const result = await native.loadVADModel(modelPath, configJson);
  if (result) {
    vadState.isInitialized = true;
    logger.info('VAD model loaded');
  }
  return result;
}

/** Check if a VAD model is loaded. */
export async function isVADModelLoaded(): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = requireNativeModule();
  return native.isVADModelLoaded();
}

/** Unload the current VAD model. */
export async function unloadVADModel(): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = requireNativeModule();
  const result = await native.unloadVADModel();
  if (result) {
    vadState.isInitialized = false;
    vadState.isRunning = false;
    vadState.isSpeechActive = false;
    logger.info('VAD model unloaded');
  }
  return result;
}

// ============================================================================
// Speech Detection
// ============================================================================

/** Encode a `Float32Array` audio buffer to a base64 string. */
function float32ToBase64(samples: Float32Array): string {
  const bytes = new Uint8Array(samples.buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    const byte = bytes[i];
    if (byte !== undefined) binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

/**
 * Detect voice activity in audio samples.
 *
 * Canonical cross-SDK signature: detectVoiceActivity(audio: Uint8Array, options: VADOptions)
 * Also accepts Float32Array | string | ArrayBuffer for legacy callers.
 *
 * Matches Swift SDK: `RunAnywhere.detectVoiceActivity(_:options:)`.
 */
export async function detectVoiceActivity(
  audio: Uint8Array | Float32Array | string | ArrayBuffer,
  options?: Partial<VADOptions>
): Promise<VADResult> {
  if (!isNativeModuleAvailable()) {
    return { isSpeech: false, confidence: 0, energy: 0, durationMs: 0 };
  }
  let audioForProcessing: string | ArrayBuffer;
  if (audio instanceof Float32Array) {
    audioForProcessing = audio.buffer as ArrayBuffer;
  } else if (audio instanceof Uint8Array) {
    audioForProcessing = audio.buffer as ArrayBuffer;
  } else {
    audioForProcessing = audio;
  }
  const result = await processVAD(audioForProcessing, 16000, options);

  const wasSpeechActive = vadState.isSpeechActive;
  vadState.isSpeechActive = result.isSpeech;
  vadState.currentProbability = result.confidence;

  if (result.isSpeech && !wasSpeechActive) {
    if (speechActivityCallback) {
      speechActivityCallback(SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_STARTED);
    }
    EventBus.publish('Voice', { type: 'speechStarted' });
  } else if (!result.isSpeech && wasSpeechActive) {
    if (speechActivityCallback) {
      speechActivityCallback(SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_ENDED);
    }
    EventBus.publish('Voice', { type: 'speechEnded' });
  }

  if (audioBufferCallback && audio instanceof Float32Array) {
    audioBufferCallback(audio);
  }

  // Fire statistics callback if set and the bridge exposes vadGetStatistics.
  if (statisticsCallback && isNativeModuleAvailable()) {
    const native = requireNativeModule() as unknown as VADStatisticsNativeModule;
    if (typeof native.vadGetStatistics === 'function') {
      native.vadGetStatistics().then((statsJson) => {
        try {
          const stats = JSON.parse(statsJson) as {
            currentEnergy?: number;
            current_energy?: number;
            currentThreshold?: number;
            current_threshold?: number;
            ambientLevel?: number;
            ambient_level?: number;
            recentAvg?: number;
            recent_avg?: number;
            recentMax?: number;
            recent_max?: number;
          };
          const vadStats: VADStatistics = {
            currentEnergy: stats.currentEnergy ?? stats.current_energy ?? 0,
            currentThreshold: stats.currentThreshold ?? stats.current_threshold ?? 0,
            ambientLevel: stats.ambientLevel ?? stats.ambient_level ?? 0,
            recentAvg: stats.recentAvg ?? stats.recent_avg ?? 0,
            recentMax: stats.recentMax ?? stats.recent_max ?? 0,
          };
          statisticsCallback?.(vadStats);
        } catch { /* ignore parse errors */ }
      }).catch(() => { /* ignore errors */ });
    }
  }

  return result;
}

/**
 * Detect speech in audio samples (boolean convenience).
 *
 * Matches Swift SDK: `RunAnywhere.detectSpeech(in:)`.
 */
export async function detectSpeech(samples: Float32Array): Promise<boolean> {
  const result = await detectVoiceActivity(samples);
  return result.isSpeech;
}

/**
 * Process audio for voice activity detection — returns the full proto result.
 */
export async function processVAD(
  audio: string | ArrayBuffer,
  sampleRate: number = 16000,
  options?: Partial<VADOptions>
): Promise<VADResult> {
  if (!isNativeModuleAvailable()) {
    return { isSpeech: false, confidence: 0, energy: 0, durationMs: 0 };
  }
  const native = requireNativeModule();
  const audioBase64 =
    typeof audio === 'string' ? audio : float32ToBase64(new Float32Array(audio));
  const optionsJson = JSON.stringify({
    sampleRate,
    threshold: options?.threshold,
    minSpeechDurationMs: options?.minSpeechDurationMs,
    minSilenceDurationMs: options?.minSilenceDurationMs,
  });
  const resultJson = await native.processVAD(audioBase64, optionsJson);
  try {
    const result = JSON.parse(resultJson);
    return {
      isSpeech: result.isSpeech ?? false,
      confidence:
        result.speechProbability ??
        result.probability ??
        result.confidence ??
        0,
      energy: result.energy ?? result.energyLevel ?? 0,
      durationMs: result.durationMs ?? 0,
    };
  } catch {
    return { isSpeech: false, confidence: 0, energy: 0, durationMs: 0 };
  }
}

// ============================================================================
// VAD Control
// ============================================================================

/** Start VAD processing. */
export async function startVAD(): Promise<void> {
  if (!vadState.isInitialized) {
    await initializeVAD();
  }
  vadState.isRunning = true;
  logger.info('VAD started');
  EventBus.publish('Voice', { type: 'vadStarted' });
}

/** Stop VAD processing. */
export async function stopVAD(): Promise<void> {
  vadState.isRunning = false;
  vadState.isSpeechActive = false;
  vadState.currentProbability = 0;
  logger.info('VAD stopped');
  EventBus.publish('Voice', { type: 'vadStopped' });
}

/** Reset VAD state. */
export async function resetVAD(): Promise<void> {
  if (!isNativeModuleAvailable()) return;
  const native = requireNativeModule();
  await native.resetVAD();
  vadState.isSpeechActive = false;
  vadState.currentProbability = 0;
  logger.debug('VAD state reset');
}

// ============================================================================
// Callbacks
// ============================================================================

/** Set VAD speech activity callback. */
export function setVADSpeechActivityCallback(
  callback: VADSpeechActivityCallback | null
): void {
  speechActivityCallback = callback;
  logger.debug('VAD speech activity callback set');
}

/** Set VAD audio buffer callback. */
export function setVADAudioBufferCallback(
  callback: VADAudioBufferCallback | null
): void {
  audioBufferCallback = callback;
  logger.debug('VAD audio buffer callback set');
}

/**
 * Set a callback that receives VAD statistics on each detection call.
 *
 * When the Nitro bridge exposes `vadGetStatistics` (wired to
 * `rac_vad_component_get_statistics`), the callback is invoked after each
 * `detectVoiceActivity` call with the freshly-fetched statistics. Otherwise
 * the callback is stored but never invoked until the bridge ships the method.
 *
 * Matches Swift SDK: `RunAnywhere.setVADStatisticsCallback(_:)` (§6).
 */
export function setVADStatisticsCallback(
  callback: VADStatisticsCallback | null
): void {
  statisticsCallback = callback;
  logger.debug('VAD statistics callback set');
}

/**
 * Stream VAD results for an async sequence of audio chunks.
 *
 * For each chunk yielded by `audio`, calls `detectVoiceActivity` and yields
 * the resulting `VADResult`. The stream terminates when `audio` is exhausted.
 *
 * Matches canonical cross-SDK spec §6:
 *   `streamVAD(audio: Stream<Bytes>) → Stream<VADResult>`
 */
export async function* streamVAD(
  audio: AsyncIterable<Uint8Array>
): AsyncIterable<VADResult> {
  for await (const chunk of audio) {
    const result = await detectVoiceActivity(chunk);
    yield result;
  }
}

// ============================================================================
// Cleanup
// ============================================================================

/** Cleanup VAD resources. */
export async function cleanupVAD(): Promise<void> {
  await stopVAD();
  await unloadVADModel();
  speechActivityCallback = null;
  audioBufferCallback = null;
  statisticsCallback = null;
  vadState = {
    isInitialized: false,
    isRunning: false,
    isSpeechActive: false,
    currentProbability: 0,
  };
  logger.info('VAD cleaned up');
  EventBus.publish('Voice', { type: 'vadCleanedUp' });
}
