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
import { ErrorCode as ErrorCodeProto } from '@runanywhere/proto-ts/errors';
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
import {
  CurrentModelRequest,
  ModelCategory,
  ModelLoadRequest,
} from '@runanywhere/proto-ts/model_types';
import { currentModel, loadModel } from '../Models/RunAnywhere+ModelLifecycle';
import { VoiceAgentStreamAdapter } from '../../../Adapters/VoiceAgentStreamAdapter';
import { arrayBufferToBytes, bytesToArrayBuffer } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

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
    const composeConfig = buildVoiceAgentComposeConfig(config);
    const bytes = await native.voiceAgentInitializeProto(
      encodeProtoMessage(composeConfig, VoiceAgentComposeConfig)
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
 * Default Silero VAD model id seeded by every example app's catalog.
 * Exposed so callers do not hard-code the string when invoking
 * `ensureDefaultVAD(...)`. Mirrors Swift `RunAnywhere.defaultVADModelID`.
 */
export const defaultVADModelID = 'silero-vad';

/**
 * Ensure a VAD model is loaded in the canonical lifecycle before a voice
 * agent session starts. When no VAD model is currently registered for
 * `MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION`, attempts to load the
 * catalogued default (`defaultVADModelID`, Silero) so the voice agent's
 * speech-start / speech-end events fire. The energy-based fallback does
 * not produce the lifecycle events the voice-agent orchestrator listens
 * for, so without a VAD lifecycle load the session stays silent after
 * init.
 *
 * Idempotent: returns `true` immediately when a VAD model is already
 * loaded. Logs (but does not throw) when the optional auto-load fails;
 * callers may inspect the return value to decide whether to surface a
 * warning. Mirrors Swift `ensureDefaultVAD(modelID:)`.
 *
 * @param modelID VAD model id to auto-load when none is current. When
 *   omitted, falls back to `defaultVADModelID`.
 * @returns `true` when a VAD model is loaded after the call; `false`
 *   when no VAD model is loaded (auto-load failed or skipped).
 */
export async function ensureDefaultVAD(modelID?: string): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;

  const snapshot = await currentModel(
    CurrentModelRequest.fromPartial({
      category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
    })
  );
  if (snapshot && snapshot.found && snapshot.modelId.length > 0) {
    return true;
  }

  const targetID = modelID ?? defaultVADModelID;
  if (targetID.length === 0) return false;

  logger.info(`Auto-loading default VAD '${targetID}' for voice-agent session`);

  const result = await loadModel(
    ModelLoadRequest.fromPartial({
      modelId: targetID,
      category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
    })
  );
  if (!result.success) {
    logger.warning(
      `Default VAD '${targetID}' auto-load failed: ${result.errorMessage} — voice agent will use energy fallback`
    );
    return false;
  }
  return true;
}

/**
 * Initialize voice agent using already-loaded models.
 *
 * Composes a `VoiceAgentComposeConfig` from the canonical model lifecycle
 * (`currentModel`) snapshots for `.speechRecognition`, `.language`, and
 * `.speechSynthesis`, then forwards to `voiceAgentInitializeProto`. Mirrors
 * the Swift `initializeVoiceAgentWithLoadedModels(ttsVoiceID:ensureVAD:)` API.
 *
 * When `ensureVAD` is `true` (default), the SDK guarantees that a VAD model
 * is loaded into the canonical lifecycle before initialization runs via
 * {@link ensureDefaultVAD}. Without this the session would silently fall back
 * to the energy-based detector and the C++ voice agent's speech-start /
 * speech-end lifecycle events would not fire. Set to `false` only if the
 * caller has already loaded an explicit VAD model (or knows the energy
 * fallback is acceptable for the deployment).
 *
 * @param ttsVoiceID Optional explicit voice id to pass through to the TTS
 *   engine. For multi-voice TTS engines, this selects the voice within the
 *   loaded model and is semantically distinct from the TTS model id. When
 *   `undefined` (default), the engine's default voice is used. Never reuse
 *   the TTS model id here — model id ≠ voice id.
 * @param ensureVAD Whether to auto-load the catalogued default VAD when no
 *   `MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION` model is loaded. Defaults to
 *   `true`.
 *
 * Mirrors Swift `initializeVoiceAgentWithLoadedModels(ttsVoiceID:ensureVAD:)`.
 */
export async function initializeVoiceAgentWithLoadedModels(
  ttsVoiceID?: string,
  ensureVAD: boolean = true
): Promise<void> {
  const native = ensureNative();
  try {
    if (ensureVAD) {
      await ensureDefaultVAD();
    }

    const sttSnap = await currentModel(
      CurrentModelRequest.fromPartial({
        category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
      })
    );
    const llmSnap = await currentModel(
      CurrentModelRequest.fromPartial({
        category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      })
    );
    const ttsSnap = await currentModel(
      CurrentModelRequest.fromPartial({
        category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
      })
    );

    const missing: string[] = [];
    if (!sttSnap?.found || !sttSnap.modelId) missing.push('STT');
    if (!llmSnap?.found || !llmSnap.modelId) missing.push('LLM');
    if (!ttsSnap?.found || !ttsSnap.modelId) missing.push('TTS');
    if (missing.length > 0) {
      throw SDKException.of(
        ErrorCodeProto.ERROR_CODE_MODEL_NOT_LOADED,
        `Cannot initialize voice agent: Models not loaded: ${missing.join(', ')}`
      );
    }

    logger.info('Initializing voice agent with loaded models...');
    const composeConfig = VoiceAgentComposeConfig.create({
      sttModelId: sttSnap!.modelId,
      llmModelId: llmSnap!.modelId,
      ...(ttsVoiceID && ttsVoiceID.length > 0 ? { ttsVoiceId: ttsVoiceID } : {}),
    });
    await native.voiceAgentInitializeProto(
      encodeProtoMessage(composeConfig, VoiceAgentComposeConfig)
    );
    logger.info('Voice agent initialized with loaded models');
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
 * The iterable is constructed synchronously; the native handle is obtained
 * lazily on the first `next()` call, matching Swift's synchronous
 * `AsyncStream` return and the existing RN `generateStream` pattern.
 *
 * Matches Swift: `RunAnywhere.streamVoiceAgent() -> AsyncStream<RAVoiceEvent>`.
 *
 * Usage:
 *   for await (const evt of RunAnywhere.streamVoiceAgent()) { handleEvent(evt) }
 */
export function streamVoiceAgent(): AsyncIterable<VoiceEvent> {
  return {
    async *[Symbol.asyncIterator]() {
      const handle = await getVoiceAgentHandle();
      const adapter = new VoiceAgentStreamAdapter(handle);
      yield* adapter.stream();
    },
  };
}
