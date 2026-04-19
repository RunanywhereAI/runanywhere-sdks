/**
 * RunAnywhere+VoiceAgent.ts
 *
 * Voice Agent extension for the full voice pipeline.
 * Delegates to native VoiceAgentBridge.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/RunAnywhere+VoiceAgent.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  VoiceAgentConfig,
  VoiceAgentComponentStates,
  VoiceTurnResult,
} from '../../types/VoiceAgentTypes';

const logger = new SDKLogger('RunAnywhere.VoiceAgent');

/**
 * Get voice agent component states
 * @returns Component load states for STT, LLM, TTS
 */
export async function getVoiceAgentComponentStates(): Promise<VoiceAgentComponentStates> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();

  try {
    const resultJson = await native.getVoiceAgentComponentStates();
    return JSON.parse(resultJson) as VoiceAgentComponentStates;
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(`Failed to get component states: ${msg}`);
    throw error;
  }
}

/**
 * Check if all voice components are ready
 */
export async function areAllVoiceComponentsReady(): Promise<boolean> {
  const states = await getVoiceAgentComponentStates();
  return states.isFullyReady;
}

/**
 * Initialize voice agent with configuration
 * @param config Voice agent configuration
 * @returns true if initialized successfully
 */
export async function initializeVoiceAgent(
  config: VoiceAgentConfig
): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();

  try {
    logger.info('Initializing voice agent...');
    const result = await native.initializeVoiceAgent(JSON.stringify(config));
    if (result) {
      logger.info('Voice agent initialized successfully');
    }
    return result;
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(`Failed to initialize voice agent: ${msg}`);
    throw error;
  }
}

/**
 * Initialize voice agent using already-loaded models
 * Uses the current STT, LLM, and TTS models
 * @returns true if initialized successfully
 */
export async function initializeVoiceAgentWithLoadedModels(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();

  try {
    logger.info('Initializing voice agent with loaded models...');
    const result = await native.initializeVoiceAgentWithLoadedModels();
    if (result) {
      logger.info('Voice agent initialized with loaded models');
    }
    return result;
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(`Failed to initialize voice agent: ${msg}`);
    throw error;
  }
}

/**
 * Check if voice agent is ready
 */
export async function isVoiceAgentReady(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }

  const native = requireNativeModule();
  return native.isVoiceAgentReady();
}

/**
 * Process a complete voice turn: audio -> transcription -> response -> speech
 * @param audioData Audio data as ArrayBuffer or base64 string
 * @returns Voice turn result
 */
export async function processVoiceTurn(
  audioData: ArrayBuffer | string
): Promise<VoiceTurnResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();

  try {
    // Convert to base64 if ArrayBuffer
    let base64Audio: string;
    if (audioData instanceof ArrayBuffer) {
      const bytes = new Uint8Array(audioData);
      base64Audio = btoa(String.fromCharCode(...bytes));
    } else {
      base64Audio = audioData;
    }

    const resultJson = await native.processVoiceTurn(base64Audio);
    const result = JSON.parse(resultJson);

    return {
      speechDetected: result.speechDetected === true || result.speechDetected === 'true',
      transcription: result.transcription || '',
      response: result.response || '',
      synthesizedAudio: result.synthesizedAudio || undefined,
      sampleRate: result.sampleRate || 16000,
    };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(`Voice turn failed: ${msg}`);
    throw error;
  }
}

/**
 * Transcribe audio using voice agent (voice agent must be initialized)
 * @param audioData Audio data as ArrayBuffer or base64 string
 * @returns Transcription text
 */
export async function voiceAgentTranscribe(
  audioData: ArrayBuffer | string
): Promise<string> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();

  let base64Audio: string;
  if (audioData instanceof ArrayBuffer) {
    const bytes = new Uint8Array(audioData);
    base64Audio = btoa(String.fromCharCode(...bytes));
  } else {
    base64Audio = audioData;
  }

  return native.voiceAgentTranscribe(base64Audio);
}

/**
 * Generate response using voice agent LLM
 * @param prompt Input text
 * @returns Generated response text
 */
export async function voiceAgentGenerateResponse(
  prompt: string
): Promise<string> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();
  return native.voiceAgentGenerateResponse(prompt);
}

/**
 * Synthesize speech using voice agent TTS
 * @param text Text to synthesize
 * @returns Base64-encoded audio data
 */
export async function voiceAgentSynthesizeSpeech(
  text: string
): Promise<string> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();
  return native.voiceAgentSynthesizeSpeech(text);
}

/**
 * Cleanup voice agent resources
 */
export async function cleanupVoiceAgent(): Promise<void> {
  if (!isNativeModuleAvailable()) {
    return;
  }

  const native = requireNativeModule();
  logger.info('Cleaning up voice agent...');
  await native.cleanupVoiceAgent();
  logger.info('Voice agent cleaned up');
}
