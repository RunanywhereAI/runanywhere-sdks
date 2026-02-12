/**
 * RunAnywhere Web SDK - Text-to-Speech Extension
 *
 * Adds TTS (speech synthesis) capabilities via sherpa-onnx WASM.
 * Uses Piper/VITS ONNX models for offline, on-device speech synthesis.
 *
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/TTS/
 *
 * Usage:
 *   import { TTS } from '@runanywhere/web';
 *
 *   await TTS.loadVoice({
 *     voiceId: 'piper-en-amy',
 *     modelPath: '/models/tts/model.onnx',
 *     tokensPath: '/models/tts/tokens.txt',
 *     dataDir: '/models/tts/espeak-ng-data',
 *   });
 *
 *   const result = await TTS.synthesize('Hello world');
 *   // result.audioData is Float32Array of PCM samples
 */

import { RunAnywhere } from '../RunAnywhere';
import { SherpaONNXBridge } from '../../Foundation/SherpaONNXBridge';
import { SDKError, SDKErrorCode } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType } from '../../types/enums';

const logger = new SDKLogger('TTS');

// ---------------------------------------------------------------------------
// Internal State
// ---------------------------------------------------------------------------

let _ttsHandle = 0;
let _currentVoiceId = '';

// ---------------------------------------------------------------------------
// TTS Types
// ---------------------------------------------------------------------------

export interface TTSVoiceConfig {
  voiceId: string;
  /** Path to the VITS/Piper model ONNX file in sherpa FS */
  modelPath: string;
  /** Path to the tokens.txt file in sherpa FS */
  tokensPath: string;
  /** Path to the espeak-ng-data directory in sherpa FS (for Piper models) */
  dataDir?: string;
  /** Path to the lexicon file in sherpa FS (optional) */
  lexicon?: string;
  /** Number of threads (default: 1) */
  numThreads?: number;
}

export interface TTSSynthesisResult {
  /** Raw PCM audio data */
  audioData: Float32Array;
  /** Audio sample rate */
  sampleRate: number;
  /** Duration in milliseconds */
  durationMs: number;
  /** Processing time in milliseconds */
  processingTimeMs: number;
}

export interface TTSSynthesizeOptions {
  /** Speaker ID for multi-speaker models (default: 0) */
  speakerId?: number;
  /** Speed factor (default: 1.0, >1 = faster, <1 = slower) */
  speed?: number;
}

// ---------------------------------------------------------------------------
// TTS Extension
// ---------------------------------------------------------------------------

