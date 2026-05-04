/**
 * RunAnywhere+TTS.ts
 *
 * Text-to-Speech extension for RunAnywhere SDK. Wave 2: aligned to
 * proto-canonical TTS shapes (`@runanywhere/proto-ts/tts_options`). All
 * legacy ad-hoc shapes have been deleted.
 *
 * Matches Swift: `Public/Extensions/TTS/RunAnywhere+TTS.swift`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { AudioPlaybackManager } from '../../Features/VoiceSession/AudioPlaybackManager';
import { ModelRegistry } from '../../services/ModelRegistry';
import {
  type TTSOptions,
  type TTSOutput,
  type TTSSpeakResult,
  type TTSVoiceInfo,
} from '@runanywhere/proto-ts/tts_options';
import {
  TTSOptions as TTSOptionsMessage,
  TTSOutput as TTSOutputMessage,
  TTSVoiceInfo as TTSVoiceInfoMessage,
} from '@runanywhere/proto-ts/tts_options';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';

const logger = new SDKLogger('RunAnywhere.TTS');

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

function encodeTTSOptions(options?: Partial<TTSOptions>): ArrayBuffer {
  return bytesToArrayBuffer(TTSOptionsMessage.encode(buildTTSOptions(options)).finish());
}

function decodeTTSOutput(buffer: ArrayBuffer): TTSOutput {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw new Error('TTS proto synthesis returned an empty result');
  }
  return TTSOutputMessage.decode(bytes);
}

// ============================================================================
// Voice / Model Loading
// ============================================================================

/** Load a TTS model. */
export async function loadTTSModel(
  modelPath: string,
  modelType: string = 'piper',
  config?: Record<string, unknown>
): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    logger.warning('Native module not available for loadTTSModel');
    return false;
  }
  const native = requireNativeModule();
  return native.loadTTSModel(
    modelPath,
    modelType,
    config ? JSON.stringify(config) : undefined
  );
}

/** Load a TTS voice by ID. */
export async function loadTTSVoice(voiceId: string): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  logger.info(`Loading TTS voice: ${voiceId}`);
  const native = requireNativeModule();
  const modelInfo = await ModelRegistry.getModel(voiceId);
  if (!modelInfo?.localPath) {
    throw new Error(`Voice '${voiceId}' is not downloaded`);
  }
  const loaded = await native.loadTTSModel(modelInfo.localPath, 'piper');
  if (!loaded) {
    throw new Error(`Failed to load voice '${voiceId}'`);
  }
  logger.info(`TTS voice loaded: ${voiceId}`);
}

/** Unload the current TTS voice. */
export async function unloadTTSVoice(): Promise<void> {
  if (!isNativeModuleAvailable()) return;
  const native = requireNativeModule();
  await native.unloadTTSModel();
  logger.info('TTS voice unloaded');
}

/** Check if a TTS model is loaded. */
export async function isTTSModelLoaded(): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = requireNativeModule();
  return native.isTTSModelLoaded();
}

/** Check if a TTS voice is loaded. */
export async function isTTSVoiceLoaded(): Promise<boolean> {
  return isTTSModelLoaded();
}

/** Unload the current TTS model. */
export async function unloadTTSModel(): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = requireNativeModule();
  return native.unloadTTSModel();
}

// ============================================================================
// Voice Management
// ============================================================================

/**
 * Get available TTS voices (IDs only).
 *
 * Matches Swift SDK: `RunAnywhere.availableTTSVoices`.
 */
export async function availableTTSVoices(): Promise<string[]> {
  const voices = await getTTSVoiceInfo();
  return voices.map((voice) => voice.id);
}

/** Get detailed voice information. */
export async function getTTSVoiceInfo(): Promise<TTSVoiceInfo[]> {
  if (!isNativeModuleAvailable()) return [];
  const native = requireNativeModule();
  const voices: TTSVoiceInfo[] = [];
  const ok = await native.ttsListVoicesProto((voiceBytes: ArrayBuffer) => {
    voices.push(TTSVoiceInfoMessage.decode(arrayBufferToBytes(voiceBytes)));
  });
  return ok ? voices : [];
}

// ============================================================================
// Synthesis
// ============================================================================

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
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();
  return decodeTTSOutput(await native.ttsSynthesizeProto(text, encodeTTSOptions(options)));
}

/**
 * Streaming TTS handle (mirrors LLM/VLM streaming primitive).
 */
