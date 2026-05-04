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
import {
  VoiceAgentComposeConfig,
  VoiceAgentResult as VoiceAgentResultMessage,
} from '@runanywhere/proto-ts/voice_agent_service';
import type { VoiceAgentComponentStates } from '@runanywhere/proto-ts/voice_events';
import {
  VoiceAgentComponentStates as VoiceAgentComponentStatesMessage,
} from '@runanywhere/proto-ts/voice_events';
import type { VoiceEvent } from '@runanywhere/proto-ts/voice_events';
import {
  STTLanguage,
  type STTOutput as STTOutputType,
} from '@runanywhere/proto-ts/stt_options';
import type { TTSOutput } from '@runanywhere/proto-ts/tts_options';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import { VoiceAgentStreamAdapter } from '../../Adapters/VoiceAgentStreamAdapter';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';

const logger = new SDKLogger('RunAnywhere.VoiceAgent');

/** Decode a base64 string to a `Uint8Array`. */
function base64ToBytes(b64: string): Uint8Array {
  if (!b64) return new Uint8Array(0);
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function audioToArrayBuffer(audioData: ArrayBuffer | string): ArrayBuffer {
  if (typeof audioData === 'string') {
    return bytesToArrayBuffer(base64ToBytes(audioData));
  }
  return audioData;
}

function buildVoiceAgentComposeConfig(
  config: VoiceAgentConfig
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
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();
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
  config: VoiceAgentConfig
): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();
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
    const resultBytes = await native.voiceAgentProcessTurnProto(
      audioToArrayBuffer(audioData)
    );
    const bytes = arrayBufferToBytes(resultBytes);
    if (bytes.byteLength === 0) {
      throw new Error('Voice agent proto turn returned an empty result');
    }
    return VoiceAgentResultMessage.decode(bytes);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(`Voice turn failed: ${msg}`);
    throw error;
  }
}

/**
 * Transcribe audio using the voice agent's STT component.
 *
 * Returns a `STTOutput` proto object.
 *
 * Matches Swift SDK: `RunAnywhere.voiceAgentTranscribe(_:) → STTOutput` (§10).
 */
export async function voiceAgentTranscribe(
  audioData: ArrayBuffer | string
): Promise<STTOutputType> {
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
  const raw = await native.voiceAgentTranscribe(base64Audio);
  // The native call may return a plain string (the transcript text) or a
  // JSON-encoded STTOutput. Normalise to STTOutput shape.
  try {
    const parsed = JSON.parse(raw) as Partial<STTOutputType>;
    return {
      text: parsed.text ?? raw,
      language: parsed.language ?? STTLanguage.STT_LANGUAGE_UNSPECIFIED,
      confidence: parsed.confidence ?? 1.0,
      words: parsed.words ?? [],
      alternatives: parsed.alternatives ?? [],
      metadata: parsed.metadata,
      timestampMs: parsed.timestampMs ?? Date.now(),
      durationMs: parsed.durationMs ?? 0,
    };
  } catch {
    // Native returned a plain text string — wrap it.
    return {
      text: raw,
      language: STTLanguage.STT_LANGUAGE_UNSPECIFIED,
      confidence: 1.0,
      words: [],
      alternatives: [],
      timestampMs: Date.now(),
      durationMs: 0,
    };
  }
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

/**
 * Synthesize speech using the voice-agent TTS component.
 *
 * Returns a `TTSOutput` proto object.
 *
 * Matches Swift SDK: `RunAnywhere.voiceAgentSynthesizeSpeech(_:) → TTSOutput` (§10).
 */
export async function voiceAgentSynthesizeSpeech(
  text: string
): Promise<TTSOutput> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();
  const raw = await native.voiceAgentSynthesizeSpeech(text);
  // The native call may return a base64 audio string or a JSON-encoded TTSOutput.
  try {
    const parsed = JSON.parse(raw) as Partial<{
      audioData: string | Uint8Array;
      audio_data: string;
      audioFormat: number;
      audio_format: number;
      sampleRate: number;
      sample_rate: number;
      durationMs: number;
      duration_ms: number;
      phonemeTimestamps: unknown[];
      timestampMs: number;
    }>;
    // audio_data may arrive as a base64 string from the native bridge.
    let audioData: Uint8Array;
    const rawAudio = parsed.audioData ?? parsed.audio_data;
    if (typeof rawAudio === 'string') {
      audioData = base64ToBytes(rawAudio);
    } else if (rawAudio instanceof Uint8Array) {
      audioData = rawAudio;
    } else {
      audioData = new Uint8Array(0);
    }
    return {
      audioData,
      audioFormat: (parsed.audioFormat ?? parsed.audio_format ?? AudioFormat.AUDIO_FORMAT_PCM) as AudioFormat,
      sampleRate: parsed.sampleRate ?? parsed.sample_rate ?? 22050,
      durationMs: parsed.durationMs ?? parsed.duration_ms ?? 0,
      phonemeTimestamps: [],
      timestampMs: parsed.timestampMs ?? Date.now(),
    };
  } catch {
    // Native returned a base64 audio string directly.
    const audioData = raw ? base64ToBytes(raw) : new Uint8Array(0);
    return {
      audioData,
      audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
      sampleRate: 22050,
      durationMs: 0,
      phonemeTimestamps: [],
      timestampMs: Date.now(),
    };
  }
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