export const TTS = {
  /**
   * Load a TTS voice model via sherpa-onnx.
   * Model files must already be written to sherpa-onnx virtual FS.
   */
  async loadVoice(config: TTSVoiceConfig): Promise<void> {
    const sherpa = requireSherpa();
    await sherpa.ensureLoaded();
    const m = sherpa.module;

    // Clean up previous voice
    TTS.cleanup();

    logger.info(`Loading TTS voice: ${config.voiceId}`);
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, {
      modelId: config.voiceId, component: 'tts',
    });

    const startMs = performance.now();

    // Build config JSON for sherpa-onnx offline TTS
    // sherpa-onnx expects a PrintOfflineTtsConfig-style struct, but the
    // WASM C API takes a pointer. We build the struct manually in WASM memory.
    // For the WASM API, we use ccall with the JSON-based approach.
    const configJson = JSON.stringify({
      'model': {
        'vits': {
          'model': config.modelPath,
          'tokens': config.tokensPath,
          'data-dir': config.dataDir ?? '',
          'lexicon': config.lexicon ?? '',
          'noise-scale': 0.667,
          'noise-scale-w': 0.8,
          'length-scale': 1.0,
        },
        'num-threads': config.numThreads ?? 1,
        'provider': 'cpu',
        'debug': 0,
      },
      'max-num-sentences': 1,
    });

    const configPtr = sherpa.allocString(configJson);

    try {
      _ttsHandle = m.ccall(
        'SherpaOnnxCreateOfflineTts', 'number', ['number'], [configPtr],
      ) as number;

      if (_ttsHandle === 0) {
        throw new SDKError(SDKErrorCode.ModelLoadFailed,
          `Failed to create TTS engine for voice: ${config.voiceId}`);
      }

      _currentVoiceId = config.voiceId;

      const loadTimeMs = Math.round(performance.now() - startMs);
      logger.info(`TTS voice loaded: ${config.voiceId} in ${loadTimeMs}ms`);
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, {
        modelId: config.voiceId, component: 'tts', loadTimeMs,
      });
    } catch (error) {
      TTS.cleanup();
      throw error;
    } finally {
      sherpa.free(configPtr);
    }
  },

  /** Unload the TTS voice. */
  async unloadVoice(): Promise<void> {
    TTS.cleanup();
    logger.info('TTS voice unloaded');
  },

  /** Check if a TTS voice is loaded. */
  get isVoiceLoaded(): boolean {
    return _ttsHandle !== 0;
  },

  /** Get current voice ID. */
  get voiceId(): string {
    return _currentVoiceId;
  },

  /** Get the sample rate of the loaded TTS model. */
  get sampleRate(): number {
    if (_ttsHandle === 0) return 0;
    return SherpaONNXBridge.shared.module._SherpaOnnxOfflineTtsSampleRate(_ttsHandle);
  },

  /** Get the number of speakers in the loaded model. */
  get numSpeakers(): number {
    if (_ttsHandle === 0) return 0;
    return SherpaONNXBridge.shared.module._SherpaOnnxOfflineTtsNumSpeakers(_ttsHandle);
  },

  /**
   * Synthesize speech from text.
   *
   * @param text - Text to synthesize
   * @param options - Synthesis options (speaker ID, speed)
   * @returns Synthesis result with PCM audio data
   */
  async synthesize(text: string, options: TTSSynthesizeOptions = {}): Promise<TTSSynthesisResult> {
    const sherpa = requireSherpa();
    const m = sherpa.module;

    if (_ttsHandle === 0) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No TTS voice loaded. Call loadVoice() first.');
    }

    const startMs = performance.now();
    const sid = options.speakerId ?? 0;
    const speed = options.speed ?? 1.0;

    logger.debug(`Synthesizing: "${text.substring(0, 80)}..." (sid=${sid}, speed=${speed})`);

    const textPtr = sherpa.allocString(text);

    try {
      // SherpaOnnxOfflineTtsGenerate returns a pointer to generated audio struct:
      // struct { const float* samples; int32_t n; int32_t sample_rate; }
      const audioPtr = m._SherpaOnnxOfflineTtsGenerate(_ttsHandle, textPtr, sid, speed);

      if (audioPtr === 0) {
        throw new SDKError(SDKErrorCode.GenerationFailed, 'TTS synthesis failed');
      }

      // Read the generated audio struct
      const samplesPtr = m.getValue(audioPtr, '*');
      const numSamples = m.getValue(audioPtr + 4, 'i32');
      const sampleRate = m.getValue(audioPtr + 8, 'i32');

      // Copy audio data
      const audioData = new Float32Array(numSamples);
      if (samplesPtr && numSamples > 0) {
        audioData.set(m.HEAPF32.subarray(samplesPtr / 4, samplesPtr / 4 + numSamples));
      }

      // Destroy the audio struct
      m._SherpaOnnxDestroyOfflineTtsGeneratedAudio(audioPtr);

      const processingTimeMs = Math.round(performance.now() - startMs);
      const durationMs = Math.round((numSamples / sampleRate) * 1000);

      const result: TTSSynthesisResult = {
        audioData,
        sampleRate,
        durationMs,
        processingTimeMs,
      };

      EventBus.shared.emit('tts.synthesized', SDKEventType.Voice, {
        durationMs,
        sampleRate,
        textLength: text.length,
      });

      logger.debug(`TTS generated ${durationMs}ms audio in ${processingTimeMs}ms`);
      return result;
    } finally {
      sherpa.free(textPtr);
    }
  },

  /** Clean up the TTS resources. */
  cleanup(): void {
    if (_ttsHandle !== 0) {
      try {
        SherpaONNXBridge.shared.module._SherpaOnnxDestroyOfflineTts(_ttsHandle);
      } catch { /* ignore */ }
      _ttsHandle = 0;
    }
    _currentVoiceId = '';
  },
};

// ---------------------------------------------------------------------------
// Internal Helpers
// ---------------------------------------------------------------------------

function requireSherpa(): SherpaONNXBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return SherpaONNXBridge.shared;
}
