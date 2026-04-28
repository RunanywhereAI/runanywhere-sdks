/**
 * RunAnywhere+VoiceAgent.ts
 *
 * Voice Agent extension for the full voice pipeline. Wave 2: aligned to
 * proto-canonical voice agent shapes
 * (`@runanywhere/proto-ts/voice_agent_service` and
 * `@runanywhere/proto-ts/voice_events`).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/RunAnywhere+VoiceAgent.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  VoiceSessionConfig as VoiceAgentConfig,
  VoiceAgentResult,
} from '@runanywhere/proto-ts/voice_agent_service';
import type { VoiceAgentComponentStates } from '@runanywhere/proto-ts/voice_events';

const logger = new SDKLogger('RunAnywhere.VoiceAgent');

/** Decode a base64 string to a `Uint8Array`. */
function base64ToBytes(b64: string): Uint8Array {
  if (!b64) return new Uint8Array(0);
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/**
 * Get voice agent component states.
 *
 * Matches Swift: `RunAnywhere.getVoiceAgentComponentStates()`.
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

/** Whether all voice components are ready. */
export async function areAllVoiceComponentsReady(): Promise<boolean> {
  const states = await getVoiceAgentComponentStates();
  return states.ready;
}

/** Initialize voice agent with configuration. */
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
 * Initialize voice agent using already-loaded models.
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

/** Whether the voice agent is ready. */
export async function isVoiceAgentReady(): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = requireNativeModule();
  return native.isVoiceAgentReady();
}

/**
 * Process a complete voice turn: audio -> transcription -> response -> speech.
 *
 * Matches Swift: `RunAnywhere.processVoiceTurn(_:)`.
 */
export async function processVoiceTurn(
  audioData: ArrayBuffer | string
): Promise<VoiceAgentResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();
  try {
    let base64Audio: string;
    if (audioData instanceof ArrayBuffer) {
      const bytes = new Uint8Array(audioData);
      base64Audio = btoa(String.fromCharCode(...bytes));
    } else {
      base64Audio = audioData;
    }
    const resultJson = await native.processVoiceTurn(base64Audio);
    const parsed = JSON.parse(resultJson) as {
      speechDetected?: boolean;
      transcription?: string;
      assistantResponse?: string;
      response?: string;
      thinkingContent?: string;
      synthesizedAudio?: string;
      sampleRate?: number;
    };
    return {
      speechDetected: !!parsed.speechDetected,
      transcription: parsed.transcription,
      assistantResponse: parsed.assistantResponse ?? parsed.response,
      thinkingContent: parsed.thinkingContent,
      synthesizedAudio: parsed.synthesizedAudio
        ? base64ToBytes(parsed.synthesizedAudio)
        : undefined,
    };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(`Voice turn failed: ${msg}`);
    throw error;
  }
}

/** Transcribe audio using voice agent. */
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

/** Generate a response using the voice-agent LLM. */
export async function voiceAgentGenerateResponse(
  prompt: string
): Promise<string> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();
  return native.voiceAgentGenerateResponse(prompt);
}

/** Synthesize speech using the voice-agent TTS. */
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
 * Get the native voice-agent handle.
 *
 * Matches Swift: `RunAnywhere.voiceAgentHandle()`.
 */
export async function getVoiceAgentHandle(): Promise<number> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();
  return native.getVoiceAgentHandle();
}

/** Cleanup voice-agent resources. */
export async function cleanupVoiceAgent(): Promise<void> {
  if (!isNativeModuleAvailable()) return;
  const native = requireNativeModule();
  logger.info('Cleaning up voice agent...');
  await native.cleanupVoiceAgent();
  logger.info('Voice agent cleaned up');
}
