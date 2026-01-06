/**
 * RunAnywhere+VAD.ts
 *
 * Voice Activity Detection extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+VAD.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '@runanywhere/native';
import { EventBus } from '../Events';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  VADConfiguration,
  VADResult,
  SpeechActivityEvent,
  VADSpeechActivityCallback,
  VADAudioBufferCallback,
  VADState,
} from '../../types/VADTypes';

const logger = new SDKLogger('RunAnywhere.VAD');

// ============================================================================
// VAD State Management
// ============================================================================

// Internal VAD state
let vadState: VADState = {
  isInitialized: false,
  isRunning: false,
  isSpeechActive: false,
  currentProbability: 0,
};

// Callbacks
let speechActivityCallback: VADSpeechActivityCallback | null = null;
let audioBufferCallback: VADAudioBufferCallback | null = null;

// ============================================================================
// VAD Initialization
// ============================================================================

/**
 * Initialize VAD with default configuration
 * Matches Swift SDK: RunAnywhere.initializeVAD()
 */
export async function initializeVAD(config?: VADConfiguration): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  logger.info('Initializing VAD...');

  const native = requireNativeModule();

  // If a config is provided, configure VAD first
  if (config) {
    const configJson = JSON.stringify({
      sampleRate: config.sampleRate ?? 16000,
      frameLength: config.frameLength ?? 0.1,
      energyThreshold: config.energyThreshold ?? 0.005,
    });

    // Load VAD model if path provided, otherwise use default
    const loaded = await native.loadVADModel('default', configJson);
    if (!loaded) {
      throw new Error('Failed to initialize VAD');
    }
  }

  vadState.isInitialized = true;
  logger.info('VAD initialized');

  EventBus.publish('Voice', { type: 'vadInitialized' });
}

/**
 * Check if VAD is ready
 * Matches Swift SDK: RunAnywhere.isVADReady
 */
export async function isVADReady(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }

  const native = requireNativeModule();
  return native.isVADModelLoaded();
}

/**
 * Get current VAD state
 */
export function getVADState(): VADState {
  return { ...vadState };
}

// ============================================================================
// VAD Model Loading
// ============================================================================

/**
 * Load a VAD model
 */
export async function loadVADModel(
  modelPath: string,
  config?: VADConfiguration
): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }

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
 * Unload the current VAD model
 */
export async function unloadVADModel(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }

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

/**
 * Detect speech in audio samples
 * Matches Swift SDK: RunAnywhere.detectSpeech(in:)
 *
 * @param samples Float32Array of audio samples
 * @returns Whether speech was detected
 */
export async function detectSpeech(samples: Float32Array): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  // Convert Float32Array to base64
  const bytes = new Uint8Array(samples.buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    const byte = bytes[i];
    if (byte !== undefined) {
      binary += String.fromCharCode(byte);
    }
  }
  const audioBase64 = btoa(binary);

  const result = await processVAD(audioBase64);

  // Update state
  const wasSpeechActive = vadState.isSpeechActive;
  vadState.isSpeechActive = result.isSpeech;
  vadState.currentProbability = result.probability;

  // Emit speech activity events
  if (result.isSpeech && !wasSpeechActive) {
    if (speechActivityCallback) {
      speechActivityCallback('started');
    }
    EventBus.publish('Voice', { type: 'speechStarted' });
  } else if (!result.isSpeech && wasSpeechActive) {
    if (speechActivityCallback) {
      speechActivityCallback('ended');
    }
    EventBus.publish('Voice', { type: 'speechEnded' });
  }

  // Forward to audio buffer callback if set
  if (audioBufferCallback) {
    audioBufferCallback(samples);
  }

  return result.isSpeech;
}

/**
 * Process audio for voice activity detection
 * Returns detailed VAD result
 */
export async function processVAD(
  audioData: string | ArrayBuffer,
  sampleRate: number = 16000
): Promise<VADResult> {
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

  const optionsJson = JSON.stringify({ sampleRate });
  const resultJson = await native.processVAD(audioBase64, optionsJson);

  try {
    const result = JSON.parse(resultJson);
    return {
      isSpeech: result.isSpeech ?? false,
      probability: result.speechProbability ?? result.probability ?? 0,
      startTime: result.startTime,
      endTime: result.endTime,
    };
  } catch {
    return { isSpeech: false, probability: 0 };
  }
}

// ============================================================================
// VAD Control
// ============================================================================

/**
 * Start VAD processing
 * Matches Swift SDK: RunAnywhere.startVAD()
 */
export async function startVAD(): Promise<void> {
  if (!vadState.isInitialized) {
    await initializeVAD();
  }

  vadState.isRunning = true;
  logger.info('VAD started');

  EventBus.publish('Voice', { type: 'vadStarted' });
}

/**
 * Stop VAD processing
 * Matches Swift SDK: RunAnywhere.stopVAD()
 */
export async function stopVAD(): Promise<void> {
  vadState.isRunning = false;
  vadState.isSpeechActive = false;
  vadState.currentProbability = 0;

  logger.info('VAD stopped');
  EventBus.publish('Voice', { type: 'vadStopped' });
}

/**
 * Reset VAD state
 */
export async function resetVAD(): Promise<void> {
  if (!isNativeModuleAvailable()) {
    return;
  }

  const native = requireNativeModule();
  await native.resetVAD();

  vadState.isSpeechActive = false;
  vadState.currentProbability = 0;

  logger.debug('VAD state reset');
}

// ============================================================================
// Callbacks
// ============================================================================

/**
 * Set VAD speech activity callback
 * Matches Swift SDK: RunAnywhere.setVADSpeechActivityCallback(_:)
 *
 * @param callback Callback invoked when speech state changes
 */
export function setVADSpeechActivityCallback(
  callback: VADSpeechActivityCallback | null
): void {
  speechActivityCallback = callback;
  logger.debug('VAD speech activity callback set');
}

/**
 * Set VAD audio buffer callback
 * Matches Swift SDK: RunAnywhere.setVADAudioBufferCallback(_:)
 *
 * @param callback Callback invoked with audio samples
 */
export function setVADAudioBufferCallback(
  callback: VADAudioBufferCallback | null
): void {
  audioBufferCallback = callback;
  logger.debug('VAD audio buffer callback set');
}

// ============================================================================
// Cleanup
// ============================================================================

/**
 * Cleanup VAD resources
 * Matches Swift SDK: RunAnywhere.cleanupVAD()
 */
export async function cleanupVAD(): Promise<void> {
  await stopVAD();
  await unloadVADModel();

  speechActivityCallback = null;
  audioBufferCallback = null;

  vadState = {
    isInitialized: false,
    isRunning: false,
    isSpeechActive: false,
    currentProbability: 0,
  };

  logger.info('VAD cleaned up');
  EventBus.publish('Voice', { type: 'vadCleanedUp' });
}
