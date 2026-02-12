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

// @ts-ignore – sherpa-onnx-tts.js has no .d.ts
import { initSherpaOnnxOfflineTtsConfig, freeConfig } from '../../../wasm/sherpa/sherpa-onnx-tts.js';

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

    // Build the proper C struct config for sherpa-onnx offline TTS
    // Uses the initSherpaOnnxOfflineTtsConfig helper from sherpa-onnx-tts.js
    // which packs the config into WASM memory as the C API expects.
    const configObj = {
      offlineTtsModelConfig: {
        offlineTtsVitsModelConfig: {
          model: config.modelPath,
          lexicon: config.lexicon ?? '',
          tokens: config.tokensPath,
          dataDir: config.dataDir ?? '',
          noiseScale: 0.667,
          noiseScaleW: 0.8,
          lengthScale: 1.0,
        },
        numThreads: config.numThreads ?? 1,
        debug: 0,
        provider: 'cpu',
      },
      ruleFsts: '',
      ruleFars: '',
      maxNumSentences: 1,
      silenceScale: 0.2,
    };

    logger.debug(`Building TTS config struct... (_CopyHeap available: ${typeof m._CopyHeap})`);

    let configStruct: ReturnType<typeof initSherpaOnnxOfflineTtsConfig>;
    try {
      configStruct = initSherpaOnnxOfflineTtsConfig(configObj, m);
    } catch (initErr) {
      const msg = initErr instanceof Error ? initErr.message : JSON.stringify(initErr);
      logger.error(`Failed to build TTS config struct: ${msg}`);
      throw new SDKError(SDKErrorCode.ModelLoadFailed,
        `Failed to build TTS config: ${msg}`);
    }

    try {
      logger.debug(`Calling _SherpaOnnxCreateOfflineTts with ptr=${configStruct.ptr}`);
      _ttsHandle = m._SherpaOnnxCreateOfflineTts(configStruct.ptr);

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
      if (error instanceof Error) throw error;
      const msg = typeof error === 'object' ? JSON.stringify(error) : String(error);
      throw new SDKError(SDKErrorCode.ModelLoadFailed, `TTS creation failed: ${msg}`);
    } finally {
      freeConfig(configStruct, m);
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
      logger.debug(`Calling _SherpaOnnxOfflineTtsGenerate (handle=${_ttsHandle})`);

      let audioPtr: number;
      try {
        audioPtr = m._SherpaOnnxOfflineTtsGenerate(_ttsHandle, textPtr, sid, speed);
      } catch (wasmErr: unknown) {
        // C++ exceptions thrown from WASM appear as numeric exception pointers
        let errMsg: string;
        if (typeof wasmErr === 'number') {
          // Try to extract C++ exception message from WASM memory
          let cppMsg = '';
          try {
            // Emscripten exception layout: the exception pointer points to the thrown object.
            // For std::exception, the what() string is typically at a known offset.
            // Try reading as UTF8 string from various offsets
            const offsets = [0, 4, 8, 12, 16];
            for (const off of offsets) {
              const strPtr = m.HEAP32[(wasmErr + off) / 4];
              if (strPtr > 0 && strPtr < m.HEAPU8.length) {
                const str = m.UTF8ToString(strPtr);
                if (str && str.length > 2 && str.length < 1000 && /^[\x20-\x7e]/.test(str)) {
                  cppMsg = str;
                  break;
                }
              }
            }
          } catch { /* ignore */ }
          errMsg = cppMsg
            ? `WASM C++ exception: ${cppMsg}`
            : `WASM C++ exception (ptr=${wasmErr}). Possible cause: model incompatibility or insufficient memory.`;
        } else {
          errMsg = String(wasmErr);
        }
        logger.error(`TTS WASM error: ${errMsg}`);
        throw new SDKError(SDKErrorCode.GenerationFailed, `TTS synthesis WASM error: ${errMsg}`);
      }
      logger.debug(`_SherpaOnnxOfflineTtsGenerate returned: ${audioPtr}`);

      if (!audioPtr || audioPtr === 0) {
        throw new SDKError(SDKErrorCode.GenerationFailed, 'TTS synthesis failed (null audio pointer)');
      }

      // Read the generated audio struct using HEAP32 (matches sherpa-onnx-tts.js pattern)
      const numSamples = m.HEAP32[audioPtr / 4 + 1];
      const sampleRate = m.HEAP32[audioPtr / 4 + 2];
      const samplesFloatIdx = m.HEAP32[audioPtr / 4] / 4; // float pointer / 4 = float array index

      logger.debug(`TTS audio: numSamples=${numSamples}, sampleRate=${sampleRate}, samplesIdx=${samplesFloatIdx}`);

      // Copy audio data from WASM heap
      const audioData = new Float32Array(numSamples);
      if (samplesFloatIdx && numSamples > 0) {
        for (let i = 0; i < numSamples; i++) {
          audioData[i] = m.HEAPF32[samplesFloatIdx + i];
        }
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
