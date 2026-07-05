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
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
import {
  isSDKInitialized,
  requireInitialized,
} from '../../../Foundation/Initialization/InitializedGuard';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import { AudioPlaybackManager } from '../../../Features/VoiceSession/AudioPlaybackManager';
import {
  CurrentModelRequest,
  ModelCategory,
} from '@runanywhere/proto-ts/model_types';
import { currentModel } from '../Models/RunAnywhere+ModelLifecycle';
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
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

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
  return encodeProtoMessage(request, TTSSynthesisRequest);
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
  // Swift parity: guard isInitialized (RunAnywhere+TTS.swift:26-28).
  requireInitialized();
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  await ensureServicesReady();
  const native = requireNativeModule();
  return decodeTTSOutput(
    await native.ttsSynthesizeProto(encodeTTSSynthesisRequest(text, options))
  );
}

/**
 * Synthesize with streaming chunked audio output.
 *
 * Matches Swift SDK: `RunAnywhere.synthesizeStream(_:options:)`
 * (RunAnywhere+TTS.swift:46-97) — the stream never rejects the iterator:
 *   - SDK not initialized / services not ready / no TTS voice loaded →
 *     the stream finishes silently.
 *   - A stream failure surfaces as a terminal error-marked `TTSOutput`
 *     (`isFinal=true`, non-empty `errorMessage`,
 *     `errorCode=RAC_ERROR_PROCESSING_FAILED`) followed by completion.
 */
export function synthesizeStream(
  text: string,
  options?: Partial<TTSOptions>
): AsyncIterable<TTSOutput> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }

  const native = requireNativeModule();
  const requestBytes = encodeTTSSynthesisRequest(text, options);

  // RAC_ERROR_PROCESSING_FAILED — mirrors Swift's terminal failure marker
  // (RunAnywhere+TTS.swift:84).
  const RAC_ERROR_PROCESSING_FAILED = -234;

  return {
    [Symbol.asyncIterator](): AsyncIterator<TTSOutput> {
      const queue: TTSOutput[] = [];
      let resolver: ((value: IteratorResult<TTSOutput>) => void) | null = null;
      let done = false;
      let started = false;

      const finish = (): void => {
        done = true;
        if (resolver) {
          resolver({ value: undefined as unknown as TTSOutput, done: true });
          resolver = null;
        }
      };

      const push = (output: TTSOutput): void => {
        if (resolver) {
          resolver({ value: output, done: false });
          resolver = null;
        } else {
          queue.push(output);
        }
      };

      // Terminal error-marked output — mirrors Swift's failure RATTSOutput
      // (RunAnywhere+TTS.swift:80-87): yield once, then finish.
      const failStream = (message: string): void => {
        push(
          TTSOutputMessage.fromPartial({
            timestampMs: Date.now(),
            isFinal: true,
            errorMessage: `TTS stream failed: ${message}`,
            errorCode: RAC_ERROR_PROCESSING_FAILED,
          })
        );
        finish();
      };

      const start = (): void => {
        if (started) return;
        started = true;
        (async () => {
          // Swift parity: not-initialized finishes silently
          // (RunAnywhere+TTS.swift:52-55).
          if (!isSDKInitialized()) {
            finish();
            return;
          }
          // Swift parity: a Phase-2 failure finishes silently
          // (RunAnywhere+TTS.swift:56-61).
          try {
            await ensureServicesReady();
          } catch {
            finish();
            return;
          }
          // Swift parity: no TTS voice loaded in the lifecycle finishes
          // silently (RunAnywhere+TTS.swift:65-69).
          const snapshot = await currentModel(
            CurrentModelRequest.fromPartial({
              category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
            })
          );
          if (!snapshot?.found) {
            finish();
            return;
          }

          await native
            .ttsSynthesizeStreamProto(
              requestBytes,
              (eventBytes: ArrayBuffer) => {
                if (done) return;
                try {
                  const event = TTSStreamEvent.decode(arrayBufferToBytes(eventBytes));
                  if (event.kind === TTSStreamEventKind.TTS_STREAM_EVENT_KIND_ERROR) {
                    failStream(event.errorMessage ?? 'unknown error');
                    return;
                  }
                  if (event.output) {
                    push(event.output);
                  }
                  if (
                    event.kind === TTSStreamEventKind.TTS_STREAM_EVENT_KIND_COMPLETED
                  ) {
                    finish();
                  }
                } catch (error) {
                  failStream(error instanceof Error ? error.message : String(error));
                }
              }
            )
            .then(() => {
              if (!done) finish();
            })
            .catch((err: Error) => {
              logger.warning(`ttsSynthesizeStreamProto rejected: ${err.message}`);
              if (!done) failStream(err.message);
            });
        })().catch((err: unknown) => {
          if (!done) {
            failStream(err instanceof Error ? err.message : String(err));
          }
        });
      };

      return {
        async next(): Promise<IteratorResult<TTSOutput>> {
          start();
          if (queue.length > 0) {
            return { value: queue.shift()!, done: false };
          }
          if (done) {
            return { value: undefined as unknown as TTSOutput, done: true };
          }
          return new Promise<IteratorResult<TTSOutput>>((resolve) => {
            resolver = resolve;
          });
        },
        async return(): Promise<IteratorResult<TTSOutput>> {
          await cancelTTS();
          finish();
          return { value: undefined as unknown as TTSOutput, done: true };
        },
      };
    },
  };
}

/**
 * Stop current TTS synthesis.
 *
 * Matches Swift SDK: `RunAnywhere.stopSynthesis()`.
 */
export async function stopSynthesis(): Promise<void> {
  await cancelTTS();
  const playback = getAudioPlayback();
  playback.stop();
}

// Speak (Simple Playback API)

/**
 * Speak text aloud — the simplest way to use TTS.
 *
 * Matches Swift SDK: `RunAnywhere.speak(_:options:)`.
 */
export async function speak(
  text: string,
  options?: Partial<TTSOptions>
): Promise<TTSSpeakResult> {
  // Swift parity: guard isInitialized (RunAnywhere+TTS.swift:114-116).
  requireInitialized();
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
async function cancelTTS(): Promise<void> {
  if (!isNativeModuleAvailable()) return;
  logger.debug('TTS cancellation requested');
  await requireNativeModule().ttsStopProto().catch((error: Error) => {
    logger.warning(`ttsStopProto failed: ${error.message}`);
  });
}
