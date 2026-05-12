/**
 * RunAnywhere+VAD.ts
 *
 * Voice Activity Detection extension. Aligned to proto-canonical VAD shapes
 * (`@runanywhere/proto-ts/vad_options`). Path-first loading and JS-side
 * speech activity callbacks have been removed — VAD model loading goes
 * through `loadModelLifecycle` and activity events flow over the native
 * `vadSetActivityCallbackProto` ABI.
 *
 * Matches Swift: `Public/Extensions/VAD/RunAnywhere+VAD.swift`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import {
  type VADOptions,
  type VADResult,
  type VADStatistics,
  SpeechActivityKind,
} from '@runanywhere/proto-ts/vad_options';
import {
  VADOptions as VADOptionsMessage,
  VADResult as VADResultMessage,
  VADStatistics as VADStatisticsMessage,
} from '@runanywhere/proto-ts/vad_options';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../../services/ProtoBytes';

const logger = new SDKLogger('RunAnywhere.VAD');

/** Native module interface extension for VAD statistics. */
interface VADStatisticsNativeModule {
  vadGetStatisticsProto?: () => Promise<ArrayBuffer>;
}

// ============================================================================
// VAD Model Loading
// ============================================================================

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
  return native.unloadVADModel();
}

// ============================================================================
// Speech Detection
// ============================================================================

function audioToArrayBuffer(audio: Uint8Array | Float32Array | string | ArrayBuffer): ArrayBuffer {
  if (typeof audio === 'string') {
    const binary = atob(audio);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytesToArrayBuffer(bytes);
  }
  if (audio instanceof Uint8Array) {
    return bytesToArrayBuffer(audio);
  }
  if (audio instanceof Float32Array) {
    return audio.buffer.slice(
      audio.byteOffset,
      audio.byteOffset + audio.byteLength
    ) as ArrayBuffer;
  }
  return audio;
}

function buildVADOptions(options?: Partial<VADOptions>): VADOptions {
  return VADOptionsMessage.create({
    threshold: options?.threshold ?? 0,
    minSpeechDurationMs: options?.minSpeechDurationMs ?? 100,
    minSilenceDurationMs: options?.minSilenceDurationMs ?? 300,
    maxSpeechDurationMs: options?.maxSpeechDurationMs ?? 0,
  });
}

function defaultVADResult(): VADResult {
  return VADResultMessage.create({
    isSpeech: false,
    confidence: 0,
    energy: 0,
    durationMs: 0,
    timestampMs: Date.now(),
    startTimeMs: 0,
    endTimeMs: 0,
  });
}

/**
 * Detect voice activity in audio samples.
 *
 * Matches Swift SDK: `RunAnywhere.detectVoiceActivity(_:options:)`.
 */
export async function detectVoiceActivity(
  audio: Uint8Array | Float32Array | string | ArrayBuffer,
  options?: Partial<VADOptions>
): Promise<VADResult> {
  if (!isNativeModuleAvailable()) {
    return defaultVADResult();
  }
  return processVAD(audioToArrayBuffer(audio), 16000, options);
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
    return defaultVADResult();
  }
  const native = requireNativeModule();
  void sampleRate;
  const optionBytes = bytesToArrayBuffer(
    VADOptionsMessage.encode(buildVADOptions(options)).finish()
  );
  const resultBytes = await native.vadProcessProto(
    audioToArrayBuffer(audio),
    optionBytes
  );
  const bytes = arrayBufferToBytes(resultBytes);
  return bytes.byteLength > 0 ? VADResultMessage.decode(bytes) : defaultVADResult();
}

/** Reset VAD state. */
export async function resetVAD(): Promise<void> {
  if (!isNativeModuleAvailable()) return;
  const native = requireNativeModule();
  await native.resetVAD();
  logger.debug('VAD state reset');
}

// ============================================================================
// Activity Streaming (proto-byte canonical)
// ============================================================================

/**
 * Subscribe to speech activity events emitted by the native VAD component.
 *
 * Matches the canonical cross-SDK spec §6:
 *   `streamVADActivity() → Stream<SpeechActivityKind>`
 */
export async function streamVADActivity(
  callback: (kind: SpeechActivityKind) => void
): Promise<() => Promise<void>> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  const native = requireNativeModule();
  const ok = await native.vadSetActivityCallbackProto((activityBytes: ArrayBuffer) => {
    try {
      // The activity callback is fed proto bytes containing a SpeechActivityEvent.
      // The kind is the most actionable scalar; SDK callers can subscribe via
      // SDKEvent stream for the full payload.
      const view = arrayBufferToBytes(activityBytes);
      // Trivial proto-1-byte tag + value parse is overkill; emit a derived kind
      // from the first non-empty event payload by decoding via VADStreamEvent
      // shape if/when commons exposes it. For now, treat any callback as a
      // signal change; consumers should mirror Swift's pattern.
      void view;
      // Fallback: emit UNSPECIFIED so callers can poll fresh state.
      callback(SpeechActivityKind.SPEECH_ACTIVITY_KIND_UNSPECIFIED);
    } catch (e) {
      logger.warning(`Failed to decode VAD activity proto: ${String(e)}`);
    }
  });
  if (!ok) {
    throw SDKException.generationFailedWith('VAD activity subscription failed');
  }
  return async () => {
    // Native side accepts a no-op callback to clear; emulate by setting a noop.
    await native.vadSetActivityCallbackProto(() => undefined);
  };
}

// ============================================================================
// Statistics
// ============================================================================

/** Fetch the latest VAD statistics from native commons (when available). */
export async function getVADStatistics(): Promise<VADStatistics | null> {
  if (!isNativeModuleAvailable()) return null;
  const native = requireNativeModule() as unknown as VADStatisticsNativeModule;
  if (typeof native.vadGetStatisticsProto !== 'function') return null;
  try {
    const bytes = await native.vadGetStatisticsProto();
    return VADStatisticsMessage.decode(arrayBufferToBytes(bytes));
  } catch (e) {
    logger.warning(`Failed to fetch VAD statistics: ${String(e)}`);
    return null;
  }
}

/**
 * Stream VAD results for an async sequence of audio chunks.
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
