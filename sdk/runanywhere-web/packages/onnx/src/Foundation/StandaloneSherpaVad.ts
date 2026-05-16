/**
 * StandaloneSherpaVad — wrapper around `_SherpaOnnxCreateVoiceActivityDetector`
 * (Silero VAD) on top of the standalone Sherpa Emscripten module.
 *
 * Struct packing for `SherpaOnnxVadModelConfig` is delegated to the
 * upstream `sherpa-onnx-vad.js` helper (`initSherpaOnnxVadModelConfig`)
 * loaded via `SherpaUpstreamHelpers`. The same upstream-helper pattern is
 * used by `StandaloneSherpaStt` and `StandaloneSherpaTts`; this avoids
 * re-implementing the byte layout of the Silero/TEN sub-configs in
 * TypeScript and stays aligned with future sherpa-onnx upstream changes.
 */

import { SDKLogger } from '@runanywhere/web/internal';
import type { StandaloneSherpaModule } from './StandaloneSherpaModule';
import {
  loadSherpaVADHelpers,
  type SherpaConfigHandle,
  type SherpaVADHelpers,
  type UpstreamVadConfig,
} from './SherpaUpstreamHelpers';

const logger = new SDKLogger('StandaloneSherpaVad');

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

let _helpersPromise: Promise<SherpaVADHelpers> | null = null;
function getVADHelpers(): Promise<SherpaVADHelpers> {
  if (!_helpersPromise) _helpersPromise = loadSherpaVADHelpers();
  return _helpersPromise;
}

export class StandaloneSherpaVad {
  private handle: number = 0;
  private cfgHandle: SherpaConfigHandle | null = null;

  constructor(private readonly module: StandaloneSherpaModule) {}

  /**
   * Load the Silero VAD model. Async because the upstream
   * `sherpa-onnx-vad.js` helper is fetched + compiled lazily.
   */
  async load(config: StandaloneSherpaVadConfig): Promise<void> {
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

    const helpers = await getVADHelpers();
    const upstreamConfig: UpstreamVadConfig = {
      sileroVad: {
        model: config.modelPath,
        threshold: config.threshold ?? 0.5,
        minSilenceDuration: config.minSilenceDurationSec ?? 0.5,
        minSpeechDuration: config.minSpeechDurationSec ?? 0.25,
        windowSize: config.windowSize ?? 512,
        maxSpeechDuration: config.maxSpeechDurationSec ?? 20,
      },
      sampleRate: config.sampleRate ?? 16000,
      numThreads: config.numThreads ?? 1,
      provider: config.provider ?? 'cpu',
      debug: config.debug ? 1 : 0,
    };

    const cfgHandle = helpers.initSherpaOnnxVadModelConfig(upstreamConfig, m);
    this.cfgHandle = cfgHandle;

    try {
      const handle = m._SherpaOnnxCreateVoiceActivityDetector(
        cfgHandle.ptr,
        config.bufferSizeInSeconds ?? 30,
      );
      if (!handle) {
        this.releaseConfigHandle();
        throw new Error(
          `_SherpaOnnxCreateVoiceActivityDetector returned NULL for model "${config.modelPath}". ` +
          'The Silero VAD model may be the v5 schema; sherpa-onnx 1.12.x requires v4.',
        );
      }
      this.handle = handle;
      logger.info(`Standalone Sherpa VAD loaded (handle=${handle}, model=${config.modelPath})`);
    } catch (err) {
      this.releaseConfigHandle();
      throw err;
    }
  }

  isLoaded(): boolean {
    return this.handle !== 0;
  }

  destroy(): void {
    if (!this.handle) {
      this.releaseConfigHandle();
      return;
    }
    const m = this.module;
    if (typeof m._SherpaOnnxDestroyVoiceActivityDetector === 'function') {
      m._SherpaOnnxDestroyVoiceActivityDetector(this.handle);
    }
    this.handle = 0;
    this.releaseConfigHandle();
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

  private releaseConfigHandle(): void {
    if (!this.cfgHandle) return;
    const handle = this.cfgHandle;
    this.cfgHandle = null;
    void getVADHelpers()
      .then((helpers) => helpers.freeConfig(handle, this.module))
      .catch((err) => {
        logger.warning(
          `Failed to free VAD config handle: ${err instanceof Error ? err.message : String(err)}`,
        );
      });
  }
}
