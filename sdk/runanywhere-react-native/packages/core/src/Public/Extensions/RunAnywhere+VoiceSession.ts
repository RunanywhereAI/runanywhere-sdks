/**
 * RunAnywhere+VoiceSession.ts
 *
 * Voice session extension.
 * Delegates to native commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/RunAnywhere+VoiceSession.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '@runanywhere/native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('RunAnywhere.VoiceSession');

/**
 * Voice session config
 */
export interface VoiceSessionConfig {
  sttModelId?: string;
  ttsModelId?: string;
  llmModelId?: string;
  sampleRate?: number;
  language?: string;
}

/**
 * Voice turn result
 */
export interface VoiceTurnResult {
  transcription: string;
  response: string;
  audioData?: string; // base64
}

/**
 * Process a voice turn (STT -> LLM -> TTS)
 */
export async function processVoiceTurn(
  audioData: ArrayBuffer,
  config?: VoiceSessionConfig
): Promise<VoiceTurnResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();
  const sampleRate = config?.sampleRate ?? 16000;

  try {
    // Step 1: Transcribe audio
    const base64Audio = Buffer.from(audioData).toString('base64');
    const transcription = await native.transcribe(base64Audio, sampleRate, config?.language);

    // Step 2: Generate response
    const response = await native.generate(transcription);

    // Step 3: Synthesize response (if TTS model loaded)
    let audioResponse: string | undefined;
    try {
      const synthesized = await native.synthesize(response, '', 1.0, 1.0);
      audioResponse = synthesized;
    } catch {
      // TTS optional
    }

    return {
      transcription,
      response,
      audioData: audioResponse,
    };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(`Voice turn failed: ${msg}`);
    throw error;
  }
}

/**
 * Start a voice session (placeholder)
 */
export function startVoiceSession(_config?: VoiceSessionConfig): void {
  logger.info('Voice session started');
}

/**
 * Start voice session with callback (placeholder)
 */
export function startVoiceSessionWithCallback(
  _config: VoiceSessionConfig,
  _callback: (event: unknown) => void
): void {
  logger.info('Voice session with callback started');
}
