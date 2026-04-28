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
import {
  type TTSOptions,
  type TTSOutput,
  type TTSSpeakResult,
  type TTSSynthesisMetadata,
  type TTSVoiceInfo,
} from '@runanywhere/proto-ts/tts_options';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';

const logger = new SDKLogger('RunAnywhere.TTS');

// Internal audio playback manager for speak() functionality.
let ttsAudioPlayback: AudioPlaybackManager | null = null;

function getAudioPlayback(): AudioPlaybackManager {
  if (!ttsAudioPlayback) {
    ttsAudioPlayback = new AudioPlaybackManager();
  }
  return ttsAudioPlayback;
}

/** Decode a base64 string to a `Uint8Array`. */
function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
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
  const modelInfoJson = await native.getModelInfo(voiceId);
  const modelInfo = JSON.parse(modelInfoJson);
  if (!modelInfo.localPath) {
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
  if (!isNativeModuleAvailable()) return [];
  const native = requireNativeModule();
  const voicesJson = await native.getTTSVoices();
  try {
    const voices = JSON.parse(voicesJson);
    if (Array.isArray(voices)) {
      return voices.map((v: TTSVoiceInfo | string) =>
        typeof v === 'string' ? v : v.id
      );
    }
    return [];
  } catch {
    return voicesJson ? [voicesJson] : [];
  }
}

/** Get detailed voice information. */
export async function getTTSVoiceInfo(): Promise<TTSVoiceInfo[]> {
  if (!isNativeModuleAvailable()) return [];
  const native = requireNativeModule();
  const voicesJson = await native.getTTSVoices();
  try {
    const voices = JSON.parse(voicesJson);
    if (!Array.isArray(voices)) return [];
    return voices.map(
      (
        v: Partial<TTSVoiceInfo> & {
          id?: string;
          name?: string;
          displayName?: string;
          language?: string;
        }
      ): TTSVoiceInfo => ({
        id: v.id ?? '',
        displayName: v.displayName ?? v.name ?? v.id ?? '',
        languageCode: v.languageCode ?? v.language ?? 'en-US',
        gender: v.gender ?? 0,
        description: v.description ?? '',
      })
    );
  } catch {
    return [];
  }
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
  const startTime = Date.now();
  const native = requireNativeModule();

  const voiceId = options?.voice ?? '';
  const speedRate = options?.speakingRate ?? 1.0;
  const pitchShift = options?.pitch ?? 1.0;

  const resultJson = await native.synthesize(
    text,
    voiceId,
    speedRate,
    pitchShift
  );
  const endTime = Date.now();
  const processingTimeMs = endTime - startTime;

  try {
    const result = JSON.parse(resultJson);
    const sampleRate = result.sampleRate ?? 22050;
    const audioSize = result.audioSize ?? 0;
    const numSamples = Math.floor(audioSize / 4);
    const durationMs = result.durationMs
      ? result.durationMs
      : numSamples > 0
      ? Math.round((numSamples / sampleRate) * 1000)
      : 0;

    const audioBase64 = result.audioBase64 ?? result.audio ?? '';
    const audioData = audioBase64 ? base64ToBytes(audioBase64) : new Uint8Array(0);

    const metadata: TTSSynthesisMetadata = {
      voiceId: voiceId || 'default',
      languageCode: options?.languageCode ?? '',
      processingTimeMs,
      characterCount: text.length,
      audioDurationMs: durationMs,
    };

    return {
      audioData,
      audioFormat: options?.audioFormat ?? AudioFormat.AUDIO_FORMAT_PCM,
      sampleRate,
      durationMs,
      phonemeTimestamps: result.phonemeTimestamps ?? [],
      metadata,
      timestampMs: Date.now(),
    };
  } catch (err) {
    if (err instanceof Error) throw err;
    if (resultJson.includes('error')) throw new Error(resultJson);
    return {
      audioData: new Uint8Array(0),
      audioFormat: options?.audioFormat ?? AudioFormat.AUDIO_FORMAT_PCM,
      sampleRate: 22050,
      durationMs: 0,
      phonemeTimestamps: [],
      metadata: {
        voiceId: voiceId || 'default',
        languageCode: options?.languageCode ?? '',
        processingTimeMs,
        characterCount: text.length,
        audioDurationMs: 0,
      },
      timestampMs: Date.now(),
    };
  }
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
  const output = await synthesize(text, options);
  if (output.audioData && output.audioData.byteLength > 0) {
    try {
      onAudioChunk(output.audioData.buffer.slice(
        output.audioData.byteOffset,
        output.audioData.byteOffset + output.audioData.byteLength
      ) as ArrayBuffer);
    } catch (error) {
      logger.error(`Failed to emit audio chunk: ${error}`);
    }
  }
  return output;
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
