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
import { SDKException } from '../../Foundation/ErrorTypes/SDKException';
import type {
  VoiceAgentResult,
  VoiceSessionConfig,
} from '@runanywhere/proto-ts/voice_agent_service';
import {
  VoiceAgentComposeConfig,
  VoiceAgentResult as VoiceAgentResultMessage,
  VoiceAgentTranscribeProtoRequest,
} from '@runanywhere/proto-ts/voice_agent_service';
import type { VoiceAgentComponentStates } from '@runanywhere/proto-ts/voice_events';
import {
  VoiceAgentComponentStates as VoiceAgentComponentStatesMessage,
} from '@runanywhere/proto-ts/voice_events';
import type { VoiceEvent } from '@runanywhere/proto-ts/voice_events';
import {
  STTOutput as STTOutputMessage,
  type STTOutput as STTOutputType,
} from '@runanywhere/proto-ts/stt_options';
import { TTSOutput } from '@runanywhere/proto-ts/tts_options';
import { VoiceAgentStreamAdapter } from '../../Adapters/VoiceAgentStreamAdapter';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';

const logger = new SDKLogger('RunAnywhere.VoiceAgent');

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
}

function audioToArrayBuffer(audioData: ArrayBuffer | Uint8Array): ArrayBuffer {
  if (audioData instanceof Uint8Array) {
    return bytesToArrayBuffer(audioData);
  }
  return audioData;
}

function buildVoiceAgentComposeConfig(
  config: VoiceSessionConfig
): ReturnType<typeof VoiceAgentComposeConfig.create> {
  return VoiceAgentComposeConfig.create({
    vadSampleRate: 16000,
    vadFrameLength: 0.1,
    vadEnergyThreshold: config.speechThreshold ?? 0.1,
    wakewordEnabled: false,
    wakewordThreshold: 0,
    sessionConfig: config,
  });
}

/**
 * Get voice agent component states.
 *
 * Matches Swift: `RunAnywhere.getVoiceAgentComponentStates()`.
 */
export async function getVoiceAgentComponentStates(): Promise<VoiceAgentComponentStates> {
  const native = ensureNative();
  try {
    const bytes = await native.voiceAgentComponentStatesProto();
    return VoiceAgentComponentStatesMessage.decode(arrayBufferToBytes(bytes));
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
  config: VoiceSessionConfig
): Promise<boolean> {
  const native = ensureNative();
  try {
    logger.info('Initializing voice agent...');
    const bytes = await native.voiceAgentInitializeProto(
      bytesToArrayBuffer(
        VoiceAgentComposeConfig.encode(buildVoiceAgentComposeConfig(config)).finish()
      )
    );
    const result = arrayBufferToBytes(bytes).byteLength > 0;
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
  const native = ensureNative();
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
  audioData: ArrayBuffer | Uint8Array
): Promise<VoiceAgentResult> {
  const native = ensureNative();
  try {
    const resultBytes = await native.voiceAgentProcessTurnProto(
      audioToArrayBuffer(audioData)
    );
    const bytes = arrayBufferToBytes(resultBytes);
    if (bytes.byteLength === 0) {
      throw SDKException.protoDecodeFailed('voiceAgentProcessTurnProto');
    }
    return VoiceAgentResultMessage.decode(bytes);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(`Voice turn failed: ${msg}`);
    throw error;
  }
}

/**
 * Transcribe audio using the voice agent's STT component via the native
 * `rac_voice_agent_transcribe_proto` ABI (Wave D-7).
 *
 * Matches Swift SDK: `RunAnywhere.voiceAgentTranscribe(_:) → STTOutput` (§10).
 */
export async function voiceAgentTranscribe(
  audioData: ArrayBuffer | Uint8Array
): Promise<STTOutputType> {
  const native = ensureNative();
  const audioBytes =
    audioData instanceof Uint8Array ? audioData : new Uint8Array(audioData);
  const request = VoiceAgentTranscribeProtoRequest.create({
    audioData: audioBytes,
    sessionId: '',
    sampleRate: 16000,
    languageHint: '',
    channels: 1,
    encoding: 0,
  });
  const requestBytes = VoiceAgentTranscribeProtoRequest.encode(request).finish();
  const resultBytes = await native.voiceAgentTranscribeProto(
    bytesToArrayBuffer(requestBytes)
  );
  const bytes = arrayBufferToBytes(resultBytes);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed('voiceAgentTranscribeProto');
  }
  return STTOutputMessage.decode(bytes);
}

/**
 * Synthesize speech using the voice-agent TTS component via the native
 * `rac_voice_agent_synthesize_speech_proto` ABI (Wave D-7).
 *
 * Matches Swift SDK: `RunAnywhere.voiceAgentSynthesizeSpeech(_:) → TTSOutput` (§10).
 */
export async function voiceAgentSynthesizeSpeech(
  text: string
): Promise<TTSOutput> {
  const native = ensureNative();
  const resultBytes = await native.voiceAgentSynthesizeSpeechProto(text);
  const bytes = arrayBufferToBytes(resultBytes);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed('voiceAgentSynthesizeSpeechProto');
  }
  return TTSOutput.decode(bytes);
}

/**
 * Get the native voice-agent handle.
 *
 * Matches Swift: `RunAnywhere.voiceAgentHandle()`.
 */
export async function getVoiceAgentHandle(): Promise<number> {
  const native = ensureNative();
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

/**
 * Stream voice agent events as an AsyncIterable<VoiceEvent>.
 *
 * This is the canonical cross-SDK public method for voice agent streaming.
 * Internally obtains the native voice-agent handle and wraps it with
 * `VoiceAgentStreamAdapter` so callers never need to reach into internals.
 *
 * Matches Swift: `RunAnywhere.streamVoiceAgent() -> AsyncStream<RAVoiceEvent>`.
 *
 * Usage:
 *   const stream = await RunAnywhere.streamVoiceAgent()
 *   for await (const evt of stream) { handleEvent(evt) }
 */
export async function streamVoiceAgent(): Promise<AsyncIterable<VoiceEvent>> {
  const handle = await getVoiceAgentHandle();
  const adapter = new VoiceAgentStreamAdapter(handle);
  return adapter.stream();
}
