/**
 * RunAnywhere+TTS.ts
 *
 * Text-to-Speech extension for RunAnywhere SDK. Aligned to proto-canonical
 * TTS shapes (`@runanywhere/proto-ts/tts_options`). Path-first loading and
 * registry path probing have been removed — voice loading goes through
 * `loadModel` in `Models/RunAnywhere+ModelLifecycle.ts`.
 *
 * Matches Swift: `Public/Extensions/TTS/RunAnywhere+TTS.swift`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import { AudioPlaybackManager } from '../../../Features/VoiceSession/AudioPlaybackManager';
import {
  type TTSOptions,
  type TTSOutput,
  type TTSSpeakResult,
} from '@runanywhere/proto-ts/tts_options';
import {
  TTSOptions as TTSOptionsMessage,
  TTSOutput as TTSOutputMessage,
  TTSSpeakResult as TTSSpeakResultMessage,
  TTSSynthesisRequest,
  TTSStreamEvent,
  TTSStreamEventKind,
} from '@runanywhere/proto-ts/tts_options';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../../services/ProtoBytes';

const logger = new SDKLogger('RunAnywhere.TTS');
let requestCounter = 0;

// Internal audio playback manager for speak() functionality.
let ttsAudioPlayback: AudioPlaybackManager | null = null;

function getAudioPlayback(): AudioPlaybackManager {
  if (!ttsAudioPlayback) {
    ttsAudioPlayback = new AudioPlaybackManager();
  }
  return ttsAudioPlayback;
}

/** Encode a `Uint8Array` to a base64 string. */
function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    const byte = bytes[i];
    if (byte !== undefined) binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function buildTTSOptions(options?: Partial<TTSOptions>): TTSOptions {
  return TTSOptionsMessage.create({
    voice: options?.voice ?? '',
    languageCode: options?.languageCode ?? '',
    speakingRate: options?.speakingRate ?? 1.0,
    pitch: options?.pitch ?? 1.0,
    volume: options?.volume ?? 1.0,
    enableSsml: options?.enableSsml ?? false,
    audioFormat: options?.audioFormat ?? AudioFormat.AUDIO_FORMAT_PCM,
    sampleRate: options?.sampleRate ?? 0,
  });
}

function nextTTSRequestId(): string {
  requestCounter += 1;
  return `rn-tts-${Date.now()}-${requestCounter}`;
}

function encodeTTSSynthesisRequest(
  text: string,
  options?: Partial<TTSOptions>
): ArrayBuffer {
  const request = TTSSynthesisRequest.fromPartial({
    requestId: nextTTSRequestId(),
    text,
    options: buildTTSOptions(options),
    metadata: {},
  });
  return bytesToArrayBuffer(TTSSynthesisRequest.encode(request).finish());
}

function decodeTTSOutput(buffer: ArrayBuffer): TTSOutput {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed('ttsSynthesizeProto');
  }
  return TTSOutputMessage.decode(bytes);
}

/**
 * Synthesize text to speech.
 *
 * Matches Swift SDK: `RunAnywhere.synthesize(_:options:)`.
 */
export async function synthesize(
  text: string,
  options?: Partial<TTSOptions>
): Promise<TTSOutput> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  const native = requireNativeModule();
  return decodeTTSOutput(
    await native.ttsSynthesizeProto(encodeTTSSynthesisRequest(text, options))
  );
}

/**
 * Synthesize with streaming (chunked audio output) — callback variant.
 *
 * Matches Swift SDK: `RunAnywhere.synthesizeStream(_:options:onAudioChunk:)`.
 */
export async function synthesizeStream(
  text: string,
  options: Partial<TTSOptions> | undefined,
  onAudioChunk: (chunk: ArrayBuffer) => void
): Promise<TTSOutput> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  const native = requireNativeModule();
  let lastOutput: TTSOutput | null = null;
  await native.ttsSynthesizeStreamProto(
    encodeTTSSynthesisRequest(text, options),
    (eventBytes: ArrayBuffer) => {
      const event = TTSStreamEvent.decode(arrayBufferToBytes(eventBytes));
      if (event.kind === TTSStreamEventKind.TTS_STREAM_EVENT_KIND_ERROR) {
        throw SDKException.generationFailedWith(
          event.errorMessage ?? 'TTS stream failed'
        );
      }
      const output = event.output;
      if (!output) return;
      lastOutput = output;
      if (output.audioData.byteLength > 0) {
        onAudioChunk(bytesToArrayBuffer(output.audioData));
      }
    }
  );
  return lastOutput ?? synthesize(text, options);
}

/**
 * Stop current TTS synthesis.
 *
 * Matches Swift SDK: `RunAnywhere.stopSynthesis()`.
 */
export async function stopSynthesis(): Promise<void> {
  cancelTTS();
  const playback = getAudioPlayback();
  playback.stop();
}

// ============================================================================
// Speak (Simple Playback API)
// ============================================================================

/**
 * Speak text aloud — the simplest way to use TTS.
 *
 * Matches Swift SDK: `RunAnywhere.speak(_:options:)`.
 */
export async function speak(
  text: string,
  options?: Partial<TTSOptions>
): Promise<TTSSpeakResult> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  logger.info(`Speaking: "${text.substring(0, 50)}..."`);

  const output = await synthesize(text, options);
  if (output.audioData && output.audioData.byteLength > 0) {
    const playback = getAudioPlayback();
    await playback.play(
      bytesToBase64(output.audioData),
      output.sampleRate || options?.sampleRate || 22050
    );
  }

  return TTSSpeakResultMessage.fromPartial({
    audioFormat: output.audioFormat,
    sampleRate: output.sampleRate,
    durationMs: output.durationMs,
    audioSizeBytes: output.audioData.byteLength,
    metadata: output.metadata,
    timestampMs: output.timestampMs,
  });
}

/** Stop current speech playback. */
export async function stopSpeaking(): Promise<void> {
  const playback = getAudioPlayback();
  playback.stop();
  await stopSynthesis();
  logger.info('Speech stopped');
}

/** Cancel ongoing TTS synthesis. */
function cancelTTS(): void {
  if (!isNativeModuleAvailable()) return;
  logger.debug('TTS cancellation requested');
  requireNativeModule().ttsStopProto().catch((error: Error) => {
    logger.warning(`ttsStopProto failed: ${error.message}`);
  });
}
