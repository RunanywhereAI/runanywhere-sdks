/**
 * RunAnywhere+VoiceSession.ts
 *
 * Voice Session and Voice Agent extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+VoiceSession.swift and RunAnywhere+VoiceAgent.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import {
  arrayBufferToBase64,
  base64ToUint8Array,
  normalizeAudioData,
} from '../../Foundation/Utilities/AudioUtils';

const logger = new SDKLogger('RunAnywhere.VoiceSession');

// ============================================================================
// Voice Agent Processing
// ============================================================================

/** Default sample rate for voice processing (16kHz) */
const DEFAULT_SAMPLE_RATE = 16000;

/**
 * Process a complete voice turn: audio → transcription → LLM response → synthesized speech
 *
 * Matches iOS: static func processVoiceTurn(_ audioData: Data) async throws -> VoiceAgentResult
 *
 * @param audioData - Raw PCM audio data (16-bit, mono, 16kHz)
 * @param sampleRate - Audio sample rate (default: 16000)
 */
export async function processVoiceTurn(
  audioData: ArrayBuffer | Uint8Array | Buffer,
  sampleRate: number = DEFAULT_SAMPLE_RATE
): Promise<import('../../Features/VoiceAgent/VoiceAgentModels').VoiceAgentResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();
  const audioBytes = normalizeAudioData(audioData);

  // Convert PCM audio to base64 for native module
  const audioBase64 = arrayBufferToBase64(audioBytes);

  // Step 1: Transcribe audio using native STT (no WAV conversion needed)
  const transcribeResultJson = await native.transcribe(
    audioBase64,
    sampleRate,
    'en'
  );
  const transcribeResult = JSON.parse(transcribeResultJson);

  if (transcribeResult.error) {
    throw new Error(transcribeResult.error);
  }

  const transcription = transcribeResult.text?.trim() || '';

  if (!transcription) {
    return {
      speechDetected: false,
      transcription: null,
      response: null,
      synthesizedAudio: null,
    };
  }

  // Step 2: Generate LLM response
  const optionsJson = JSON.stringify({
    maxTokens: 500,
    temperature: 0.7,
  });
  const generateResultJson = await native.generate(transcription, optionsJson);
  const generateResult = JSON.parse(generateResultJson);

  if (generateResult.error) {
    throw new Error(generateResult.error);
  }

  const response = generateResult.text || '';

  // Step 3: Synthesize speech from response
  let synthesizedAudio: Uint8Array | null = null;
  if (response) {
    try {
      const ttsResultJson = await native.synthesize(response, '', 1.0, 0.0);
      const ttsResult = JSON.parse(ttsResultJson);

      if (ttsResult.audioData) {
        synthesizedAudio = base64ToUint8Array(ttsResult.audioData);
      }
    } catch (ttsError) {
      logger.warning(`TTS synthesis failed: ${ttsError}`);
    }
  }

  return {
    speechDetected: true,
    transcription,
    response,
    synthesizedAudio,
  };
}

// ============================================================================
// Voice Session API
// ============================================================================

/**
 * Start a voice session with event-based handling
 *
 * Matches iOS: static func startVoiceSession(config:) async throws -> VoiceSessionHandle
 */
export async function startVoiceSession(
  config?: Partial<import('../../Features/VoiceSession').VoiceSessionConfig>
): Promise<import('../../Features/VoiceSession').VoiceSessionHandle> {
  const { VoiceSessionHandle } = await import('../../Features/VoiceSession');
  const session = new VoiceSessionHandle(config);
  await session.start();
  return session;
}

/**
 * Start a voice session with callback-based event handling
 *
 * Matches iOS: static func startVoiceSession(config:onEvent:) async throws -> VoiceSessionHandle
 */
export async function startVoiceSessionWithCallback(
  config: Partial<import('../../Features/VoiceSession').VoiceSessionConfig>,
  onEvent: import('../../Features/VoiceSession').VoiceSessionEventListener
): Promise<import('../../Features/VoiceSession').VoiceSessionHandle> {
  const { VoiceSessionHandle } = await import('../../Features/VoiceSession');
  const session = new VoiceSessionHandle(config);
  session.onEvent(onEvent);
  await session.start();
  return session;
}