export interface TTSStreamingResult {
  chunks: AsyncIterable<ArrayBuffer>;
  result: Promise<TTSOutput>;
  cancel: () => void;
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
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();
  let lastOutput: TTSOutput | null = null;
  await native.ttsSynthesizeStreamProto(
    text,
    encodeTTSOptions(options),
    (chunkBytes: ArrayBuffer) => {
      const output = decodeTTSOutput(chunkBytes);
      lastOutput = output;
      if (output.audioData.byteLength > 0) {
        onAudioChunk(bytesToArrayBuffer(output.audioData));
      }
    }
  );
  return lastOutput ?? synthesize(text, options);
}

/** AsyncIterable variant of `synthesizeStream`. */
export async function synthesizeStreamAsync(
  text: string,
  options?: Partial<TTSOptions>
): Promise<TTSStreamingResult> {
  const queue: ArrayBuffer[] = [];
  let resolver: ((value: IteratorResult<ArrayBuffer>) => void) | null = null;
  let done = false;
  let streamError: Error | null = null;
  let cancelled = false;

  let resolveResult!: (value: TTSOutput) => void;
  let rejectResult!: (err: Error) => void;
  const resultPromise = new Promise<TTSOutput>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });

  const pushChunk = (chunk: ArrayBuffer): void => {
    if (cancelled) return;
    if (resolver) {
      resolver({ value: chunk, done: false });
      resolver = null;
    } else {
      queue.push(chunk);
    }
  };

  synthesizeStream(text, options, pushChunk)
    .then((output) => {
      done = true;
      resolveResult(output);
      if (resolver) {
        resolver({ value: undefined as unknown as ArrayBuffer, done: true });
        resolver = null;
      }
    })
    .catch((err: Error) => {
      streamError = err;
      done = true;
      rejectResult(err);
      if (resolver) {
        resolver({ value: undefined as unknown as ArrayBuffer, done: true });
        resolver = null;
      }
    });

  async function* chunkGenerator(): AsyncGenerator<ArrayBuffer> {
    while (!done || queue.length > 0) {
      if (queue.length > 0) {
        yield queue.shift()!;
      } else if (!done) {
        const next = await new Promise<IteratorResult<ArrayBuffer>>((resolve) => {
          resolver = resolve;
        });
        if (next.done) break;
        yield next.value;
      }
    }
    if (streamError) throw streamError;
  }

  const cancel = (): void => {
    cancelled = true;
    cancelTTS();
    if (resolver) {
      done = true;
      resolver({ value: undefined as unknown as ArrayBuffer, done: true });
      resolver = null;
    }
  };

  return {
    chunks: chunkGenerator(),
    result: resultPromise,
    cancel,
  };
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
    throw new Error('Native module not available');
  }
  logger.info(`Speaking: "${text.substring(0, 50)}..."`);

  const output = await synthesize(text, options);
  if (output.audioData && output.audioData.byteLength > 0) {
    const playback = getAudioPlayback();
    await playback.play(bytesToBase64(output.audioData));
  }

  return {
    audioFormat: output.audioFormat,
    sampleRate: output.sampleRate,
    durationMs: output.durationMs,
    audioSizeBytes: output.audioData.byteLength,
    metadata: output.metadata,
    timestampMs: output.timestampMs,
  };
}

/** Whether speech is currently playing. */
export function isSpeaking(): boolean {
  const playback = getAudioPlayback();
  return playback.isPlaying;
}

/** Stop current speech playback. */
export async function stopSpeaking(): Promise<void> {
  const playback = getAudioPlayback();
  playback.stop();
  await stopSynthesis();
  logger.info('Speech stopped');
}

/** Cancel ongoing TTS synthesis. */
export function cancelTTS(): void {
  if (!isNativeModuleAvailable()) return;
  logger.debug('TTS cancellation requested');
}

// ============================================================================
// Cleanup
// ============================================================================

/** Cleanup TTS resources. */
export function cleanupTTS(): void {
  if (ttsAudioPlayback) {
    ttsAudioPlayback.cleanup();
    ttsAudioPlayback = null;
  }
}

// ============================================================================
// Introspection
// ============================================================================

interface TTSIntrospectionNativeModule {
  currentTTSModel?: () => Promise<string>;
  getCurrentTTSVoiceId?: () => Promise<string>;
  currentTTSVoiceId?: () => Promise<string>;
}

/**
 * Get the currently loaded TTS model/voice ID, or `null` if none.
 *
 * Matches Swift: `RunAnywhere.currentTTSModel`.
 */
export async function currentTTSModel(): Promise<string | null> {
  if (!isNativeModuleAvailable()) return null;
  const native = requireNativeModule() as unknown as TTSIntrospectionNativeModule;
  const fn =
    native.currentTTSModel ??
    native.currentTTSVoiceId ??
    native.getCurrentTTSVoiceId;
  if (!fn) return null;
  const id = await fn.call(native);
  return id && id.length > 0 ? id : null;
}
