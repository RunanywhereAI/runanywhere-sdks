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

import { RunAnywhere, SDKError, SDKErrorCode, SDKLogger, EventBus, SDKEventType, AnalyticsEmitter } from '@runanywhere/web';
import { SherpaONNXBridge } from '../Foundation/SherpaONNXBridge';
import type { TTSVoiceConfig, TTSSynthesisResult, TTSSynthesizeOptions } from './TTSTypes';

export type { TTSVoiceConfig } from './TTSTypes';

import { loadTTSHelpers } from '../Foundation/SherpaHelperLoader';
import type { SherpaConfigHandle } from '../Foundation/SherpaHelperLoader';

const logger = new SDKLogger('TTS');

/** Matches RAC_FRAMEWORK_ONNX in rac_model_types.h */
const RAC_FRAMEWORK_ONNX = 0;

// ---------------------------------------------------------------------------
// Internal Helpers
// ---------------------------------------------------------------------------

function requireSherpa(): SherpaONNXBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return SherpaONNXBridge.shared;
}

// ---------------------------------------------------------------------------
// TTS Extension
// ---------------------------------------------------------------------------

class TTSImpl {
  readonly extensionName = 'TTS';
  private _ttsHandle = 0;
  private _currentVoiceId = '';

  /**
   * Load a TTS voice model via sherpa-onnx.
   * Model files must already be written to sherpa-onnx virtual FS.
   */
  async loadVoice(config: TTSVoiceConfig): Promise<void> {
    const sherpa = requireSherpa();
    await sherpa.ensureLoaded();
    const m = sherpa.module;

    // Clean up previous voice
    this.cleanup();

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

    const { initSherpaOnnxOfflineTtsConfig, freeConfig } = await loadTTSHelpers();

    let configStruct: SherpaConfigHandle;
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
      this._ttsHandle = m._SherpaOnnxCreateOfflineTts(configStruct.ptr);

      if (this._ttsHandle === 0) {
        throw new SDKError(SDKErrorCode.ModelLoadFailed,
          `Failed to create TTS engine for voice: ${config.voiceId}`);
      }

      this._currentVoiceId = config.voiceId;

      const loadTimeMs = Math.round(performance.now() - startMs);
      logger.info(`TTS voice loaded: ${config.voiceId} in ${loadTimeMs}ms`);
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, {
        modelId: config.voiceId, component: 'tts', loadTimeMs,
      });
      AnalyticsEmitter.emitTTSVoiceLoadCompleted(config.voiceId, config.voiceId, loadTimeMs, RAC_FRAMEWORK_ONNX);
    } catch (error) {
      this.cleanup();
      if (error instanceof Error) throw error;
      const msg = typeof error === 'object' ? JSON.stringify(error) : String(error);
      throw new SDKError(SDKErrorCode.ModelLoadFailed, `TTS creation failed: ${msg}`);
    } finally {
      freeConfig(configStruct, m);
    }
  }

  /** Unload the TTS voice. */
  async unloadVoice(): Promise<void> {
    this.cleanup();
    logger.info('TTS voice unloaded');
  }

  /** Check if a TTS voice is loaded. */
  get isVoiceLoaded(): boolean {
    return this._ttsHandle !== 0;
  }

  /** Get current voice ID. */
  get voiceId(): string {
    return this._currentVoiceId;
  }

  /** Get the sample rate of the loaded TTS model. */
  get sampleRate(): number {
    if (this._ttsHandle === 0) return 0;
    return SherpaONNXBridge.shared.module._SherpaOnnxOfflineTtsSampleRate(this._ttsHandle);
  }

  /** Get the number of speakers in the loaded model. */
  get numSpeakers(): number {
    if (this._ttsHandle === 0) return 0;
    return SherpaONNXBridge.shared.module._SherpaOnnxOfflineTtsNumSpeakers(this._ttsHandle);
  }

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

    if (this._ttsHandle === 0) {
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
      logger.debug(`Calling _SherpaOnnxOfflineTtsGenerate (handle=${this._ttsHandle})`);

      let audioPtr: number;
      try {
        audioPtr = m._SherpaOnnxOfflineTtsGenerate(this._ttsHandle, textPtr, sid, speed);
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
      const charsPerSec = processingTimeMs > 0 ? Math.round(text.length / processingTimeMs * 1000) : 0;
      AnalyticsEmitter.emitTTSSynthesisCompleted(
        crypto.randomUUID(), this._currentVoiceId, text.length,
        durationMs, numSamples * 4, processingTimeMs,
        charsPerSec, sampleRate, RAC_FRAMEWORK_ONNX,
      );

      logger.debug(`TTS generated ${durationMs}ms audio in ${processingTimeMs}ms`);
      return result;
    } finally {
      sherpa.free(textPtr);
    }
  }

  /** Clean up the TTS resources. */
  cleanup(): void {
    if (this._ttsHandle !== 0) {
      try {
        SherpaONNXBridge.shared.module._SherpaOnnxDestroyOfflineTts(this._ttsHandle);
      } catch { /* ignore */ }
      this._ttsHandle = 0;
    }
    this._currentVoiceId = '';
  }
}

export const TTS = new TTSImpl();
