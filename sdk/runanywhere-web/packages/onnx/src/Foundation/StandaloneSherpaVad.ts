/**
 * StandaloneSherpaVad — direct C-API wrapper for `_SherpaOnnxCreateVoiceActivityDetector`
 * (Silero VAD) on top of the standalone Sherpa Emscripten module.
 *
 * Struct layout matches `SherpaOnnxVadModelConfig` from
 * `sherpa-onnx/c-api/c-api.h`:
 *
 *   silero_vad : { model* (i8*), threshold (f32), min_silence_duration (f32),
 *                  min_speech_duration (f32), window_size (i32),
 *                  max_speech_duration (f32) }   // 6 * 4 = 24 bytes
 *   sample_rate (i32)
 *   num_threads (i32)
 *   provider* (i8*)
 *   debug (i32)
 *   ten_vad : same shape as silero, all zero = disabled.
 *
 * Total: 24 + 4*4 + 24 = 64 bytes.
 */

import { SDKLogger } from '@runanywhere/web/internal';
import type { StandaloneSherpaModule } from './StandaloneSherpaModule';

const logger = new SDKLogger('StandaloneSherpaVad');

const SILERO_BLOCK_SIZE = 6 * 4;
const TEN_BLOCK_SIZE = 6 * 4;
const TOP_BLOCK_SIZE = 4 * 4;
const VAD_CONFIG_SIZE = SILERO_BLOCK_SIZE + TOP_BLOCK_SIZE + TEN_BLOCK_SIZE;

export interface StandaloneSherpaVadConfig {
  modelPath: string;
  threshold?: number;
  minSilenceDurationSec?: number;
  minSpeechDurationSec?: number;
  windowSize?: number;
  maxSpeechDurationSec?: number;
  sampleRate?: number;
  numThreads?: number;
  provider?: string;
  bufferSizeInSeconds?: number;
  debug?: boolean;
}

export class StandaloneSherpaVad {
  private handle: number = 0;

  constructor(private readonly module: StandaloneSherpaModule) {}

  load(config: StandaloneSherpaVadConfig): void {
    if (this.handle) {
      this.destroy();
    }

    const m = this.module;
    if (typeof m._SherpaOnnxCreateVoiceActivityDetector !== 'function') {
      throw new Error(
        'Standalone Sherpa module is missing _SherpaOnnxCreateVoiceActivityDetector. ' +
        'Rebuild via wasm/scripts/build-sherpa-onnx.sh.',
      );
    }

    const cfgPtr = m._malloc(VAD_CONFIG_SIZE);
    m.HEAPU8.fill(0, cfgPtr, cfgPtr + VAD_CONFIG_SIZE);

    const modelPath = config.modelPath;
    const modelPathLen = m.lengthBytesUTF8(modelPath) + 1;
    const modelPathPtr = m._malloc(modelPathLen);
    m.stringToUTF8(modelPath, modelPathPtr, modelPathLen);

    const providerStr = config.provider ?? 'cpu';
    const providerLen = m.lengthBytesUTF8(providerStr) + 1;
    const providerPtr = m._malloc(providerLen);
    m.stringToUTF8(providerStr, providerPtr, providerLen);

    // silero_vad
    m.setValue(cfgPtr + 0, modelPathPtr, 'i8*');
    m.setValue(cfgPtr + 4, config.threshold ?? 0.5, 'float');
    m.setValue(cfgPtr + 8, config.minSilenceDurationSec ?? 0.5, 'float');
    m.setValue(cfgPtr + 12, config.minSpeechDurationSec ?? 0.25, 'float');
    m.setValue(cfgPtr + 16, config.windowSize ?? 512, 'i32');
    m.setValue(cfgPtr + 20, config.maxSpeechDurationSec ?? 20, 'float');

    // top-level after silero block
    const topOffset = cfgPtr + SILERO_BLOCK_SIZE;
    m.setValue(topOffset + 0, config.sampleRate ?? 16000, 'i32');
    m.setValue(topOffset + 4, config.numThreads ?? 1, 'i32');
    m.setValue(topOffset + 8, providerPtr, 'i8*');
    m.setValue(topOffset + 12, config.debug ? 1 : 0, 'i32');

    try {
      const handle = m._SherpaOnnxCreateVoiceActivityDetector(
        cfgPtr,
        config.bufferSizeInSeconds ?? 30,
      );
      if (!handle) {
        throw new Error(
          `_SherpaOnnxCreateVoiceActivityDetector returned NULL for model "${modelPath}". ` +
          'The Silero VAD model may be the v5 schema; sherpa-onnx 1.12.x requires v4.',
        );
      }
      this.handle = handle;
      logger.info(`Standalone Sherpa VAD loaded (handle=${handle}, model=${modelPath})`);
    } finally {
      m._free(modelPathPtr);
      m._free(providerPtr);
      m._free(cfgPtr);
    }
  }

  isLoaded(): boolean {
    return this.handle !== 0;
  }

  destroy(): void {
    if (!this.handle) return;
    const m = this.module;
    if (typeof m._SherpaOnnxDestroyVoiceActivityDetector === 'function') {
      m._SherpaOnnxDestroyVoiceActivityDetector(this.handle);
    }
    this.handle = 0;
  }

  /**
   * Push samples through the detector. Returns `true` if any speech was
   * detected after consuming the chunk, `false` otherwise.
   */
  acceptWaveform(samples: Float32Array): boolean {
    if (!this.handle) {
      throw new Error('StandaloneSherpaVad: no model loaded; call load() first.');
    }
    const m = this.module;
    const accept = m._SherpaOnnxVoiceActivityDetectorAcceptWaveform;
    if (typeof accept !== 'function') {
      throw new Error('Standalone Sherpa module is missing _SherpaOnnxVoiceActivityDetectorAcceptWaveform.');
    }
    const bytes = samples.length * 4;
    const ptr = m._malloc(bytes);
    try {
      m.HEAPF32.set(samples, ptr / 4);
      accept(this.handle, ptr, samples.length);
      return this.isDetected();
    } finally {
      m._free(ptr);
    }
  }

  isDetected(): boolean {
    if (!this.handle) return false;
    const fn = this.module._SherpaOnnxVoiceActivityDetectorDetected;
    return typeof fn === 'function' && fn(this.handle) === 1;
  }

  isEmpty(): boolean {
    if (!this.handle) return true;
    const fn = this.module._SherpaOnnxVoiceActivityDetectorEmpty;
    if (typeof fn !== 'function') return true;
    return fn(this.handle) === 1;
  }

  reset(): void {
    if (!this.handle) return;
    const fn = this.module._SherpaOnnxVoiceActivityDetectorReset;
    if (typeof fn === 'function') fn(this.handle);
  }
}
