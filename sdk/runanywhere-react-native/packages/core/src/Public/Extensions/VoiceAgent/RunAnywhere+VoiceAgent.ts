/**
 * RunAnywhere+VoiceAgent.ts
 *
 * Voice agent (full VAD → STT → LLM → TTS) extension. All shapes come from
 * `@runanywhere/proto-ts/voice_agent_service` and
 * `@runanywhere/proto-ts/voice_events`; commons owns the pipeline.
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/RunAnywhere+VoiceAgent.swift`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import type {
  VoiceAgentResult,
  VoiceSessionConfig,
} from '@runanywhere/proto-ts/voice_agent_service';
import {
  VoiceAgentComposeConfig,
  VoiceAgentResult as VoiceAgentResultMessage,
} from '@runanywhere/proto-ts/voice_agent_service';
import type { VoiceAgentComponentStates } from '@runanywhere/proto-ts/voice_events';
import {
  VoiceAgentComponentStates as VoiceAgentComponentStatesMessage,
} from '@runanywhere/proto-ts/voice_events';
import type { VoiceEvent } from '@runanywhere/proto-ts/voice_events';
import { VoiceAgentStreamAdapter } from '../../../Adapters/VoiceAgentStreamAdapter';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../../services/ProtoBytes';

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
 * Get the native voice-agent handle.
 *
 * Internal bridge detail for `streamVoiceAgent()`.
 */
async function getVoiceAgentHandle(): Promise<number> {
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
