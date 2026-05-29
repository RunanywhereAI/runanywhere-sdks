/**
 * RunAnywhere+VAD.ts
 *
 * Voice Activity Detection extension. Aligned to proto-canonical VAD shapes
 * (`@runanywhere/proto-ts/vad_options`). Path-first loading and JS-side
 * speech activity callbacks have been removed — VAD model loading goes
 * through `loadModel` and activity events flow over the native
 * `vadSetActivityCallbackProto` ABI.
 *
 * Matches Swift: `Public/Extensions/VAD/RunAnywhere+VAD.swift`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import {
  type VADOptions,
  type VADResult,
  VADAudioEncoding,
} from '@runanywhere/proto-ts/vad_options';
import {
  VADAudioSource,
  VADOptions as VADOptionsMessage,
  VADProcessRequest,
  VADResult as VADResultMessage,
} from '@runanywhere/proto-ts/vad_options';
import { arrayBufferToBytes, bytesToArrayBuffer } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

const logger = new SDKLogger('RunAnywhere.VAD');
let requestCounter = 0;

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

function nextVADRequestId(): string {
  requestCounter += 1;
  return `rn-vad-${Date.now()}-${requestCounter}`;
}

function buildVADRequestBytes(
  audio: ArrayBuffer,
  sampleRate: number,
  options?: Partial<VADOptions>
): ArrayBuffer {
  const request = VADProcessRequest.fromPartial({
    requestId: nextVADRequestId(),
    audio: VADAudioSource.fromPartial({
      audioData: arrayBufferToBytes(audio),
      encoding: VADAudioEncoding.VAD_AUDIO_ENCODING_PCM_F32_LE,
      sampleRate,
      channels: 1,
    }),
    options: buildVADOptions(options),
    metadata: {},
  });
  return encodeProtoMessage(request, VADProcessRequest);
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
    throw SDKException.nativeModuleUnavailable();
  }
  const native = requireNativeModule();
  if (!(await native.isInitialized())) {
    throw SDKException.notInitialized();
  }
  await ensureServicesReady();
  return processVAD(audioToArrayBuffer(audio), 16000, options);
}

/**
 * Process audio for voice activity detection — returns the full proto result.
 */
async function processVAD(
  audio: string | ArrayBuffer,
  sampleRate: number = 16000,
  options?: Partial<VADOptions>
): Promise<VADResult> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  const native = requireNativeModule();
  const resultBytes = await native.vadProcessProto(
    buildVADRequestBytes(audioToArrayBuffer(audio), sampleRate, options)
  );
  const bytes = arrayBufferToBytes(resultBytes);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed('vadProcessProto');
  }
  return VADResultMessage.decode(bytes);
}

/** Reset VAD state. */
export async function resetVAD(): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  const native = requireNativeModule();
  if (!(await native.isInitialized())) {
    throw SDKException.notInitialized();
  }
  await native.resetVAD();
  logger.debug('VAD state reset');
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
